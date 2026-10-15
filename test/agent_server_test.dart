import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import '../tool/agent/collector.dart';
import '../tool/agent/server.dart';

class FixtureTailnet extends TailnetReader {
  FixtureTailnet({
    this.peerOverrides = const {},
    this.nodeOverrides = const {},
  });
  final AgentJson peerOverrides, nodeOverrides;
  @override
  Future<AgentJson> whois(String ip) async => {
    'Node': {
      'StableID': ip == '100.64.1.2' ? 'node-phone' : 'node-pc',
      'User': ip == '100.64.1.3' ? 999 : 123,
      if (ip == '100.64.1.4') 'MachineAuthorized': false,
      ...nodeOverrides,
    },
    'UserProfile': {
      'ID': ip == '100.64.1.3' ? 999 : 123,
      'LoginName': ip == '100.64.1.3'
          ? 'other@example.test'
          : 'owner@example.test',
    },
  };
  @override
  Future<AgentJson> read() async => {
    'BackendState': 'Running',
    'Self': {
      'ID': 'node-pc',
      'UserID': 123,
      'HostName': 'test-pc',
      'DNSName': 'test-pc.test-tail.ts.net.',
      'OS': 'windows',
      'Online': true,
      'TailscaleIPs': ['100.64.1.1'],
    },
    'Peer': {
      'phone': {
        'ID': 'node-phone',
        'UserID': 123,
        'InNetworkMap': true,
        'HostName': 'phone',
        'OS': 'android',
        'Online': true,
        'TailscaleIPs': ['100.64.1.2'],
        ...peerOverrides,
      },
    },
  };
}

class FixtureCollector extends WindowsCollector {
  FixtureCollector(this.clock) : super(File('unused'));
  final DateTime Function() clock;
  @override
  Future<AgentJson> sample() async => {
    'sampledAt': clock().toIso8601String(),
    'readings': {'cpu': 23, 'gpu': 17, 'ramUsed': 8.5, 'ramTotal': 16},
    'availability': {'cpuTemp': 'No sensor', 'gpuTemp': 'No sensor'},
  };
}

void main() {
  test(
    'peer identity without MachineAuthorized requires current network membership, owner, address and nonexpired key',
    () async {
      for (final fixture in [
        FixtureTailnet(),
        FixtureTailnet(peerOverrides: {'InNetworkMap': false}),
        FixtureTailnet(peerOverrides: {'UserID': 999}),
        FixtureTailnet(
          peerOverrides: {
            'TailscaleIPs': ['100.64.1.9'],
          },
        ),
        FixtureTailnet(nodeOverrides: {'MachineAuthorized': false}),
        FixtureTailnet(nodeOverrides: {'KeyExpiry': '2020-01-01T00:00:00Z'}),
        FixtureTailnet(nodeOverrides: {'StableID': 'unknown-node'}),
      ]) {
        final temp = await Directory.systemTemp.createTemp('mimo-peer-auth-');
        final agent = MimoAgent(
          tailnet: fixture,
          collector: FixtureCollector(DateTime.now),
          stateDirectory: temp,
        );
        await agent.start(port: 0);
        try {
          final response = await http.post(
            Uri.parse('http://127.0.0.1:${agent.port}/v1/tailscale-session'),
            headers: {
              'X-Forwarded-Host': 'test-pc.test-tail.ts.net:8443',
              'X-Forwarded-Proto': 'https',
              'X-Forwarded-For': '100.64.1.2',
              'Tailscale-User-Login': 'owner@example.test',
            },
          );
          expect(
            response.statusCode,
            fixture.peerOverrides.isEmpty && fixture.nodeOverrides.isEmpty
                ? 200
                : 401,
          );
        } finally {
          await agent.stop();
          await temp.delete(recursive: true);
        }
      }
    },
  );
  test(
    'cancelling an APK download does not stop the Agent; APK MIME is correct',
    () async {
      final temp = await Directory.systemTemp.createTemp('mimo-static-test-');
      final web = await Directory(
        '${temp.path}/web/downloads',
      ).create(recursive: true);
      final apk = await File('${web.path}/test.apk').open(mode: FileMode.write);
      await apk.writeFrom([0x50, 0x4b, 3, 4]);
      await apk.truncate(16 * 1024 * 1024);
      await apk.close();
      final agent = MimoAgent(
        tailnet: FixtureTailnet(),
        collector: FixtureCollector(DateTime.now),
        stateDirectory: Directory('${temp.path}/state'),
        webRoot: Directory('${temp.path}/web'),
      );
      await agent.start(port: 0);
      final client = HttpClient();
      try {
        final response = await (await client.getUrl(
          Uri.parse('http://127.0.0.1:${agent.port}/downloads/test.apk'),
        )).close();
        expect(response.statusCode, 200);
        expect(
          response.headers.contentType?.mimeType,
          'application/vnd.android.package-archive',
        );
        await response.first;
        client.close(force: true);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(
          (await http.get(
            Uri.parse('http://127.0.0.1:${agent.port}/v1/health'),
          )).statusCode,
          200,
        );
      } finally {
        client.close(force: true);
        await agent.stop();
        expect(
          temp.absolute.path.startsWith(
            '${Directory.systemTemp.absolute.path}${Platform.pathSeparator}',
          ),
          isTrue,
        );
        await temp.delete(recursive: true);
      }
    },
  );
  test(
    'usage ledger splits midnight and never invents sleep/offline/history',
    () {
      final ledger = UsageLedger();
      ledger.observe(DateTime(2026, 10, 14, 23, 59, 55));
      ledger.observe(DateTime(2026, 10, 15, 0, 0, 5));
      expect(ledger.seconds['2026-10-14'], 5);
      expect(ledger.seconds['2026-10-15'], 5);
      ledger.observe(DateTime(2026, 10, 15, 4));
      expect(ledger.seconds['2026-10-15'], 5);
      final days = ledger.week(DateTime(2026, 10, 15));
      expect(days.first['minutes'], isNull);
      expect(days[3]['seconds'], 5);
    },
  );
  test(
    'agent authenticates, separates tailnet readiness and only exposes local read-only metrics',
    () async {
      final temp = await Directory.systemTemp.createTemp('mimo-agent-test-');
      var clock = DateTime.now();
      final agent = MimoAgent(
        tailnet: FixtureTailnet(),
        collector: FixtureCollector(() => clock),
        stateDirectory: temp,
        now: () => clock,
      );
      await agent.start(port: 0);
      final base = 'http://127.0.0.1:${agent.port}';
      try {
        expect((await http.get(Uri.parse('$base/v1/devices'))).statusCode, 401);
        final sessionUrl = Uri.parse('$base/v1/tailscale-session');
        expect((await http.post(sessionUrl)).statusCode, 401);
        final identityHeaders = {
          'Origin': 'https://test-pc.test-tail.ts.net:8443',
          'X-Forwarded-Host': 'test-pc.test-tail.ts.net:8443',
          'X-Forwarded-Proto': 'https',
          'X-Forwarded-For': '100.64.1.2',
          'Tailscale-User-Login': 'owner@example.test',
        };
        for (final invalid in [
          {'Tailscale-User-Login': 'other@example.test'},
          {'X-Forwarded-For': '100.64.1.2, 100.64.1.1'},
          {'X-Forwarded-Host': 'untrusted.example'},
          {'X-Forwarded-Proto': 'http'},
          {'Tailscale-Funnel-Request': '?1'},
          {
            'X-Forwarded-For': '100.64.1.3',
            'Tailscale-User-Login': 'other@example.test',
          },
          {'X-Forwarded-For': '100.64.1.4'},
        ]) {
          expect(
            (await http.post(
              sessionUrl,
              headers: {...identityHeaders, ...invalid},
            )).statusCode,
            401,
          );
        }
        final automatic = await http.post(sessionUrl, headers: identityHeaders);
        expect(automatic.statusCode, 200);
        final autoSession = jsonDecode(automatic.body) as Map;
        expect(autoSession['clientDeviceId'], 'node-phone');
        final withoutSelf =
            jsonDecode(
                  (await http.get(
                    Uri.parse('$base/v1/devices'),
                    headers: {
                      'Authorization': 'Bearer ${autoSession['token']}',
                    },
                  )).body,
                )
                as Map;
        expect((withoutSelf['devices'] as List).length, 1);
        expect(withoutSelf['devices'][0]['machine']['id'], 'node-pc');
        expect(
          (await http.get(Uri.parse('$base/v1/health'))).body,
          contains('readOnly'),
        );
        expect(
          (await http.post(
            Uri.parse('$base/v1/pair'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'code': 'bad'}),
          )).statusCode,
          401,
        );
        final pair = await http.post(
          Uri.parse('$base/v1/pair'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'code': agent.pairingCode}),
        );
        expect(pair.statusCode, 200);
        final token = (jsonDecode(pair.body) as Map)['token'] as String,
            headers = {'Authorization': 'Bearer $token'};
        final devices =
            jsonDecode(
                  (await http.get(
                    Uri.parse('$base/v1/devices'),
                    headers: headers,
                  )).body,
                )
                as Map;
        expect(devices['devices'][0]['machine']['id'], 'node-pc');
        expect(devices['devices'][1]['agent']['status'], 'unknown');
        final secureOrigin = await http.get(
          Uri.parse('$base/v1/devices'),
          headers: {
            ...headers,
            'Origin': 'https://test-pc.test-tail.ts.net:8443',
          },
        );
        expect(secureOrigin.statusCode, 200);
        expect(
          secureOrigin.headers['access-control-allow-origin'],
          'https://test-pc.test-tail.ts.net:8443',
        );
        final data =
            jsonDecode(
                  (await http.get(
                    Uri.parse('$base/v1/devices/node-pc/snapshot'),
                    headers: headers,
                  )).body,
                )
                as Map;
        expect(data['readings']['cpu'], 23);
        expect((data['readings'] as Map).containsKey('cpuTemp'), isFalse);
        expect(data['capabilities']['commands'], isFalse);
        expect(data['weekly']['source'], 'observed_online');
        expect(
          (await http.get(
            Uri.parse('$base/v1/devices/node-phone/snapshot'),
            headers: headers,
          )).statusCode,
          404,
        );
        expect(
          (await http.post(
            Uri.parse('$base/v1/commands'),
            headers: headers,
          )).statusCode,
          405,
        );
        expect(
          (await http.get(
            Uri.parse('$base/v1/devices'),
            headers: {...headers, 'Origin': 'https://untrusted.example'},
          )).statusCode,
          403,
        );
        clock = clock.add(const Duration(hours: 9));
        expect(
          (await http.get(
            Uri.parse('$base/v1/devices'),
            headers: headers,
          )).statusCode,
          401,
        );
      } finally {
        await agent.stop();
        expect(
          temp.path.startsWith(
            '${Directory.systemTemp.path}${Platform.pathSeparator}',
          ),
          isTrue,
        );
        await temp.delete(recursive: true);
      }
    },
  );
}
