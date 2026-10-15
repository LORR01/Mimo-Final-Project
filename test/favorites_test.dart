import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:mimo_companion/data/agent_client.dart';
import 'package:mimo_companion/data/services.dart';
import 'package:mimo_companion/domain/models.dart';
import 'package:mimo_companion/state/mimo_store.dart';
import '../tool/agent/clipboard.dart';
import '../tool/agent/server.dart';
import 'agent_server_test.dart' show FixtureTailnet, FixtureCollector;
import 'sharing_test.dart' show FixtureClipboard;

void main() {
  test(
    'favorite text and attachment survive expiry, cache pressure and Agent restart; unpin resumes TTL, delete removes archive',
    () async {
      var clock = DateTime.now();
      final temp = await Directory.systemTemp.createTemp('mimo-permanent-');
      var source = FixtureClipboard()
        ..value = ClipboardBatch('first', [
          const ClipboardItem(type: 'text', text: 'keep text'),
          ClipboardItem(
            type: 'document',
            text: 'keep.pdf',
            name: 'keep.pdf',
            bytes: Uint8List.fromList([37, 80, 68, 70]),
          ),
        ]);
      MimoAgent create() => MimoAgent(
        tailnet: FixtureTailnet(),
        collector: FixtureCollector(() => clock),
        stateDirectory: temp,
        clipboardSource: source,
        now: () => clock,
      );
      var agent = create();
      final client = AgentClient(client: IOClient(HttpClient()));
      Future<void> connect() async {
        await agent.start(port: 0);
        await client.pair('http://127.0.0.1:${agent.port}', agent.pairingCode);
      }

      await connect();
      try {
        final items = await client.fetchClipboard('node-pc');
        final text =
            items.firstWhere((c) => c['type'] == 'text')['id'] as String;
        final file =
            items.firstWhere((c) => c['type'] == 'document')['id'] as String;
        for (final id in [text, file]) {
          final pinned = await client.setClipboardFavorite('node-pc', id, true);
          expect(pinned['isFavorite'], true);
          expect(pinned['expiresAt'], null);
        }
        for (var i = 0; i < 55; i++) {
          source.value = ClipboardBatch('change-$i', [
            ClipboardItem(type: 'text', text: 'temporary $i'),
          ]);
          await agent.sampleClipboard();
        }
        clock = clock.add(const Duration(minutes: 31));
        await agent.sample();
        final retained = await client.fetchClipboard('node-pc');
        expect(retained.length, 2, reason: jsonEncode(retained));
        expect(await client.fetchClipboardFile('node-pc', file), [
          37,
          80,
          68,
          70,
        ]);
        await agent.stop();
        source = FixtureClipboard();
        agent = create();
        await connect();
        expect(
          (await client.fetchClipboard('node-pc')).map((c) => c['id']).toSet(),
          {text, file},
        );
        expect(await client.fetchClipboardFile('node-pc', file), [
          37,
          80,
          68,
          70,
        ]);
        final unpinned = await client.setClipboardFavorite(
          'node-pc',
          text,
          false,
        );
        expect(
          DateTime.parse(unpinned['expiresAt'] as String).difference(clock),
          const Duration(minutes: 30),
        );
        await client.deleteClipboard('node-pc', file);
        expect(await File('${temp.path}/favorites/$file.bin').exists(), false);
        clock = clock.add(const Duration(minutes: 30));
        await agent.sample();
        expect(await client.fetchClipboard('node-pc'), isEmpty);
        expect(
          jsonDecode(
            await File('${temp.path}/favorites/favorites.json').readAsString(),
          ),
          isEmpty,
        );
      } finally {
        client.close();
        await agent.stop();
        await temp.delete(recursive: true);
      }
    },
  );

  test(
    'local Favorite survives preferences reload and expiry; unpin returns to 30-minute timer',
    () async {
      final seed =
          jsonDecode(File('assets/data/seed.json').readAsStringSync()) as Json;
      final repository = MemoryRepository();
      final store = MimoStore(repository: repository, liveMode: true);
      await store.initialize(fixture: seed, simulate: false);
      store.saveDevice(
        'saved-pc',
        'My PC',
        candidate: const DiscoveredDevice(
          TailMachine(
            id: 'saved-pc',
            hostname: 'pc',
            ip: '100.64.1.1',
            os: 'windows',
            online: true,
          ),
          AgentStatus.ready,
        ),
      );
      store.addClip('permanent local text');
      final id = store.clips.single['id'] as String;
      await store.toggleFavorite(id);
      store.clips.single['expiresAt'] = DateTime.now()
          .subtract(const Duration(days: 1))
          .toIso8601String();
      store.purgeClipboard();
      expect(store.clips.length, 1);
      await store.flush();
      final restored = MimoStore(repository: repository, liveMode: true);
      await restored.initialize(fixture: seed, simulate: false);
      expect(restored.clips.single['preview'], 'permanent local text');
      await restored.toggleFavorite(id);
      expect(
        DateTime.parse(
          restored.clips.single['expiresAt'] as String,
        ).isAfter(DateTime.now().add(const Duration(minutes: 29))),
        true,
      );
      restored.clips.single['expiresAt'] = DateTime.now()
          .subtract(const Duration(seconds: 1))
          .toIso8601String();
      restored.purgeClipboard();
      expect(restored.clips, isEmpty);
      store.dispose();
      restored.dispose();
    },
  );
}
