import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import '../tool/agent/keys.dart';
import '../tool/agent/server.dart';
import 'agent_server_test.dart' show FixtureTailnet, FixtureCollector;

class RecordingExecutor implements KeyExecutor {
  final List<List<String>> calls = [];
  @override
  Future<int> send(List<String> keys) async {
    calls.add([...keys]);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return keys.length * 2;
  }
}

void main() {
  test(
    'real command route authenticates, validates target/keys, deduplicates simultaneous requests, rate limits and rejects stale data',
    () async {
      final temp = await Directory.systemTemp.createTemp('mimo-command-test-');
      var clock = DateTime.now();
      final executor = RecordingExecutor();
      final agent = MimoAgent(
        tailnet: FixtureTailnet(),
        collector: FixtureCollector(() => clock),
        stateDirectory: temp,
        now: () => clock,
        keyExecutor: executor,
      );
      await agent.start(port: 0);
      final base = 'http://127.0.0.1:${agent.port}';
      Future<http.Response> post(
        String route,
        Map<String, dynamic> body, [
        String? token,
      ]) => http.post(
        Uri.parse('$base$route'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );
      try {
        const route = '/v1/devices/node-pc/keys';
        final request = {
          'keys': ['Ctrl', 'C'],
          'requestId': 'same-command',
        };
        expect((await post(route, request)).statusCode, 401);
        final paired =
            jsonDecode(
                  (await post('/v1/pair', {'code': agent.pairingCode})).body,
                )
                as Map;
        final token = paired['token'] as String;
        expect(
          (await post(
            '/v1/devices/node-phone/keys',
            request,
            token,
          )).statusCode,
          404,
        );
        expect(
          (await post(route, {
            'keys': ['powershell.exe'],
            'requestId': 'bad',
          }, token)).statusCode,
          400,
        );
        expect(
          (await post(route, {
            'keys': ['Ctrl', 'C'],
            'requestId': 'bad',
            'shell': 'calc',
          }, token)).statusCode,
          400,
        );
        final duplicate = await Future.wait([
          post(route, request, token),
          post(route, request, token),
        ]);
        expect(duplicate.every((r) => r.statusCode == 200), isTrue);
        expect(executor.calls, [
          ['Ctrl', 'C'],
        ]);
        expect(
          (await post(route, {
            'keys': ['Ctrl', 'V'],
            'requestId': 'same-command',
          }, token)).statusCode,
          409,
        );
        for (var i = 0; i < 4; i++) {
          expect(
            (await post(route, {
              'keys': ['F24'],
              'requestId': 'next-$i',
            }, token)).statusCode,
            200,
          );
        }
        expect(
          (await post(route, {
            'keys': ['F24'],
            'requestId': 'limited',
          }, token)).statusCode,
          429,
        );
        clock = clock.add(const Duration(seconds: 25));
        expect(
          (await post(route, {
            'keys': ['F24'],
            'requestId': 'stale',
          }, token)).statusCode,
          503,
        );
        expect(executor.calls.length, 5);
        clock = clock.add(const Duration(hours: 9));
        expect((await post(route, request, token)).statusCode, 401);
      } finally {
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
}
