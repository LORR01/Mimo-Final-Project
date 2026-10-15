import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mimo_companion/data/agent_client.dart';

void main() {
  test(
    'selected PC gets its own verified Agent session; gateway token is never forwarded',
    () async {
      final seen = <String>[];
      final expiry = DateTime.now()
          .add(const Duration(hours: 1))
          .toIso8601String();
      String targetId = 'second-pc';
      String endpoint = 'https://second.test-tail.ts.net:8443';
      Future<http.Response> handleTarget(http.Request r) async {
        seen.add(r.url.path);
        expect(r.url.host, 'second.test-tail.ts.net');
        if (r.url.path == '/v1/tailscale-session') {
          return http.Response(
            jsonEncode({
              'token': 'target-token',
              'expiresAt': expiry,
              'deviceId': targetId,
            }),
            200,
          );
        }
        expect(r.headers['Authorization'], 'Bearer target-token');
        if (r.url.path.endsWith('/keys')) {
          return http.Response(
            jsonEncode({'deviceId': targetId, 'sent': true}),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'deviceId': targetId,
            'sampledAt': DateTime.now().toIso8601String(),
            'readings': {'cpu': 55},
            'weekly': {'days': [], 'label': 'observed'},
            'capabilities': {'commands': true},
          }),
          200,
        );
      }

      final gateway = MockClient((r) async {
        if (r.url.path == '/v1/tailscale-session') {
          return http.Response(
            jsonEncode({
              'token': 'gateway-token',
              'expiresAt': expiry,
              'deviceId': 'gateway-pc',
            }),
            200,
          );
        }
        expect(r.url.path, '/v1/devices');
        expect(r.headers['Authorization'], 'Bearer gateway-token');
        return http.Response(
          jsonEncode({
            'devices': [
              {
                'machine': {
                  'id': 'second-pc',
                  'hostname': 'second',
                  'ip': '100.64.1.2',
                  'os': 'windows',
                  'online': true,
                  'agentUrl': endpoint,
                },
                'agent': {'status': 'unknown'},
              },
            ],
          }),
          200,
        );
      });
      final client = AgentClient(
        client: gateway,
        targetClientFactory: () => MockClient(handleTarget),
      );
      try {
        await client.connectTailscale('https://gateway.test-tail.ts.net:8443');
        await client.discover('live');
        expect((await client.fetchSnapshot('second-pc')).readings['cpu'], 55);
        await client.sendShortcut('second-pc', ['Ctrl', 'C']);
        expect(seen.where((p) => p == '/v1/tailscale-session').length, 1);
        expect(seen.last, '/v1/devices/second-pc/keys');
        // A different tailnet URL must be rejected before any session/key request.
        endpoint = 'https://second.other-tail.ts.net:8443';
        await client.discover('live');
        await expectLater(
          client.fetchSnapshot('second-pc'),
          throwsA(isA<AgentException>()),
        );
        endpoint = 'https://second.test-tail.ts.net:8443';
        targetId = 'wrong-pc';
        await client.connectTailscale('https://gateway.test-tail.ts.net:8443');
        await client.discover('live');
        await expectLater(
          client.fetchSnapshot('second-pc'),
          throwsA(isA<AgentException>()),
        );
        expect(seen.last, '/v1/tailscale-session');
      } finally {
        client.close();
      }
    },
  );
}
