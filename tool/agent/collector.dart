import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

typedef AgentJson = Map<String, dynamic>;
Future<String> runBounded(
  String executable,
  List<String> arguments, {
  Duration timeout = const Duration(seconds: 12),
}) async {
  final process = await Process.start(executable, arguments, runInShell: false);
  final out = process.stdout.transform(utf8.decoder).join();
  final error = process.stderr.transform(utf8.decoder).join();
  final code = await process.exitCode.timeout(
    timeout,
    onTimeout: () {
      process.kill();
      throw const HttpException('Collector timeout');
    },
  );
  final output = await out;
  await error;
  if (code != 0) throw const HttpException('Collector process failed');
  return output.replaceFirst('\uFEFF', '').trim();
}

class WindowsCollector {
  WindowsCollector(this.script);
  final File script;
  Future<AgentJson> sample() async {
    if (!Platform.isWindows) {
      throw UnsupportedError('This collector currently supports Windows only');
    }
    final source = await script.readAsString();
    final bytes = ByteData(source.codeUnits.length * 2);
    for (int i = 0; i < source.codeUnits.length; i++) {
      bytes.setUint16(i * 2, source.codeUnitAt(i), Endian.little);
    }
    final encoded = base64Encode(bytes.buffer.asUint8List());
    final output = await runBounded('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-EncodedCommand',
      encoded,
    ]);
    return Map<String, dynamic>.from(jsonDecode(output) as Map);
  }
}

class TailnetReader {
  TailnetReader({String? executable})
    : executable =
          executable ??
          (Platform.isWindows
              ? r'C:\Program Files\Tailscale\tailscale.exe'
              : 'tailscale');
  final String executable;
  Future<AgentJson> whois(String ip) async => Map<String, dynamic>.from(
    jsonDecode(await runBounded(executable, ['whois', '--json', ip])) as Map,
  );
  Future<AgentJson> read() async {
    final raw =
        jsonDecode(await runBounded(executable, ['status', '--json'])) as Map;
    if (raw['BackendState'] != 'Running') {
      throw const HttpException('Tailscale is not running/logged in');
    }
    return Map<String, dynamic>.from(raw);
  }

  static AgentJson machine(Map raw) {
    final ips = (raw['TailscaleIPs'] as List? ?? []).cast<String>();
    final dns = (raw['DNSName'] as String? ?? '').replaceFirst(
      RegExp(r'\.$'),
      '',
    );
    return {
      'id': raw['ID'],
      'hostname': raw['HostName'],
      'ip':
          ips.where((ip) => !ip.contains(':')).firstOrNull ??
          ips.firstOrNull ??
          '',
      'os': raw['OS'],
      'online': raw['Online'] == true,
      'agentUrl': dns.isEmpty ? '' : 'https://$dns:8443',
    };
  }
}

/// Observed computer-online intervals, not retrospectively reconstructed usage.
/// Sleep, restart and long sampling gaps are never credited as usage.
class UsageLedger {
  UsageLedger({Map<String, num>? seconds}) : seconds = {...?seconds};
  final Map<String, num> seconds;
  DateTime? _previous;
  static String dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  void observe(DateTime now) {
    final before = _previous;
    _previous = now;
    seconds.putIfAbsent(dateKey(now), () => 0);
    if (before == null) return;
    final duration = now.difference(before);
    if (duration.isNegative || duration > const Duration(seconds: 20)) return;
    var cursor = before;
    while (cursor.isBefore(now)) {
      final midnight = DateTime(cursor.year, cursor.month, cursor.day + 1);
      final end = midnight.isBefore(now) ? midnight : now;
      final key = dateKey(cursor);
      seconds[key] =
          (seconds[key] ?? 0) + end.difference(cursor).inMilliseconds / 1000;
      cursor = end;
    }
  }

  List<AgentJson> week(DateTime now) {
    final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    const keys = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const thai = [
      'จันทร์',
      'อังคาร',
      'พุธ',
      'พฤหัสบดี',
      'ศุกร์',
      'เสาร์',
      'อาทิตย์',
    ];
    return List.generate(7, (i) {
      final date = DateTime(monday.year, monday.month, monday.day + i);
      final count = seconds[dateKey(date)];
      return {
        'key': keys[i],
        'labelTh': thai[i],
        'date': dateKey(date),
        'seconds': count,
        'minutes': count == null ? null : (count / 60).floor(),
        'percent': count == null
            ? 0.0
            : (count / 3600 / 15).clamp(0, 1).toDouble(),
      };
    });
  }
}
