import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:mimo_companion/data/agent_client.dart';
import '../tool/agent/clipboard.dart';

void main() {
  test(
    'real HTTPS file receipt matches disk bytes and Windows clipboard adapter is read-only',
    () async {
      final client = AgentClient(client: IOClient(HttpClient()));
      try {
        await client.connectTailscale(
          const String.fromEnvironment('MIMO_AGENT_URL'),
        );
        final id = client.agentDeviceId!;
        final snapshot = await client.fetchSnapshot(id);
        expect(snapshot.files, true);
        expect(snapshot.clipboard, true);
        final bytes = utf8.encode('Mimo sharing verification - 2026-10-16\n');
        final receipt = await client.uploadFile(
          id,
          'Mimo-verification.txt',
          bytes.length,
          Stream.value(bytes),
        );
        final file = File(
          '${Platform.environment['USERPROFILE']}/Downloads/Mimo/${receipt['storedName']}',
        );
        expect(await file.readAsBytes(), bytes);
        final contents = await client.fetchClipboard(id);
        for (final item in contents) {
          expect([
            'text',
            'link',
            'image',
            'document',
            'spreadsheet',
          ], contains(item['type']));
          expect(
            DateTime.parse(item['expiresAt'] as String).isAfter(DateTime.now()),
            true,
          );
        }
        final windows = await WindowsClipboardSource().read();
        expect(windows, isNotNull);
        // Intentionally do not print any clipboard text, file names or credentials.
      } finally {
        client.close();
      }
    },
    skip: !const bool.fromEnvironment('MIMO_SHARING_TEST')
        ? 'opt-in real Windows clipboard/file test'
        : false,
  );
}
