import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'collector.dart';
import 'keys.dart';
import 'clipboard.dart';
import 'sharing.dart';
import 'favorites.dart';
import 'package:mimo_companion/domain/shortcuts.dart';

String randomSecret([int count = 32]) {
  final random = Random.secure();
  return base64UrlEncode(
    List.generate(count, (_) => random.nextInt(256)),
  ).replaceAll('=', '');
}

bool secretEquals(String a, String b) {
  var different = a.length ^ b.length;
  final size = max(a.length, b.length);
  for (int i = 0; i < size; i++) {
    different |=
        (i < a.length ? a.codeUnitAt(i) : 0) ^
        (i < b.length ? b.codeUnitAt(i) : 0);
  }
  return different == 0;
}

class MimoAgent {
  MimoAgent({
    required this.tailnet,
    required this.collector,
    required this.stateDirectory,
    this.webRoot,
    this.now = DateTime.now,
    this.keyExecutor,
    this.clipboardSource,
    this.receiveDirectory,
  });
  final TailnetReader tailnet;
  final WindowsCollector collector;
  final Directory stateDirectory;
  final Directory? webRoot;
  final DateTime Function() now;
  final KeyExecutor? keyExecutor;
  final ClipboardSource? clipboardSource;
  final Directory? receiveDirectory;
  final List<AgentJson> _clips = [];
  late final FavoriteArchive _favoriteArchive = FavoriteArchive(
    Directory('${stateDirectory.path}/favorites'),
  );
  bool _editingFavorite = false;
  final Map<String, Uint8List> _clipFiles = {};
  void expireClipboard() {
    if (_editingFavorite) return;
    _clips.removeWhere((item) {
      if (item['isFavorite'] == true) return false;
      if (DateTime.parse(item['expiresAt'] as String).isAfter(now())) {
        return false;
      }
      _clipFiles.remove(item['id']);
      return true;
    });
  }

  String? _lastClipboard;
  int _clipSequence = 0;
  bool _uploading = false;
  bool _readingClipboard = false;
  Future<void> sampleClipboard() async {
    if (clipboardSource == null || _readingClipboard || _editingFavorite) {
      return;
    }
    _readingClipboard = true;
    try {
      expireClipboard();
      final batch = await clipboardSource!.read();
      if (batch == null || batch.version == _lastClipboard) return;
      _lastClipboard = batch.version;
      for (final item in batch.items) {
        final bytes = item.bytes;
        if (bytes != null && bytes.length > 20 * 1024 * 1024) continue;
        final id = 'pc-${now().microsecondsSinceEpoch}-${_clipSequence++}';
        _clips.insert(0, {
          'id': id,
          'type': item.type,
          'title': item.type.toUpperCase(),
          'preview': item.text,
          'time': now().toUtc().toIso8601String(),
          'expiresAt': now()
              .add(const Duration(minutes: 30))
              .toUtc()
              .toIso8601String(),
          if (bytes != null) 'fileName': item.name,
          if (bytes != null) 'size': bytes.length,
        });
        if (bytes != null) _clipFiles[id] = bytes;
        while (_clips.where((item) => item['isFavorite'] != true).length > 50 ||
            _clipFiles.values.fold<int>(0, (sum, b) => sum + b.length) >
                100 * 1024 * 1024) {
          final index = _clips.lastIndexWhere(
            (item) => item['isFavorite'] != true,
          );
          if (index < 0) break;
          _clipFiles.remove(_clips.removeAt(index)['id']);
        }
      }
    } catch (_) {
      /* A busy OS clipboard must not break telemetry. */
    } finally {
      _readingClipboard = false;
    }
  }

  final Map<String, ({DateTime at, String signature, Future<AgentJson> result})>
  _commandResults = {};
  final Map<String, List<DateTime>> _commandTimes = {};
  final String pairingCode = (100000 + Random.secure().nextInt(900000))
      .toString();
  final Map<String, DateTime> _sessions = {};
  final Map<String, String> _sessionDevices = {};
  final Map<String, List<DateTime>> _attempts = {};
  UsageLedger ledger = UsageLedger();
  AgentJson? status, snapshot;
  String? error;
  bool _sampling = false;
  Timer? _timer;
  HttpServer? _server;
  Future<void> start({int port = 8765}) async {
    await stateDirectory.create(recursive: true);
    _clips.addAll(await _favoriteArchive.load());
    try {
      final saved =
          jsonDecode(
                await File('${stateDirectory.path}/usage.json').readAsString(),
              )
              as Map;
      ledger = UsageLedger(
        seconds: saved.map((k, v) => MapEntry(k as String, v as num)),
      );
    } catch (_) {
      /* No previous observations. */
    }
    await sample();
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _server!.listen((request) async {
      try {
        await handle(request);
      } catch (_) {
        // A cancelled static-file download must not crash the Agent or leak
        // internal errors. Headers/socket may already have been closed.
        try {
          request.response.statusCode = 500;
          await request.response.close();
        } catch (_) {}
      }
    });
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      sample();
      sampleClipboard();
    });
  }

  int get port => _server!.port;
  Future<void> stop() async {
    _timer?.cancel();
    await _server?.close(force: true);
  }

  Future<void> sample() async {
    if (_sampling) return;
    _sampling = true;
    try {
      final nextStatus = await tailnet.read();
      final telemetry = await collector.sample();
      status = nextStatus;
      ledger.observe(now());
      final self = Map<String, dynamic>.from(status!['Self'] as Map);
      snapshot = {
        ...telemetry,
        'deviceId': self['ID'],
        'machine': TailnetReader.machine(self),
        'capabilities': {
          'metrics': true,
          'commands': keyExecutor != null,
          'files': receiveDirectory != null,
          'clipboard': clipboardSource != null,
        },
        'weekly': {
          'source': 'observed_online',
          'label': 'เวลาใช้งานที่บันทึกไว้สัปดาห์นี้',
          'days': ledger.week(now()),
        },
      };
      error = null;
      await File(
        '${stateDirectory.path}/usage.json',
      ).writeAsString(jsonEncode(ledger.seconds), flush: true);
    } catch (_) {
      error = 'อ่านข้อมูลจาก Tailscale/Windows ไม่สำเร็จ';
    } finally {
      _sampling = false;
    }
  }

  bool _fresh() =>
      error == null &&
      snapshot != null &&
      now().difference(DateTime.parse(snapshot!['sampledAt'] as String)).abs() <
          const Duration(seconds: 20);
  Set<String> get allowedOrigins {
    final dns = ((status?['Self'] as Map?)?['DNSName'] as String? ?? '')
        .replaceFirst(RegExp(r'\.$'), '');
    return {
      'http://127.0.0.1:$port',
      'http://localhost:$port',
      if (dns.isNotEmpty) 'https://$dns',
      if (dns.isNotEmpty) 'https://$dns:8443',
    };
  }

  Future<void> _json(HttpRequest r, int code, AgentJson body) async {
    r.response.statusCode = code;
    r.response.headers.contentType = ContentType.json;
    r.response.headers.set('Cache-Control', 'no-store');
    r.response.headers.set('X-Content-Type-Options', 'nosniff');
    r.response.write(jsonEncode(body));
    await r.response.close();
  }

  Future<String?> _verifiedClient(HttpRequest r) async {
    // Only trust Serve on the loopback-only listener. Serve replaces forwarded
    // headers; local processes already have access to the private pairing file.
    if (r.connectionInfo?.remoteAddress.isLoopback != true ||
        r.headers.value('tailscale-funnel-request') != null ||
        r.headers.value('x-forwarded-proto') != 'https') {
      return null;
    }
    final host = r.headers.value('x-forwarded-host');
    if (host == null || !allowedOrigins.contains('https://$host')) return null;
    final ip = InternetAddress.tryParse(
      r.headers.value('x-forwarded-for') ?? '',
    );
    final login = r.headers.value('tailscale-user-login');
    if (ip == null || login == null || login.isEmpty) return null;
    try {
      final identity = await tailnet.whois(ip.address);
      final node = identity['Node'] as Map;
      final user = identity['UserProfile'] as Map;
      final owner = (status?['Self'] as Map?)?['UserID'];
      if (owner == null ||
          user['ID'] != owner ||
          node['User'] != owner ||
          user['LoginName'] != login ||
          node['MachineAuthorized'] == false) {
        return null;
      }
      final id = node['StableID'];
      if (id is! String || id.isEmpty) return null;
      // Current CLI omits MachineAuthorized for peers. Prove membership using
      // the current network map AND source address; never default authorization.
      final current = await tailnet.read();
      final members = <Map>[
        if (current['Self'] is Map) current['Self'] as Map,
        ...((current['Peer'] as Map?)?.values ?? const []).whereType<Map>(),
      ];
      final member = members.where((m) => m['ID'] == id).firstOrNull;
      if (current['BackendState'] != 'Running' ||
          member == null ||
          member['UserID'] != owner ||
          member['Expired'] == true ||
          member['MachineAuthorized'] == false ||
          (id != (current['Self'] as Map?)?['ID'] &&
              member['InNetworkMap'] != true) ||
          !(member['TailscaleIPs'] as List? ?? []).contains(ip.address)) {
        return null;
      }
      final expiry = DateTime.tryParse(node['KeyExpiry']?.toString() ?? '');
      if (expiry != null && expiry.year > 1 && !expiry.isAfter(now())) {
        return null;
      }
      return id;
    } catch (_) {
      return null;
    }
  }

  AgentJson _newSession({String? clientId}) {
    final token = randomSecret();
    final expires = now().add(const Duration(hours: 8));
    _sessions.removeWhere((_, expiry) => !expiry.isAfter(now()));
    _sessionDevices.removeWhere((key, _) => !_sessions.containsKey(key));
    _sessions[token] = expires;
    if (clientId != null) _sessionDevices[token] = clientId;
    return {
      'token': token,
      'expiresAt': expires.toUtc().toIso8601String(),
      'deviceId': (status?['Self'] as Map?)?['ID'],
      'clientDeviceId': clientId,
    };
  }

  Future<void> handle(HttpRequest r) async {
    final origin = r.headers.value('origin');
    if (origin != null && !allowedOrigins.contains(origin)) {
      await _json(r, 403, {'error': 'Origin not allowed'});
      return;
    }
    if (origin != null) {
      r.response.headers.set('Access-Control-Allow-Origin', origin);
      r.response.headers.set('Vary', 'Origin');
    }
    if (r.method == 'OPTIONS') {
      r.response.headers.set(
        'Access-Control-Allow-Methods',
        'GET, POST, DELETE, OPTIONS',
      );
      r.response.headers.set(
        'Access-Control-Allow-Headers',
        'Authorization, Content-Type, X-Mimo-Filename',
      );
      r.response.statusCode = 204;
      await r.response.close();
      return;
    }
    final path = r.uri.path;
    if (r.method == 'POST' && path == '/v1/tailscale-session') {
      final clientId = await _verifiedClient(r);
      if (clientId == null) {
        await _json(r, 401, {
          'error':
              'กรุณาเปิดผ่าน Tailscale HTTPS ด้วยบัญชีเจ้าของ PC หรือใช้รหัสจับคู่สำรอง',
        });
        return;
      }
      await _json(r, 200, _newSession(clientId: clientId));
      return;
    }
    if (r.method == 'GET' && path == '/v1/health') {
      await _json(r, 200, {
        'service': 'mimo-agent',
        'protocol': 1,
        'readOnly': keyExecutor == null,
      });
      return;
    }
    if (r.method == 'POST' && path == '/v1/pair') {
      final remote =
          r.headers.value('tailscale-user-login') ??
          r.connectionInfo?.remoteAddress.address ??
          'local';
      final attempts = _attempts.putIfAbsent(remote, () => [])
        ..removeWhere((t) => now().difference(t) > const Duration(minutes: 5));
      if (attempts.length >= 5) {
        await _json(r, 429, {
          'error': 'Too many pairing attempts; retry in five minutes',
        });
        return;
      }
      attempts.add(now());
      if (r.contentLength < 0 || r.contentLength > 1024) {
        await _json(r, 413, {'error': 'Invalid request size'});
        return;
      }
      AgentJson body;
      try {
        body = Map<String, dynamic>.from(
          jsonDecode(await utf8.decoder.bind(r).join()) as Map,
        );
      } catch (_) {
        await _json(r, 400, {'error': 'Invalid JSON'});
        return;
      }
      if (!secretEquals(body['code'].toString(), pairingCode)) {
        await _json(r, 401, {'error': 'รหัสจับคู่ไม่ถูกต้อง'});
        return;
      }
      attempts.clear();
      await _json(r, 200, _newSession(clientId: await _verifiedClient(r)));
      return;
    }
    if (path.startsWith('/v1/')) {
      final header = r.headers.value('authorization') ?? '';
      final token = header.startsWith('Bearer ') ? header.substring(7) : '';
      _sessions.removeWhere((_, expiry) => !expiry.isAfter(now()));
      _sessionDevices.removeWhere((key, _) => !_sessions.containsKey(key));
      if (!_sessions.keys.any((key) => secretEquals(key, token))) {
        await _json(r, 401, {'error': 'กรุณาจับคู่ Mimo Agent ใหม่'});
        return;
      }
      if (r.method == 'POST' &&
          RegExp(r'^/v1/devices/[^/]+/keys$').hasMatch(path)) {
        await _handleKeys(r, token);
        return;
      }
      expireClipboard();
      final favorite = RegExp(
        r'^/v1/devices/([^/]+)/clipboard/([^/]+)(/favorite)?$',
      ).firstMatch(path);
      if (favorite != null && (r.method == 'POST' || r.method == 'DELETE')) {
        if (clipboardSource == null ||
            !_fresh() ||
            Uri.decodeComponent(favorite[1]!) != snapshot?['deviceId']) {
          await _json(r, 403, {
            'error': 'เครื่องนี้ยังไม่พร้อมจัดการคลิปบอร์ด',
          });
          return;
        }
        final id = Uri.decodeComponent(favorite[2]!);
        final item = _clips.where((item) => item['id'] == id).firstOrNull;
        if (item == null) {
          await _json(r, 404, {'error': 'รายการนี้หมดอายุแล้ว'});
          return;
        }
        if (_editingFavorite) {
          await _json(r, 409, {'error': 'กำลังบันทึก กรุณาลองอีกครั้ง'});
          return;
        }
        _editingFavorite = true;
        var ownsFavoriteLock = true;
        try {
          if (r.method == 'DELETE' && favorite[3] == null) {
            if (item['isFavorite'] == true) await _favoriteArchive.remove(id);
            _clipFiles.remove(id);
            _clips.remove(item);
            _editingFavorite = false;
            ownsFavoriteLock = false;
            await _json(r, 200, {
              'deviceId': snapshot!['deviceId'],
              'deleted': true,
            });
          } else if (r.method == 'POST' && favorite[3] != null) {
            var body = '';
            await for (final chunk in utf8.decoder.bind(r)) {
              body += chunk;
              if (body.length > 1024) throw const FormatException();
            }
            final value = jsonDecode(body) as Map;
            if (value.length != 1 || value['favorite'] is! bool) {
              throw const FormatException();
            }
            final pin = value['favorite'] == true;
            if (pin) {
              await _favoriteArchive.pin(item, _clipFiles[id]);
              item['isFavorite'] = true;
              item['expiresAt'] = null;
              _clipFiles.remove(id);
            } else {
              final bytes = await _favoriteArchive.bytes(id);
              await _favoriteArchive.remove(id);
              if (bytes != null) _clipFiles[id] = bytes;
              item['isFavorite'] = false;
              item['expiresAt'] = now()
                  .add(const Duration(minutes: 30))
                  .toUtc()
                  .toIso8601String();
            }
            _editingFavorite = false;
            ownsFavoriteLock = false;
            await _json(r, 200, {
              'deviceId': snapshot!['deviceId'],
              'item': item,
            });
          } else {
            await _json(r, 405, {'error': 'ไม่รองรับคำขอนี้'});
          }
        } catch (_) {
          await _json(r, 400, {
            'error': 'บันทึกคลิปบอร์ดไม่สำเร็จ กรุณาลองอีกครั้ง',
          });
        } finally {
          if (ownsFavoriteLock) _editingFavorite = false;
        }
        return;
      }
      final attachment = RegExp(
        r'^/v1/devices/([^/]+)/clipboard/([^/]+)/file$',
      ).firstMatch(path);
      if (attachment != null && r.method == 'GET') {
        if (clipboardSource == null) {
          await _json(r, 405, {'error': 'เครื่องนี้ยังไม่เปิดการแชร์'});
          return;
        }
        final id = Uri.decodeComponent(attachment[2]!);
        final bytes = _clipFiles[id] ?? await _favoriteArchive.bytes(id);
        if (Uri.decodeComponent(attachment[1]!) != snapshot?['deviceId'] ||
            bytes == null) {
          await _json(r, 404, {'error': 'รายการนี้หมดอายุแล้ว'});
          return;
        }
        r.response.headers.set('Content-Type', 'application/octet-stream');
        r.response.headers.set('Content-Disposition', 'attachment');
        r.response.headers.set('X-Content-Type-Options', 'nosniff');
        r.response.headers.set('Cache-Control', 'no-store');
        r.response.add(bytes);
        await r.response.close();
        return;
      }
      final shared = RegExp(
        r'^/v1/devices/([^/]+)/(files|clipboard)$',
      ).firstMatch(path);
      if (shared != null) {
        if (!_fresh()) {
          await _json(r, 503, {'error': 'เครื่องยังไม่พร้อม กรุณาลองใหม่'});
          return;
        }
        if (Uri.decodeComponent(shared[1]!) != snapshot!['deviceId']) {
          await _json(r, 404, {'error': 'เครื่องปลายทางไม่ตรงกัน'});
          return;
        }
        if (shared[2] == 'clipboard' &&
            r.method == 'GET' &&
            clipboardSource != null) {
          await sampleClipboard();
          await _json(r, 200, {
            'deviceId': snapshot!['deviceId'],
            'items': _clips,
          });
          return;
        }
        if (shared[2] == 'files' &&
            r.method == 'POST' &&
            receiveDirectory != null) {
          if (_uploading) {
            await _json(r, 429, {'error': 'กำลังรับไฟล์อื่น กรุณารอสักครู่'});
            return;
          }
          _uploading = true;
          try {
            final receipt = await receiveFile(r, receiveDirectory!);
            await _json(r, 201, {
              'deviceId': snapshot!['deviceId'],
              ...receipt,
            });
          } catch (_) {
            await _json(r, 400, {
              'error':
                  'รับไฟล์ไม่สำเร็จ ตรวจชื่อไฟล์และขนาดไม่เกิน 100 MB แล้วลองใหม่',
            });
          } finally {
            _uploading = false;
          }
          return;
        }
        await _json(r, 405, {'error': 'เครื่องนี้ยังไม่เปิดการแชร์'});
        return;
      }
      if (r.method != 'GET') {
        await _json(r, 405, {'error': 'Read-only agent'});
        return;
      }
      if (!_fresh()) {
        await _json(r, 503, {
          'error': error ?? 'กำลังรอข้อมูลล่าสุดจากเครื่อง',
        });
        return;
      }
      if (path == '/v1/devices') {
        final self = status!['Self'] as Map;
        final peers = (status!['Peer'] as Map? ?? {}).values.cast<Map>();
        final clientId = _sessionDevices[token];
        await _json(r, 200, {
          'devices': [
            if (self['ID'] != clientId)
              {
                'machine': TailnetReader.machine(self),
                'agent': {'status': 'ready'},
              },
            ...peers
                .where(
                  (peer) => peer['ID'] != clientId && peer['ID'] != self['ID'],
                )
                .map(
                  (peer) => {
                    'machine': TailnetReader.machine(peer),
                    'agent': {
                      'status': peer['Online'] == true
                          ? 'unknown'
                          : 'unreachable',
                    },
                  },
                ),
          ],
        });
        return;
      }
      if (path.startsWith('/v1/devices/') && path.endsWith('/snapshot')) {
        final id = Uri.decodeComponent(path.split('/')[3]);
        if (id != snapshot!['deviceId']) {
          await _json(r, 404, {
            'error':
                'ต้องติดตั้งและจับคู่ Mimo Agent บนเครื่องนี้ก่อน จึงจะอ่าน telemetry ได้',
          });
          return;
        }
        await _json(r, 200, snapshot!);
        return;
      }
      await _json(r, 404, {'error': 'Unknown API route'});
      return;
    }
    if (r.method != 'GET' || webRoot == null) {
      await _json(r, 404, {'error': 'Not found'});
      return;
    }
    final segments = r.uri.pathSegments;
    if (segments.any(
      (s) => s == '..' || s.contains('\\') || s.contains('\u0000'),
    )) {
      await _json(r, 403, {'error': 'Forbidden'});
      return;
    }
    final relative = segments.isEmpty || segments.every((s) => s.isEmpty)
        ? 'index.html'
        : segments.join('/');
    final root = webRoot!.absolute;
    final file = File('${root.path}/$relative');
    if (!await file.exists()) {
      await _json(r, 404, {'error': 'Not found'});
      return;
    }
    final resolved = await file.resolveSymbolicLinks(),
        resolvedRoot = await root.resolveSymbolicLinks();
    if (!resolved.startsWith('$resolvedRoot${Platform.pathSeparator}')) {
      await _json(r, 403, {'error': 'Forbidden'});
      return;
    }
    final ext = relative.split('.').last;
    final type =
        {
          'html': 'text/html',
          'js': 'application/javascript',
          'json': 'application/json',
          'wasm': 'application/wasm',
          'png': 'image/png',
          'ttf': 'font/ttf',
          'otf': 'font/otf',
          'apk': 'application/vnd.android.package-archive',
        }[ext] ??
        'application/octet-stream';
    r.response.headers.set('Content-Type', type);
    r.response.headers.set('Cache-Control', 'no-store');
    await r.response.addStream(file.openRead());
    await r.response.close();
  }

  Future<void> _handleKeys(HttpRequest r, String token) async {
    if (keyExecutor == null) {
      await _json(r, 405, {'error': 'Agent ยังไม่ได้เปิด --enable-commands'});
      return;
    }
    if (!_fresh()) {
      await _json(r, 503, {
        'error': 'Agent ไม่มีข้อมูลเครื่องล่าสุด จึงไม่ส่งคีย์',
      });
      return;
    }
    final id = Uri.decodeComponent(r.uri.path.split('/')[3]);
    if (id != snapshot!['deviceId']) {
      await _json(r, 404, {'error': 'Agent นี้ไม่ใช่เครื่องปลายทาง'});
      return;
    }
    if (r.contentLength < 0 || r.contentLength > 4096) {
      await _json(r, 413, {'error': 'ขนาดคำขอไม่ถูกต้อง'});
      return;
    }
    AgentJson body;
    List<String> keys;
    String requestId;
    try {
      body = Map<String, dynamic>.from(
        jsonDecode(
              await utf8.decoder
                  .bind(r)
                  .join()
                  .timeout(const Duration(seconds: 3)),
            )
            as Map,
      );
      if (body.keys.any((k) => !{'keys', 'requestId'}.contains(k))) {
        throw const FormatException('รองรับเฉพาะชุดคีย์');
      }
      keys = normalizeChord((body['keys'] as List).cast<String>());
      requestId = body['requestId'] as String;
      if (!RegExp(r'^[a-zA-Z0-9-]{1,80}$').hasMatch(requestId)) {
        throw const FormatException('requestId ไม่ถูกต้อง');
      }
    } catch (_) {
      await _json(r, 400, {
        'error':
            'กรุณาส่งชุดคีย์ที่รองรับพร้อม requestId; ไม่รองรับ shell หรือข้อความอิสระ',
      });
      return;
    }
    _commandResults.removeWhere(
      (_, entry) => now().difference(entry.at) > const Duration(minutes: 5),
    );
    final cacheKey = '$token:$id:$requestId';
    final signature = keys.join('+');
    final prior = _commandResults[cacheKey];
    if (prior != null && prior.signature != signature) {
      await _json(r, 409, {'error': 'requestId นี้ถูกใช้กับชุดคีย์อื่นแล้ว'});
      return;
    }
    if (prior == null) {
      final times = _commandTimes.putIfAbsent(token, () => [])
        ..removeWhere((t) => now().difference(t) > const Duration(seconds: 1));
      _commandTimes.removeWhere((key, _) => !_sessions.containsKey(key));
      if (times.length >= 5 || _commandResults.length >= 256) {
        await _json(r, 429, {'error': 'ส่งคำสั่งถี่เกินไป กรุณารอสักครู่'});
        return;
      }
      times.add(now());
      _commandResults[cacheKey] = (
        at: now(),
        signature: signature,
        result: _performKeys(id, keys),
      );
    }
    final result = {...await _commandResults[cacheKey]!.result};
    final code = (result.remove('status') as int?) ?? 200;
    await _json(r, code, result);
  }

  Future<AgentJson> _performKeys(String id, List<String> keys) async {
    try {
      final count = await keyExecutor!.send(keys);
      return {'deviceId': id, 'sent': true, 'events': count};
    } catch (e) {
      return {
        'status': 409,
        'error': e is HttpException
            ? e.message
            : 'Windows ปฏิเสธการส่งคีย์ ไม่ได้ยืนยันว่าทำงานสำเร็จ',
      };
    }
  }
}
