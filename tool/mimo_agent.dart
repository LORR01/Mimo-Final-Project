import 'dart:convert';
import 'dart:io';
import 'agent/collector.dart';
import 'agent/server.dart';
import 'agent/keys.dart';
import 'agent/clipboard.dart';

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(
      'Mimo Windows Agent: mimo-agent.exe [--enable-commands] [--enable-sharing]\nDefault: read-only telemetry. --enable-commands enables authenticated keyboard chords. --enable-sharing enables clipboard reading and file receiving.\nRun from the extracted Agent directory; data stays in .local/agent.',
    );
    return;
  }
  if (args.any(
    (arg) => !['--enable-commands', '--enable-sharing'].contains(arg),
  )) {
    stderr.writeln('Unknown argument. Use --help.');
    exitCode = 64;
    return;
  }
  final root = Directory.current.absolute;
  final state = Directory('${root.path}/.local/agent');
  final agent = MimoAgent(
    tailnet: TailnetReader(),
    collector: WindowsCollector(
      File('${root.path}/tool/agent/windows_metrics.ps1'),
    ),
    stateDirectory: state,
    clipboardSource: args.contains('--enable-sharing')
        ? WindowsClipboardSource()
        : null,
    receiveDirectory: args.contains('--enable-sharing')
        ? Directory(
            '${Platform.environment['USERPROFILE'] ?? root.path}/Downloads/Mimo',
          )
        : null,
    webRoot: Directory('${root.path}/build/web'),
    keyExecutor: args.contains('--enable-commands')
        ? WindowsKeyExecutor()
        : null,
  );
  await agent.start();
  // This local file is ignored by Git. Never put the code/token in a URL.
  await File('${state.path}/pairing.local.json').writeAsString(
    jsonEncode({
      'code': agent.pairingCode,
      'localUrl': 'http://127.0.0.1:${agent.port}',
    }),
    flush: true,
  );
  stdout.writeln(
    'Mimo Agent ${agent.keyExecutor == null ? 'read-only' : 'keyboard enabled'}: http://127.0.0.1:${agent.port}',
  );
  stdout.writeln(
    'Pairing code is in .local/agent/pairing.local.json (keep private).',
  );
  stdout.writeln(agent.error ?? 'Tailscale and telemetry sample ready.');
  ProcessSignal.sigint.watch().listen((_) async {
    await agent.stop();
    exit(0);
  });
}
