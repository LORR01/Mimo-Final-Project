import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../domain/models.dart';
import 'services.dart';

class AgentException implements Exception {
  const AgentException(this.message);
  final String message;
  @override
  String toString() => message;
}

class LiveSnapshot {
  const LiveSnapshot({
    required this.deviceId,
    required this.sampledAt,
    required this.readings,
    required this.availability,
    required this.weeklyDays,
    required this.weeklyLabel,
    this.commands = false,
    this.files = false,
    this.clipboard = false,
  });
  final String deviceId, weeklyLabel;
  final DateTime sampledAt;
  final Map<String, double> readings;
  final Map<String, String> availability;
  final List<Json> weeklyDays;
  final bool commands;
  final bool files, clipboard;
  factory LiveSnapshot.fromJson(Json value) {
    final readings = <String, double>{};
    for (final entry in (value['readings'] as Map).entries) {
      if (entry.value is num && (entry.value as num).isFinite) {
        readings[entry.key as String] = (entry.value as num).toDouble();
      }
    }
    final weekly = value['weekly'] as Map;
    return LiveSnapshot(
      deviceId: value['deviceId'] as String,
      sampledAt: DateTime.parse(value['sampledAt'] as String),
      readings: readings,
      availability: (value['availability'] as Map? ?? {}).map(
        (k, v) => MapEntry(k as String, v.toString()),
      ),
      weeklyDays: (weekly['days'] as List)
          .map((d) => Map<String, dynamic>.from(d as Map))
          .toList(),
      weeklyLabel: weekly['label'] as String,
      commands: (value['capabilities'] as Map?)?['commands'] == true,
      files: (value['capabilities'] as Map?)?['files'] == true,
      clipboard: (value['capabilities'] as Map?)?['clipboard'] == true,
    );
  }
}

abstract interface class LiveDataSource {
  bool get connected;
  Future<LiveSnapshot> fetchSnapshot(String deviceId);
}

class AgentClient implements DeviceDiscovery, LiveDataSource {
  AgentClient({
    http.Client? client,
    http.Client Function()? targetClientFactory,
  }) : _client = client ?? http.Client(),
       _targetClientFactory = targetClientFactory ?? http.Client.new;
  final http.Client _client;
  final http.Client Function() _targetClientFactory;
  Uri? base;
  String? _token;
  DateTime? _expires;
  String? clientDeviceId;
  String? agentDeviceId;
  int _commandSequence = 0;
  final Map<String, String> _agentUrls = {};
  final Map<String, AgentClient> _targetClients = {};
  Future<AgentClient> _target(String deviceId) async {
    if (deviceId == agentDeviceId || agentDeviceId == null) return this;
    if (!connected) throw const AgentException('กรุณาเชื่อม Tailscale ก่อน');
    final endpoint = _agentUrls[deviceId];
    if (endpoint == null) {
      throw const AgentException('ไม่พบ HTTPS Agent ของเครื่องนี้');
    }
    final uri = Uri.tryParse(endpoint);
    final suffix = base!.host.split('.').skip(1).join('.');
    if (uri == null ||
        uri.scheme != 'https' ||
        suffix.isEmpty ||
        !uri.host.endsWith('.$suffix') ||
        uri.path.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty) {
      throw const AgentException(
        'ปลายทาง Agent ไม่อยู่ใน DNS tailnet เดียวกัน',
      );
    }
    final client = _targetClients.putIfAbsent(
      deviceId,
      () => AgentClient(client: _targetClientFactory()),
    );
    if (!client.connected) await client.connectTailscale(endpoint);
    if (client.agentDeviceId != deviceId) {
      client.disconnect();
      throw const AgentException('Agent ไม่ตรงกับเครื่องที่เลือก');
    }
    return client;
  }

  Future<void> sendShortcut(String deviceId, List<String> keys) async {
    final target = await _target(deviceId);
    if (!identical(target, this)) {
      await target.sendShortcut(deviceId, keys);
      return;
    }
    final response = await _request(
      'POST',
      '/v1/devices/${Uri.encodeComponent(deviceId)}/keys',
      body: {
        'keys': keys,
        'requestId':
            '${DateTime.now().microsecondsSinceEpoch}-${_commandSequence++}',
      },
    );
    if (response['deviceId'] != deviceId || response['sent'] != true) {
      throw const AgentException(
        'Agent ไม่ยืนยันการส่งคีย์ไปยังเครื่องที่เลือก',
      );
    }
  }

  Future<List<Json>> fetchClipboard(String deviceId) async {
    final target = await _target(deviceId);
    if (!identical(target, this)) return target.fetchClipboard(deviceId);
    final result = await _request(
      'GET',
      '/v1/devices/${Uri.encodeComponent(deviceId)}/clipboard',
    );
    if (result['deviceId'] != deviceId) {
      throw const AgentException('คลิปบอร์ดไม่ตรงกับเครื่องที่เลือก');
    }
    return (result['items'] as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<Uint8List> fetchClipboardFile(String deviceId, String clipId) async {
    final target = await _target(deviceId);
    if (!identical(target, this)) {
      return target.fetchClipboardFile(deviceId, clipId);
    }
    if (!connected || base == null) {
      throw const AgentException('กรุณาเชื่อมต่อเครื่องก่อน');
    }
    final response = await _client
        .get(
          base!.replace(
            path:
                '${base!.path}/v1/devices/${Uri.encodeComponent(deviceId)}/clipboard/${Uri.encodeComponent(clipId)}/file',
          ),
          headers: {'Authorization': 'Bearer $_token'},
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw const AgentException('รายการนี้หมดอายุหรือดาวน์โหลดไม่ได้');
    }
    return response.bodyBytes;
  }

  Future<Json> setClipboardFavorite(
    String deviceId,
    String clipId,
    bool favorite,
  ) async {
    final target = await _target(deviceId);
    if (!identical(target, this)) {
      return target.setClipboardFavorite(deviceId, clipId, favorite);
    }
    final result = await _request(
      'POST',
      '/v1/devices/${Uri.encodeComponent(deviceId)}/clipboard/${Uri.encodeComponent(clipId)}/favorite',
      body: {'favorite': favorite},
    );
    if (result['deviceId'] != deviceId) {
      throw const AgentException('คลิปบอร์ดไม่ตรงกับเครื่องที่เลือก');
    }
    return Map<String, dynamic>.from(result['item'] as Map);
  }

  Future<void> deleteClipboard(String deviceId, String clipId) async {
    final target = await _target(deviceId);
    if (!identical(target, this)) {
      return target.deleteClipboard(deviceId, clipId);
    }
    final result = await _request(
      'DELETE',
      '/v1/devices/${Uri.encodeComponent(deviceId)}/clipboard/${Uri.encodeComponent(clipId)}',
    );
    if (result['deviceId'] != deviceId || result['deleted'] != true) {
      throw const AgentException('ลบรายการไม่สำเร็จ');
    }
  }

  Future<Json> uploadFile(
    String deviceId,
    String name,
    int size,
    Stream<List<int>> bytes, {
    void Function(int)? onProgress,
  }) async {
    final target = await _target(deviceId);
    if (!identical(target, this)) {
      return target.uploadFile(
        deviceId,
        name,
        size,
        bytes,
        onProgress: onProgress,
      );
    }
    if (!connected || base == null) {
      throw const AgentException('กรุณาเชื่อมต่อเครื่องก่อน');
    }
    if (size < 0 || size > 100 * 1024 * 1024) {
      throw const AgentException('ไฟล์ต้องมีขนาดไม่เกิน 100 MB');
    }
    final request =
        http.StreamedRequest(
            'POST',
            base!.replace(
              path:
                  '${base!.path}/v1/devices/${Uri.encodeComponent(deviceId)}/files',
            ),
          )
          ..followRedirects = false
          ..contentLength = size;
    request.headers.addAll({
      'Authorization': 'Bearer $_token',
      'Content-Type': 'application/octet-stream',
      'X-Mimo-Filename': base64Url.encode(utf8.encode(name)),
    });
    final responseFuture = _client
        .send(request)
        .timeout(const Duration(minutes: 10));
    // Start listening immediately so an early HTTP rejection is consumed.
    final response = http.Response.fromStream(
      await (() async {
        final sending = () async {
          var sent = 0;
          try {
            await request.sink.addStream(
              bytes.timeout(const Duration(seconds: 30)).map((chunk) {
                sent += chunk.length;
                if (sent > size) {
                  throw const AgentException('ขนาดไฟล์ไม่ตรงกัน');
                }
                onProgress?.call(sent);
                return chunk;
              }),
            );
            if (sent != size) throw const AgentException('อ่านไฟล์ไม่ครบ');
          } finally {
            await request.sink.close();
          }
        }();
        final results = await Future.wait<dynamic>([responseFuture, sending]);
        return results.first as http.StreamedResponse;
      })(),
    ).timeout(const Duration(seconds: 30));
    final payload = await response;
    final result = jsonDecode(utf8.decode(payload.bodyBytes)) as Json;
    if (payload.statusCode != 201 ||
        result['deviceId'] != deviceId ||
        result['bytes'] != size) {
      throw AgentException(
        result['error']?.toString() ?? 'ปลายทางยังไม่ยืนยันว่าได้รับไฟล์',
      );
    }
    return result;
  }

  @override
  bool get connected =>
      _token != null && _expires != null && DateTime.now().isBefore(_expires!);
  void _setAddress(String address) {
    final uri = Uri.tryParse(address.trim());
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !(uri.scheme == 'https' ||
            (uri.scheme == 'http' &&
                ['localhost', '127.0.0.1', '::1'].contains(uri.host)))) {
      throw const AgentException(
        'ใช้ HTTPS ของ Tailscale Serve หรือ HTTP localhost สำหรับทดสอบบนคอมพิวเตอร์เท่านั้น',
      );
    }
    disconnect();
    base = uri.replace(path: uri.path.replaceFirst(RegExp(r'/$'), ''));
    _token = null;
    _expires = null;
    clientDeviceId = null;
    agentDeviceId = null;
  }

  void _acceptSession(Json response) {
    _token = response['token'] as String;
    _expires = DateTime.parse(response['expiresAt'] as String);
    clientDeviceId = response['clientDeviceId'] as String?;
    agentDeviceId = response['deviceId'] as String?;
  }

  Future<void> connectTailscale(String address) async {
    _setAddress(address);
    _acceptSession(
      await _request('POST', '/v1/tailscale-session', authenticated: false),
    );
  }

  Future<void> pair(String address, String code) async {
    _setAddress(address);
    final response = await _request(
      'POST',
      '/v1/pair',
      body: {'code': code.trim()},
      authenticated: false,
    );
    _acceptSession(response);
  }

  void disconnect() {
    _token = null;
    _expires = null;
    clientDeviceId = null;
    agentDeviceId = null;
    for (final client in _targetClients.values) {
      client.close();
    }
    _targetClients.clear();
    _agentUrls.clear();
  }

  Future<Json> _request(
    String method,
    String path, {
    Json? body,
    bool authenticated = true,
  }) async {
    if (base == null || (authenticated && !connected)) {
      throw const AgentException('กรุณาเชื่อมต่อและจับคู่ Mimo Agent ก่อน');
    }
    final uri = base!.replace(path: '${base!.path}$path');
    final request = http.Request(method, uri)..followRedirects = false;
    request.headers['Accept'] = 'application/json';
    if (authenticated) request.headers['Authorization'] = 'Bearer $_token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    try {
      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 12));
      final response = await http.Response.fromStream(
        streamed,
      ).timeout(const Duration(seconds: 12));
      final value = jsonDecode(utf8.decode(response.bodyBytes)) as Json;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.statusCode == 401 && authenticated) disconnect();
        throw AgentException(
          value['error']?.toString() ??
              'Agent ส่งข้อผิดพลาด ${response.statusCode}',
        );
      }
      return value;
    } on AgentException {
      rethrow;
    } on TimeoutException {
      throw const AgentException('Mimo Agent ไม่ตอบกลับภายในเวลา');
    } catch (error) {
      throw AgentException(
        'เชื่อมต่อ Mimo Agent ไม่ได้ ตรวจ Tailscale, URL และ Agent บน PC (${error.runtimeType})',
      );
    }
  }

  @override
  Future<List<DiscoveredDevice>> discover(String scenario) async {
    final result = await _request('GET', '/v1/devices');
    return (result['devices'] as List).map((raw) {
      final value = raw as Map;
      final machine = value['machine'] as Map;
      if (machine['agentUrl'] is String &&
          (machine['agentUrl'] as String).isNotEmpty) {
        _agentUrls[machine['id'] as String] = machine['agentUrl'] as String;
      }
      final status = (value['agent'] as Map)['status'] as String;
      return DiscoveredDevice(
        TailMachine.fromJson(
          Map<String, dynamic>.from(value['machine'] as Map),
        ),
        AgentStatus.values.where((e) => e.name == status).firstOrNull ??
            AgentStatus.unknown,
      );
    }).toList();
  }

  @override
  Future<LiveSnapshot> fetchSnapshot(String deviceId) async {
    final target = await _target(deviceId);
    if (!identical(target, this)) return target.fetchSnapshot(deviceId);
    final snapshot = LiveSnapshot.fromJson(
      await _request(
        'GET',
        '/v1/devices/${Uri.encodeComponent(deviceId)}/snapshot',
      ),
    );
    if (snapshot.deviceId != deviceId) {
      throw const AgentException('Agent ส่งข้อมูลคนละเครื่องกับที่เลือก');
    }
    if (DateTime.now().difference(snapshot.sampledAt).abs() >
        const Duration(seconds: 25)) {
      throw const AgentException(
        'ข้อมูล Agent เก่าเกินไป กรุณาตรวจเวลาและการเชื่อมต่อ',
      );
    }
    return snapshot;
  }

  void close() {
    disconnect();
    _client.close();
  }
}
