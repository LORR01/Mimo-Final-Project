import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:mimo_companion/data/agent_client.dart';

void main() {
  test(
    'owner authenticated HTTPS reaches real Windows SendInput with harmless F24',
    () async {
      final client = AgentClient(client: IOClient(HttpClient()));
      try {
        await client.connectTailscale(
          const String.fromEnvironment('MIMO_AGENT_URL'),
        );
        final snapshot = await client.fetchSnapshot(client.agentDeviceId!);
        expect(snapshot.commands, isTrue);
        await client.sendShortcut(client.agentDeviceId!, ['F24']);
      } finally {
        client.close();
      }
    },
    skip: !const bool.fromEnvironment('MIMO_COMMAND_TEST')
        ? 'opt-in real keystroke test'
        : false,
  );
}
