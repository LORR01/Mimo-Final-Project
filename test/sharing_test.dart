import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:mimo_companion/data/agent_client.dart';
import 'package:mimo_companion/data/services.dart';
import 'package:mimo_companion/domain/models.dart';
import 'package:mimo_companion/state/mimo_store.dart';
import '../tool/agent/clipboard.dart';
import '../tool/agent/server.dart';
import '../tool/agent/sharing.dart';
import 'agent_server_test.dart' show FixtureTailnet, FixtureCollector;

class FixtureClipboard extends ClipboardSource {
  ClipboardBatch? value;
  @override
  Future<ClipboardBatch?> read() async => value;
}

void main() {
  test(
    'authenticated streamed upload writes exact bytes, isolates target, rejects traversal/oversize, never overwrites',
    () async {
      final temp = await Directory.systemTemp.createTemp('mimo-sharing-');
      final inbox = Directory('${temp.path}/inbox');
      final agent = MimoAgent(
        tailnet: FixtureTailnet(),
        collector: FixtureCollector(DateTime.now),
        stateDirectory: Directory('${temp.path}/state'),
        receiveDirectory: inbox,
      );
      await agent.start(port: 0);
      final client = AgentClient(client: IOClient(HttpClient()));
      final base = 'http://127.0.0.1:${agent.port}';
      try {
        expect(
          (await http.post(
            Uri.parse('$base/v1/devices/node-pc/files'),
            body: [1, 2],
          )).statusCode,
          401,
        );
        await client.pair(base, agent.pairingCode);
        final bytes = List<int>.generate(8193, (i) => i % 256);
        for (var attempt = 0; attempt < 2; attempt++) {
          final receipt = await client.uploadFile(
            'node-pc',
            'ทดสอบ.txt',
            bytes.length,
            Stream.fromIterable([bytes.sublist(0, 1000), bytes.sublist(1000)]),
          );
          expect(receipt['bytes'], bytes.length);
          expect(
            await File('${inbox.path}/${receipt['storedName']}').readAsBytes(),
            bytes,
          );
        }
        expect(await inbox.list().length, 2);
        await expectLater(
          client.uploadFile('other-pc', 'test.txt', 2, Stream.value([1, 2])),
          throwsA(isA<AgentException>()),
        );
        for (final name in [
          '../outside.txt',
          r'C:\secret.txt',
          'NUL.txt',
          'bad:name.txt',
          'trailing.',
        ]) {
          expect(
            () => safeUploadName(base64Url.encode(utf8.encode(name))),
            throwsFormatException,
          );
        }
        await expectLater(
          client.uploadFile('node-pc', '../outside.txt', 1, Stream.value([0])),
          throwsA(anything),
        );
        await expectLater(
          client.uploadFile(
            'node-pc',
            'large.bin',
            maxUploadBytes + 1,
            const Stream.empty(),
          ),
          throwsA(isA<AgentException>()),
        );
        expect(await inbox.list().length, 2);
      } finally {
        client.close();
        await agent.stop();
        await temp.delete(recursive: true);
      }
    },
  );

  test(
    'all clipboard categories, attachment auth/target, dedup and exact 30-minute expiry',
    () async {
      var clock = DateTime.now();
      final source = FixtureClipboard()
        ..value = ClipboardBatch('copy-1', [
          const ClipboardItem(type: 'text', text: 'ภาษาไทย'),
          const ClipboardItem(type: 'link', text: 'https://example.test'),
          ClipboardItem(
            type: 'image',
            text: 'image',
            name: 'picture.png',
            bytes: Uint8List.fromList([137, 80, 78, 71]),
          ),
          ClipboardItem(
            type: 'document',
            text: 'report.pdf',
            name: 'report.pdf',
            bytes: Uint8List.fromList([37, 80, 68, 70]),
          ),
          ClipboardItem(
            type: 'spreadsheet',
            text: 'A\tB\n1\t2',
            name: 'table.html',
            bytes: Uint8List.fromList(
              utf8.encode('<table><tr><td>A</td></tr></table>'),
            ),
          ),
        ]);
      final temp = await Directory.systemTemp.createTemp('mimo-clips-');
      final agent = MimoAgent(
        tailnet: FixtureTailnet(),
        collector: FixtureCollector(() => clock),
        stateDirectory: temp,
        clipboardSource: source,
        now: () => clock,
      );
      await agent.start(port: 0);
      final client = AgentClient(client: IOClient(HttpClient()));
      final base = 'http://127.0.0.1:${agent.port}';
      try {
        await client.pair(base, agent.pairingCode);
        final items = await client.fetchClipboard('node-pc');
        expect(items.map((c) => c['type']).toSet(), {
          'text',
          'link',
          'image',
          'document',
          'spreadsheet',
        });
        expect((await client.fetchClipboard('node-pc')).length, 5);
        final image = items.firstWhere((c) => c['type'] == 'image');
        expect(
          await client.fetchClipboardFile('node-pc', image['id'] as String),
          [137, 80, 78, 71],
        );
        expect(
          (await http.get(
            Uri.parse('$base/v1/devices/node-pc/clipboard/${image['id']}/file'),
          )).statusCode,
          401,
        );
        await expectLater(
          client.fetchClipboardFile('other-pc', image['id'] as String),
          throwsA(isA<AgentException>()),
        );
        clock = clock.add(const Duration(minutes: 30));
        await agent.sample();
        expect(await client.fetchClipboard('node-pc'), isEmpty);
        await expectLater(
          client.fetchClipboardFile('node-pc', image['id'] as String),
          throwsA(isA<AgentException>()),
        );
        // Unchanged Windows sequence must not resurrect expired content.
        expect(await client.fetchClipboard('node-pc'), isEmpty);
        source.value = const ClipboardBatch('copy-2', [
          ClipboardItem(type: 'text', text: 'new'),
        ]);
        expect(
          (await client.fetchClipboard('node-pc')).single['preview'],
          'new',
        );
      } finally {
        client.close();
        await agent.stop();
        await temp.delete(recursive: true);
      }
    },
  );

  test(
    'live store imports clipboard, deduplicates notices, deletes/expiry, device transitions and file receipts',
    () async {
      final source = FixtureClipboard()
        ..value = const ClipboardBatch('1', [
          ClipboardItem(type: 'text', text: 'first'),
        ]);
      final temp = await Directory.systemTemp.createTemp('mimo-live-sharing-');
      final agent = MimoAgent(
        tailnet: FixtureTailnet(),
        collector: FixtureCollector(DateTime.now),
        stateDirectory: Directory('${temp.path}/state'),
        clipboardSource: source,
        receiveDirectory: Directory('${temp.path}/inbox'),
      );
      await agent.start(port: 0);
      final client = AgentClient(client: IOClient(HttpClient()));
      final repository = MemoryRepository();
      final store = MimoStore(
        repository: repository,
        discovery: client,
        liveMode: true,
      );
      try {
        await store.initialize(
          fixture:
              jsonDecode(File('assets/data/seed.json').readAsStringSync())
                  as Json,
          simulate: false,
        );
        await client.pair('http://127.0.0.1:${agent.port}', agent.pairingCode);
        await store.searchDevices('live');
        final candidate = store.discovered.firstWhere(
          (d) => d.machine.id == 'node-pc',
        );
        store.saveDevice('node-pc', 'คอมทำงาน', candidate: candidate);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await store.refreshLive();
        expect(store.clips.single['preview'], 'first');
        await store.flush();
        expect(
          jsonEncode(repository.value),
          isNot(contains('"preview":"first"')),
        );
        source.value = const ClipboardBatch('2', [
          ClipboardItem(type: 'link', text: 'https://example.test/new'),
        ]);
        await store.refreshLive();
        expect(store.unreadNotifications, 1);
        await store.refreshLive();
        expect(store.unreadNotifications, 1);
        final id = store.clips.first['id'] as String;
        await store.removeClip(id);
        await store.refreshLive();
        expect(store.clips.any((c) => c['id'] == id), false);
        store.observeOnline('node-pc', false);
        store.observeOnline('node-pc', false);
        store.observeOnline('node-pc', true);
        expect(store.unreadNotifications, 3);
        store.readNotifications();
        expect(store.unreadNotifications, 0);
        store.clips.single['expiresAt'] = DateTime.now()
            .subtract(const Duration(seconds: 1))
            .toIso8601String();
        store.purgeClipboard();
        expect(store.clips, isEmpty);
        final transfer = await store.sendRealFile(
          deviceId: 'node-pc',
          name: 'real.txt',
          size: 3,
          bytes: Stream.value([1, 2, 3]),
        );
        expect(transfer.done, true);
        expect(transfer.storedName, isNotNull);
        expect(transfer.progress, 1);
      } finally {
        store.dispose();
        await agent.stop();
        await temp.delete(recursive: true);
      }
    },
  );
}
