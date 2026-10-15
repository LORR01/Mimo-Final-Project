import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:mimo_companion/data/agent_client.dart';

void main() {
  test(
    'real Serve identity connects without pairing code and excludes caller',
    () async {
      const url = String.fromEnvironment('MIMO_AGENT_URL');
      expect(url, isNotEmpty);
      final client = AgentClient(client: IOClient(HttpClient()));
      try {
        await client.connectTailscale(url);
        expect(client.connected, isTrue);
        expect(client.clientDeviceId, isNotNull);
        final devices = await client.discover('live');
        expect(
          devices.any((d) => d.machine.id == client.clientDeviceId),
          isFalse,
        );
        expect(devices.map((d) => d.machine.id).toSet().length, devices.length);
        // API check of the Agent itself; the UI correctly excludes it when this PC is the caller.
        final snapshot = await client.fetchSnapshot(client.agentDeviceId!);
        expect(snapshot.readings['ramTotal'], greaterThan(0));
      } finally {
        client.close();
      }
    },
    skip: !const bool.fromEnvironment('MIMO_IDENTITY_TEST')
        ? 'opt-in real Tailscale HTTPS identity test'
        : false,
  );
}
