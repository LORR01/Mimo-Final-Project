import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mimo_companion/data/agent_client.dart';
import 'package:mimo_companion/data/services.dart';
import 'package:mimo_companion/domain/models.dart';
import 'package:mimo_companion/state/mimo_store.dart';

AgentClient fixtureClient({
  bool fail = false,
  String? snapshotId,
  String? callerId,
}) => AgentClient(
  client: MockClient((request) async {
    Map<String, dynamic> result;
    if (request.url.path == '/v1/pair' ||
        request.url.path == '/v1/tailscale-session') {
      result = {
        'token': 'test-session',
        if (request.url.path == '/v1/tailscale-session')
          'clientDeviceId': callerId,
        'expiresAt': DateTime.now()
            .add(const Duration(hours: 1))
            .toIso8601String(),
      };
    } else {
      expect(request.headers['Authorization'], 'Bearer test-session');
      if (fail) return http.Response(jsonEncode({'error': 'offline'}), 503);
      if (request.url.path == '/v1/devices') {
        result = {
          'devices': [
            {
              'machine': {
                'id': 'live-pc',
                'hostname': 'actual-host',
                'ip': '100.64.1.1',
                'os': 'windows',
                'online': true,
              },
              'agent': {'status': 'ready'},
            },
          ],
        };
      } else {
        result = {
          'deviceId': snapshotId ?? 'live-pc',
          'sampledAt': DateTime.now().toIso8601String(),
          'readings': {'cpu': 23, 'gpu': 17, 'ramUsed': 8.5, 'ramTotal': 16},
          'availability': {
            'cpuTemp': 'Sensor unavailable',
            'gpuTemp': 'Sensor unavailable',
          },
          'weekly': {
            'label': 'Observed online',
            'days': [
              {
                'key': 'Mon',
                'labelTh': 'จันทร์',
                'minutes': null,
                'percent': 0.0,
              },
            ],
          },
        };
      }
    }
    return http.Response.bytes(
      utf8.encode(jsonEncode(result)),
      200,
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  }),
);
void main() {
  final seed =
      jsonDecode(File('assets/data/seed.json').readAsStringSync()) as Json;
  test(
    'Tailscale connection needs no code and hides saved caller without deleting alias',
    () async {
      final client = fixtureClient(callerId: 'live-pc');
      final repository = MemoryRepository();
      final store = MimoStore(
        repository: repository,
        discovery: client,
        liveMode: true,
      );
      await store.initialize(fixture: seed, simulate: false);
      await client.pair('http://127.0.0.1:8765', '123456');
      await store.searchDevices('live');
      store.saveDevice(
        'live-pc',
        'ชื่อที่เก็บไว้',
        candidate: store.discovered.single,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await client.connectTailscale('https://test-pc.example.ts.net:8443');
      await store.searchDevices('live');
      expect(client.connected, isTrue);
      expect(store.discovered, isEmpty);
      expect(store.visibleDevices, isEmpty);
      expect(store.active, isNull);
      await store.flush();
      expect(store.devices.single.displayName, 'ชื่อที่เก็บไว้');
      expect(jsonEncode(repository.value), isNot(contains('test-session')));
      store.dispose();
    },
  );
  test(
    'live mode contains no demo seeds, uses real payload, missing temperature is not zero, writes have no token',
    () async {
      final client = fixtureClient(), repository = MemoryRepository();
      final store = MimoStore(
        repository: repository,
        discovery: client,
        liveMode: true,
      );
      await store.initialize(fixture: seed, simulate: false);
      expect(store.devices, isEmpty);
      expect(store.weeklyTotal, '—');
      await client.pair('http://127.0.0.1:8765', '123456');
      await store.searchDevices('live');
      expect(store.discovered.single.machine.hostname, 'actual-host');
      final candidate = store.discovered.single;
      store.saveDevice(candidate.machine.id, 'คอมทำงาน', candidate: candidate);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await store.refreshLive();
      expect(store.metrics.first.value, '23%', reason: store.liveError);
      expect(store.metrics[3].value, '—');
      expect(store.metrics[3].caption, 'Sensor unavailable');
      expect(store.metrics[2].value, '8.5 GB');
      expect(store.canRunCommands, isFalse);
      expect(store.sendFile(name: 'blocked.txt', size: 1), isNull);
      expect(store.weeklyTotal, '—');
      await store.flush();
      expect(jsonEncode(repository.value), isNot(contains('test-session')));
      store.disconnectAgent();
      expect(store.metrics.first.value, '—');
      store.dispose();
    },
  );
  test(
    'client refuses insecure remote URL and wrong machine identity',
    () async {
      final client = fixtureClient(snapshotId: 'another-device');
      await expectLater(
        client.pair('http://100.64.1.1:8765', '123456'),
        throwsA(isA<AgentException>()),
      );
      await client.pair('http://127.0.0.1:8765', '123456');
      await expectLater(
        client.fetchSnapshot('live-pc'),
        throwsA(isA<AgentException>()),
      );
      client.close();
    },
  );
  test('failed API leaves error and never returns mock discovery', () async {
    final client = fixtureClient(fail: true);
    await client.pair('http://127.0.0.1:8765', '123456');
    final store = MimoStore(
      repository: MemoryRepository(),
      discovery: client,
      liveMode: true,
    );
    await store.initialize(fixture: seed, simulate: false);
    await store.searchDevices('live');
    expect(store.discoveryState, DiscoveryState.error);
    expect(store.discovered, isEmpty);
    expect(store.devices, isEmpty);
    store.dispose();
  });
}
