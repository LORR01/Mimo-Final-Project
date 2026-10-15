import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../data/services.dart';
import '../data/agent_client.dart';
import '../domain/models.dart';
import '../domain/shortcuts.dart';

class MimoStore extends ChangeNotifier {
  MimoStore({
    required this.repository,
    this.discovery = const MockDeviceDiscovery(),
    this.transferDelay = const Duration(milliseconds: 900),
    this.liveMode = false,
    this.configuredGateway = '',
  });
  final LocalRepository repository;
  final DeviceDiscovery discovery;
  final Duration transferDelay;
  final bool liveMode;
  final String configuredGateway;
  final Map<String, LiveSnapshot> liveSnapshots = {};
  String? liveError;
  String gatewayUrl = '';
  bool connectingAgent = false;
  bool _autoReconnect = true;
  DateTime? _retryAfter;
  Future<bool>? _connection;
  Future<bool> connectAgent([String? address]) {
    return _connection ??= _connectAgent(address).whenComplete(() {
      _connection = null;
    });
  }

  Future<bool> _connectAgent(String? address) async {
    if (!liveMode ||
        discovery is! AgentClient ||
        connectingAgent ||
        _disposed) {
      return false;
    }
    final endpoint =
        address?.trim() ??
        (gatewayUrl.isNotEmpty ? gatewayUrl : configuredGateway);
    if (endpoint.isEmpty) {
      liveError =
          'แอปรุ่นนี้ยังไม่ได้ตั้งค่าเครือข่าย Mimo กรุณาติดตั้ง APK ที่ตั้งค่า PC แล้ว';
      _changed(persist: false);
      return false;
    }
    connectingAgent = true;
    liveError = null;
    _autoReconnect = true;
    _refreshVersion++;
    _changed(persist: false);
    try {
      try {
        await (discovery as AgentClient).connectTailscale(endpoint);
      } catch (_) {
        if (address != null ||
            configuredGateway.isEmpty ||
            endpoint == configuredGateway) {
          rethrow;
        }
        await (discovery as AgentClient).connectTailscale(configuredGateway);
      }
      if (_disposed) return false;
      gatewayUrl = (discovery as AgentClient).base!.toString();
      _retryAfter = null;
      await searchDevices('live');
      await refreshLive();
      _changed();
      return discoveryState != DiscoveryState.error;
    } catch (e) {
      _retryAfter = DateTime.now().add(const Duration(seconds: 30));
      liveError = e.toString();
      _changed(persist: false);
      return false;
    } finally {
      connectingAgent = false;
      _changed(persist: false);
    }
  }

  bool _refreshing = false;
  int _refreshVersion = 0;
  bool get liveConnected =>
      discovery is LiveDataSource && (discovery as LiveDataSource).connected;
  bool get canRunCommands =>
      (active?.canOperate ?? false) &&
      !connectingAgent &&
      (!liveMode || (_freshSnapshot?.commands == true && commandBusy.isEmpty));
  final Set<String> commandBusy = {};
  bool get canSendFiles =>
      (active?.canOperate ?? false) &&
      (!liveMode || (_freshSnapshot?.files == true && !connectingAgent));
  String get fileBlockedReason =>
      blockedReason.isNotEmpty ? blockedReason : 'เครื่องนี้ยังไม่เปิดรับไฟล์';
  final List<Json> notifications = [];
  final Map<String, bool> _onlineStates = {};
  final Map<String, Set<String>> _clipSeen = {};
  String? clipboardError;
  final Map<String, Future<Uint8List>> _clipBytes = {};
  Future<Uint8List> clipboardFile(String deviceId, String clipId) {
    final key = '$deviceId/$clipId';
    if (!_clipBytes.containsKey(key) && _clipBytes.length >= 4) {
      _clipBytes.remove(_clipBytes.keys.first);
    }
    return _clipBytes.putIfAbsent(
      key,
      () => (discovery as AgentClient)
          .fetchClipboardFile(deviceId, clipId)
          .catchError((Object error) {
            _clipBytes.remove(key);
            throw error;
          }),
    );
  }

  void purgeClipboard() {
    final now = DateTime.now();
    var removed = false;
    for (final entry in clipboard.entries) {
      entry.value.removeWhere((clip) {
        if (favorites[clip['id']] == true || clip['isFavorite'] == true) {
          return false;
        }
        final expires = DateTime.tryParse(clip['expiresAt']?.toString() ?? '');
        if (expires == null || expires.isAfter(now)) return false;
        _clipBytes.remove('${entry.key}/${clip['id']}');
        favorites.remove(clip['id']);
        removed = true;
        return true;
      });
    }
    if (removed) _changed();
  }

  int get unreadNotifications =>
      notifications.where((n) => n['read'] != true).length;
  void readNotifications() {
    for (final n in notifications) {
      n['read'] = true;
    }
    _changed(persist: false);
  }

  void _notify(String deviceId, String title, String type) {
    notifications.insert(0, {
      'id': _id('notice'),
      'deviceId': deviceId,
      'title': title,
      'type': type,
      'time': DateTime.now().toIso8601String(),
      'read': false,
    });
    if (notifications.length > 100) notifications.removeLast();
  }

  void observeOnline(String deviceId, bool online) {
    final previous = _onlineStates[deviceId];
    _onlineStates[deviceId] = online;
    if (previous == null || previous == online) return;
    final name = devices
        .where((d) => d.id == deviceId)
        .firstOrNull
        ?.displayName;
    if (name != null) {
      _notify(
        deviceId,
        '$name ${online ? 'ออนไลน์แล้ว' : 'ออฟไลน์'}',
        'connection',
      );
    }
  }

  Future<void> refreshClipboard(String deviceId) async {
    if (discovery is! AgentClient) return;
    try {
      final incoming = await (discovery as AgentClient).fetchClipboard(
        deviceId,
      );
      if (_disposed || !devices.any((d) => d.id == deviceId)) return;
      final first = !_clipSeen.containsKey(deviceId);
      final seen = _clipSeen.putIfAbsent(deviceId, () => {});
      final dismissed = (configs[deviceId]?['dismissedClips'] as List? ?? []);
      final list = clipboard.putIfAbsent(deviceId, () => []);
      final incomingIds = incoming.map((item) => item['id']).toSet();
      list.removeWhere((item) {
        if (item['source'] != 'pc' ||
            item['isFavorite'] != true ||
            incomingIds.contains(item['id'])) {
          return false;
        }
        favorites.remove(item['id']);
        _clipBytes.remove('$deviceId/${item['id']}');
        return true;
      });
      var added = 0;
      for (final item in incoming.reversed) {
        final id = item['id'] as String;
        final existing = list.where((c) => c['id'] == id).firstOrNull;
        if (existing != null) {
          existing.addAll(item);
          favorites[id] = item['isFavorite'] == true;
          continue;
        }
        if ((!seen.add(id) && item['isFavorite'] != true) ||
            dismissed.contains(id) ||
            list.any((c) => c['id'] == id)) {
          continue;
        }
        final expiry = DateTime.tryParse(item['expiresAt']?.toString() ?? '');
        if (item['isFavorite'] != true &&
            (expiry == null || !expiry.isAfter(DateTime.now()))) {
          continue;
        }
        favorites[id] = item['isFavorite'] == true;
        list.insert(0, {...item, 'source': 'pc', 'deviceId': deviceId});
        added++;
      }
      if (seen.length > 1000) {
        seen.clear();
        seen.addAll(incoming.map((i) => i['id'] as String));
      }
      clipboardError = null;
      if (!first && added > 0) {
        final name = devices.firstWhere((d) => d.id == deviceId).displayName;
        _notify(
          deviceId,
          'คลิปบอร์ดใหม่จาก $name · $added รายการ',
          'clipboard',
        );
      }
      if (added > 0) _changed();
    } catch (_) {
      clipboardError = 'ดึงคลิปบอร์ดไม่ได้ กรุณาลองใหม่';
    }
  }

  String? get temperatureNotice => liveMode && _freshSnapshot != null
      ? (_freshSnapshot!.readings.containsKey('cpuTemp')
            ? null
            : 'ยังอ่านอุณหภูมิ CPU ไม่ได้')
      : null;
  String get operationReason => liveMode
      ? (blockedReason.isNotEmpty
            ? blockedReason
            : 'Agent ยังไม่เปิดสิทธิ์ส่งคีย์ลัด หรือกำลังส่งคำสั่ง')
      : blockedReason;
  List<MimoDevice> devices = [];
  String? get clientDeviceId => discovery is AgentClient
      ? (discovery as AgentClient).clientDeviceId
      : null;
  List<MimoDevice> get visibleDevices =>
      devices.where((d) => d.id != clientDeviceId).toList();
  Map<String, Json> configs = {}, clipsByDevice = {};
  Map<String, List<Json>> clipboard = {};
  Map<String, bool> favorites = {};
  Map<String, Map<String, bool>> quickActions = {};
  final List<DemoTransfer> transfers = [];
  List<DiscoveredDevice> discovered = [];
  DiscoveryState discoveryState = DiscoveryState.idle;
  String scenario = 'found',
      discoveryError = '',
      theme = 'dark',
      username = 'USERNAME';
  String? activeDeviceId, selectedMetric, selectedGroupId;
  DemoScreen screen = DemoScreen.splash;
  String clipFilter = 'all';
  Json seed = {};
  String? storageWarning;
  bool _disposed = false;
  int _sequence = 0, _serial = 0;
  Timer? _telemetry;
  Future<void> _writes = Future<void>.value();
  final List<Timer> _transfersTimers = [];
  MimoDevice? get active =>
      visibleDevices.where((d) => d.id == activeDeviceId).firstOrNull;
  String get blockedReason =>
      active?.blockedReason ?? 'ยังไม่มีอุปกรณ์ที่เลือก';
  List<Json> get groups =>
      (configs[activeDeviceId]?['groups'] as List? ?? []).cast<Json>();
  List<Json> get buttons =>
      (configs[activeDeviceId]?['buttons'] as List? ?? []).cast<Json>();
  List<String> get pinnedIds =>
      (configs[activeDeviceId]?['pins'] as List? ?? []).cast<String>();
  List<Json> get pinnedButtons => [
    for (final id in pinnedIds) ...buttons.where((b) => b['id'] == id),
  ];
  String? togglePin(String id) {
    if (!buttons.any((b) => b['id'] == id)) return 'ไม่พบปุ่มนี้';
    final pins =
        configs[activeDeviceId]!.putIfAbsent('pins', () => <String>[]) as List;
    if (pins.contains(id)) {
      pins.remove(id);
    } else {
      if (pins.length >= 4) {
        return 'ปักหมุดได้สูงสุด 4 ปุ่ม กรุณาถอดหมุดเดิมก่อน';
      }
      pins.add(id);
    }
    _changed();
    return null;
  }

  void removeButton(String id) {
    buttons.removeWhere((b) => b['id'] == id);
    (configs[activeDeviceId]?['pins'] as List?)?.remove(id);
    _changed();
  }

  List<Json> get clips => clipboard[activeDeviceId] ?? [];
  List<DemoTransfer> get activeTransfers =>
      transfers.where((t) => t.deviceId == activeDeviceId).toList();
  Map<String, bool> get quick => quickActions.putIfAbsent(
    activeDeviceId ?? '',
    () => {'mic': false, 'media': false},
  );

  Future<void> initialize({Json? fixture, bool simulate = true}) async {
    seed = fixture ?? await loadSeed();
    Json? saved;
    try {
      saved = await repository.read();
    } catch (_) {
      storageWarning = 'อ่านข้อมูลที่บันทึกไม่ได้ ใช้ข้อมูลตัวอย่างของรอบนี้';
    }
    try {
      if (saved != null) {
        if (saved['schemaVersion'] != 1) {
          throw const FormatException('Unknown schema');
        }
        devices = (saved['devices'] as List)
            .map(
              (d) => MimoDevice.fromJson(Map<String, dynamic>.from(d as Map)),
            )
            .toList();
        configs = (saved['configs'] as Map).map(
          (k, v) => MapEntry(k as String, Map<String, dynamic>.from(v as Map)),
        );
        clipboard = (saved['clipboard'] as Map).map(
          (k, v) => MapEntry(
            k as String,
            (v as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList(),
          ),
        );
        favorites = (saved['favorites'] as Map).map(
          (k, v) => MapEntry(k as String, v == true),
        );
        theme = ['dark', 'light', 'system'].contains(saved['theme'])
            ? saved['theme'] as String
            : 'dark';
        activeDeviceId = saved['activeDeviceId'] as String?;
        gatewayUrl = saved['gatewayUrl'] as String? ?? '';
      } else {
        _seed();
      }
    } catch (_) {
      storageWarning = 'รูปแบบข้อมูลเก่าไม่ถูกต้อง ใช้ข้อมูลตัวอย่างแทน';
      _seed();
    }
    if (liveMode) {
      // Clipboard contents are intentionally memory-only in live mode. This
      // prevents expired material remaining on disk while the app is closed.
      for (final list in clipboard.values) {
        list.removeWhere((item) => favorites[item['id']] != true);
      }
      devices.removeWhere((d) => !d.live);
      for (final d in devices) {
        d.agent = AgentStatus.unreachable;
        d.readings = {};
      }
    }
    for (final config in configs.values) {
      final ids = (config['buttons'] as List? ?? [])
          .map((b) => b['id'])
          .toSet();
      config['pins'] = (config['pins'] as List? ?? [])
          .whereType<String>()
          .where(ids.contains)
          .toSet()
          .take(4)
          .toList();
    }
    purgeClipboard();
    _fallback();
    if (liveMode && simulate) {
      _telemetry = Timer.periodic(
        const Duration(seconds: 5),
        (_) => refreshLive(),
      );
    } else if (simulate) {
      _telemetry = Timer.periodic(
        const Duration(milliseconds: 2800),
        (_) => _tick(),
      );
    }
    if (liveMode) _changed();
    notifyListeners();
  }

  void _seed() {
    devices = (seed['INITIAL_DEVICES'] as List).asMap().entries.map((entry) {
      final d = entry.value as Map, online = d['online'] == true;
      return MimoDevice(
        machine: TailMachine(
          id: d['id'] as String,
          hostname: d['name'] as String,
          ip: '100.64.10.${entry.key + 10}',
          os: d['id'] == 'notebook' ? 'macOS' : 'Windows 11',
          online: online,
        ),
        displayName: d['name'] as String,
        agent: online ? AgentStatus.ready : AgentStatus.unreachable,
        readings: _readings(d['readings'] as Map?),
        addedAt: 0,
      );
    }).toList();
    configs = (jsonDecode(jsonEncode(seed['INITIAL_DEVICE_CONFIGS'])) as Map)
        .map(
          (k, v) => MapEntry(k as String, Map<String, dynamic>.from(v as Map)),
        );
    clipboard = (jsonDecode(jsonEncode(seed['INITIAL_CLIPBOARD'])) as Map).map(
      (k, v) => MapEntry(
        k as String,
        (v as List).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      ),
    );
    favorites = {
      for (final list in clipboard.values)
        for (final c in list) c['id'] as String: c['isFavorite'] == true,
    };
    activeDeviceId = 'desktop';
  }

  static Map<String, double> _readings(Map? values) => values == null
      ? {
          'cpu': 18,
          'gpu': 29,
          'ramUsed': 7.9,
          'ramTotal': 16,
          'cpuTemp': 42,
          'gpuTemp': 46,
        }
      : values.map((k, v) => MapEntry(k as String, (v as num).toDouble()));
  void _fallback() {
    if (!visibleDevices.any((d) => d.id == activeDeviceId)) {
      activeDeviceId =
          visibleDevices.where((d) => d.canOperate).firstOrNull?.id ??
          visibleDevices.firstOrNull?.id;
    }
  }

  Json snapshot() => {
    'schemaVersion': 1,
    'devices': devices.map((d) => d.toJson()).toList(),
    'configs': configs,
    'clipboard': liveMode
        ? {
            for (final entry in clipboard.entries)
              entry.key: entry.value
                  .where((item) => favorites[item['id']] == true)
                  .toList(),
          }
        : clipboard,
    'favorites': favorites,
    'theme': theme,
    'activeDeviceId': activeDeviceId,
    'gatewayUrl': gatewayUrl,
  };
  void _changed({bool persist = true}) {
    if (_disposed) return;
    if (persist) {
      final value = jsonDecode(jsonEncode(snapshot())) as Json;
      _writes = _writes.then((_) => repository.write(value)).catchError((
        Object error,
      ) {
        storageWarning = 'บันทึกข้อมูลไม่ได้ การเปลี่ยนแปลงคงอยู่เฉพาะรอบนี้';
      });
    }
    notifyListeners();
  }

  Future<void> flush() => _writes;
  void navigate(DemoScreen target) {
    screen = target;
    selectedMetric = null;
    selectedGroupId = null;
    _changed(persist: false);
  }

  Future<void> login(String name) async {
    username = name.trim();
    navigate(DemoScreen.loading);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!_disposed) navigate(DemoScreen.home);
  }

  void setTheme(String value) {
    theme = value;
    _changed();
  }

  void selectDevice(String id) {
    if (!visibleDevices.any((d) => d.id == id)) return;
    activeDeviceId = id;
    selectedMetric = null;
    selectedGroupId = null;
    clipFilter = 'all';
    _changed();
    if (liveMode) unawaited(refreshLive());
  }

  void focusMetric(String id) {
    screen = DemoScreen.status;
    selectedMetric = id;
    _changed(persist: false);
  }

  void selectGroup(String id) {
    selectedGroupId = selectedGroupId == id ? null : id;
    _changed(persist: false);
  }

  void setClipFilter(String filter) {
    clipFilter = filter;
    _changed(persist: false);
  }

  final Set<String> clipboardBusy = {};
  Future<String?> toggleFavorite(String id) async {
    final item = clips.where((c) => c['id'] == id).firstOrNull;
    if (item == null || clipboardBusy.contains(id)) return null;
    final deviceId = activeDeviceId!;
    final pin = !(favorites[id] ?? false);
    clipboardBusy.add(id);
    try {
      if (liveMode && item['source'] == 'pc') {
        final updated = await (discovery as AgentClient).setClipboardFavorite(
          deviceId,
          id,
          pin,
        );
        item.addAll(updated);
      } else {
        item['isFavorite'] = pin;
        if (liveMode) {
          item['expiresAt'] = pin
              ? null
              : DateTime.now()
                    .add(const Duration(minutes: 30))
                    .toUtc()
                    .toIso8601String();
        }
      }
      favorites[id] = pin;
      _changed();
      return null;
    } catch (_) {
      return 'บันทึก Favorite ไม่สำเร็จ กรุณาลองใหม่';
    } finally {
      clipboardBusy.remove(id);
      if (!_disposed) _changed(persist: false);
    }
  }

  Future<String?> removeClip(String id) async {
    if (clipboardBusy.contains(id)) return null;
    final deviceId = activeDeviceId!;
    if (liveMode && clips.any((c) => c['id'] == id && c['source'] == 'pc')) {
      clipboardBusy.add(id);
      try {
        await (discovery as AgentClient).deleteClipboard(deviceId, id);
      } catch (_) {
        return 'ลบรายการไม่สำเร็จ กรุณาลองใหม่';
      } finally {
        clipboardBusy.remove(id);
      }
    }
    final targetClips = clipboard[deviceId] ?? [];
    if (liveMode &&
        targetClips.any((c) => c['id'] == id && c['source'] == 'pc')) {
      final dismissed =
          configs[deviceId]!.putIfAbsent('dismissedClips', () => <String>[])
              as List;
      dismissed.add(id);
      if (dismissed.length > 1000) dismissed.removeAt(0);
    }
    targetClips.removeWhere((c) => c['id'] == id);
    _clipBytes.remove('$deviceId/$id');
    favorites.remove(id);
    _changed();
    return null;
  }

  void addClip(String value) {
    final text = value.trim();
    if (active == null || text.isEmpty) return;
    clipboard.putIfAbsent(active!.id, () => []).insert(0, {
      'id': _id('clip'),
      'type': RegExp(r'^https?://', caseSensitive: false).hasMatch(text)
          ? 'link'
          : 'text',
      'title': RegExp(r'^https?://', caseSensitive: false).hasMatch(text)
          ? 'LINK'
          : 'TEXT',
      'preview': text,
      'time': 'เมื่อกี้',
      if (liveMode)
        'expiresAt': DateTime.now()
            .add(const Duration(minutes: 30))
            .toUtc()
            .toIso8601String(),
    });
    _changed();
  }

  String? addGroup(String name, String color) {
    name = name.trim();
    if (name.isEmpty) return 'กรุณาใส่ชื่อกลุ่ม';
    if (groups.any(
      (g) => (g['name'] as String).toLowerCase() == name.toLowerCase(),
    )) {
      return 'ชื่อกลุ่มนี้มีอยู่แล้ว';
    }
    if (active == null) return blockedReason;
    groups.add({'id': _id('group'), 'name': name, 'color': color});
    _changed();
    return null;
  }

  String? addButton(
    String name,
    String note,
    String command,
    String binding,
    String groupId, {
    String? editingId,
  }) {
    if (name.trim().isEmpty) return 'กรุณาใส่ชื่อปุ่ม';
    if (!groups.any((g) => g['id'] == groupId)) return 'กรุณาเลือกกลุ่ม';
    String normalized;
    try {
      normalized = parseChord(binding).join(' + ');
    } on FormatException catch (e) {
      return e.message;
    }
    final value = <String, dynamic>{
      'id': editingId ?? _id('button'),
      'name': name.trim(),
      'note': note.trim(),
      'command': 'custom',
      'binding': normalized,
      'groupId': groupId,
    };
    final index = buttons.indexWhere((b) => b['id'] == editingId);
    if (editingId != null && index < 0) return 'ปุ่มนี้ถูกลบแล้ว';
    if (index >= 0) {
      buttons[index] = value;
    } else {
      buttons.add(value);
    }
    _changed();
    return null;
  }

  String runShortcut(String id) {
    if (liveMode) return operationReason;
    if (blockedReason.isNotEmpty) return '$blockedReason · ส่งคำสั่งไม่ได้';
    final b = buttons.where((b) => b['id'] == id).firstOrNull;
    if (b == null) return 'ไม่พบปุ่ม';
    if (b['command'] == 'mic') quick['mic'] = false;
    if (b['command'] == 'media') quick['media'] = !(quick['media'] ?? false);
    _changed(persist: false);
    return 'ตัวอย่าง: ${b['name']} · ${b['binding'] ?? b['command']} → ${active!.displayName}';
  }

  Future<String> executeShortcut(String id) async {
    if (!liveMode) return runShortcut(id);
    final device = active;
    if (!canRunCommands || device == null || discovery is! AgentClient) {
      return operationReason;
    }
    final button = buttons.where((b) => b['id'] == id).firstOrNull;
    if (button == null) return 'ไม่พบปุ่มนี้';
    List<String> keys;
    try {
      keys = parseChord(button['binding']?.toString() ?? '');
    } on FormatException catch (e) {
      return 'กรุณาแก้คีย์ลัด: ${e.message}';
    }
    final busyId = '${device.id}/$id';
    commandBusy.add(busyId);
    _changed(persist: false);
    try {
      await (discovery as AgentClient).sendShortcut(device.id, keys);
      return 'ส่ง ${keys.join(' + ')} ไปที่ ${device.displayName} แล้ว';
    } catch (e) {
      return 'ส่งคีย์ลัดไม่สำเร็จ: $e';
    } finally {
      commandBusy.remove(busyId);
      _changed(persist: false);
    }
  }

  String toggleQuick(String key) {
    if (liveMode) return operationReason;
    if (blockedReason.isNotEmpty) return '$blockedReason · ส่งคำสั่งไม่ได้';
    quick[key] = !(quick[key] ?? false);
    _changed(persist: false);
    return 'ตัวอย่าง: $key ${quick[key] == true ? 'ON' : 'OFF'}';
  }

  Future<void> searchDevices(String value) async {
    final sequence = ++_sequence;
    scenario = value;
    discoveryState = DiscoveryState.searching;
    discovered = [];
    discoveryError = '';
    _changed(persist: false);
    try {
      final results = await discovery.discover(value);
      if (_disposed || sequence != _sequence) return;
      final unique = {for (final result in results) result.machine.id: result};
      unique.remove(clientDeviceId);
      _fallback();
      for (final d in devices) {
        final update = unique[d.id];
        if (update != null) {
          d.machine = update.machine;
          d.agent = update.agent;
        }
      }
      discovered = unique.values
          .where((result) => !devices.any((d) => d.id == result.machine.id))
          .toList();
      discoveryState = discovered.isEmpty
          ? DiscoveryState.empty
          : DiscoveryState.found;
      _changed();
    } catch (error) {
      if (_disposed || sequence != _sequence) return;
      discoveryError = liveMode
          ? error.toString()
          : 'ค้นหาไม่สำเร็จ กรุณาลองอีกครั้ง';
      discoveryState = DiscoveryState.error;
      _changed(persist: false);
    }
  }

  String? saveDevice(String id, String name, {DiscoveredDevice? candidate}) {
    name = name.trim();
    if (name.isEmpty) return 'กรุณาใส่ชื่อแสดงใน Mimo';
    if (name.length > 32) return 'ชื่อแสดงต้องไม่เกิน 32 ตัวอักษร';
    final existing = devices.where((d) => d.id == id).firstOrNull;
    if (existing != null) {
      existing.displayName = name;
    } else {
      if (id == clientDeviceId) {
        return 'เครื่องนี้กำลังเปิดแอป จึงไม่แสดงเป็นปลายทาง';
      }
      if (candidate == null || candidate.machine.id != id) {
        return 'ไม่พบเครื่อง กรุณาค้นหาใหม่';
      }
      devices.add(
        MimoDevice(
          machine: candidate.machine,
          displayName: name,
          agent: candidate.agent,
          readings: liveMode ? {} : _readings(null),
          addedAt: DateTime.now().millisecondsSinceEpoch,
          live: liveMode,
        ),
      );
      configs[id] = {'groups': <Json>[], 'buttons': <Json>[]};
      clipboard[id] = [];
      activeDeviceId = id;
    }
    discovered.removeWhere((r) => r.machine.id == id);
    if (discovered.isEmpty && discoveryState == DiscoveryState.found) {
      discoveryState = DiscoveryState.empty;
    }
    _changed();
    if (liveMode) unawaited(refreshLive());
    return null;
  }

  void removeDevice(String id) {
    _clipBytes.removeWhere((key, _) => key.startsWith('$id/'));
    _clipSeen.remove(id);
    _onlineStates.remove(id);
    devices.removeWhere((d) => d.id == id);
    configs.remove(id);
    final removed = clipboard.remove(id) ?? [];
    for (final c in removed) {
      favorites.remove(c['id']);
    }
    quickActions.remove(id);
    liveSnapshots.remove(id);
    transfers.removeWhere((t) => t.deviceId == id);
    _fallback();
    selectedMetric = null;
    selectedGroupId = null;
    clipFilter = 'all';
    _changed();
    if (liveMode) unawaited(refreshLive());
  }

  DemoTransfer? sendFile({
    required String name,
    required int size,
    String? deviceId,
  }) {
    if (liveMode) return null;
    final d = devices
        .where((d) => d.id == (deviceId ?? activeDeviceId))
        .firstOrNull;
    if (d == null || !d.canOperate) return null;
    final transfer = DemoTransfer(
      id: _id('file'),
      deviceId: d.id,
      name: name,
      size: size,
    );
    transfers.insert(0, transfer);
    _changed(persist: false);
    _transfersTimers.add(
      Timer(transferDelay, () {
        if (!_disposed && transfers.contains(transfer)) {
          transfer.done = true;
          _changed(persist: false);
        }
      }),
    );
    return transfer;
  }

  Future<DemoTransfer> sendRealFile({
    required String deviceId,
    required String name,
    required int size,
    required Stream<List<int>> bytes,
  }) async {
    final device = devices.where((d) => d.id == deviceId).firstOrNull;
    final snapshot = liveSnapshots[deviceId];
    if (!liveMode ||
        discovery is! AgentClient ||
        device?.canOperate != true ||
        snapshot?.files != true ||
        DateTime.now().difference(snapshot!.sampledAt).abs() >
            const Duration(seconds: 25)) {
      throw const AgentException('เครื่องปลายทางยังไม่พร้อมรับไฟล์');
    }
    final transfer = DemoTransfer(
      id: _id('file'),
      deviceId: deviceId,
      name: name,
      size: size,
    );
    transfers.insert(0, transfer);
    _changed(persist: false);
    try {
      final receipt = await (discovery as AgentClient).uploadFile(
        deviceId,
        name,
        size,
        bytes,
        onProgress: (sent) {
          if (_disposed) return;
          transfer.progress = size == 0 ? 1 : sent / size;
          _changed(persist: false);
        },
      );
      transfer.done = true;
      transfer.storedName = receipt['storedName'] as String?;
    } catch (e) {
      transfer.error = 'ส่งไม่สำเร็จ กรุณาลองใหม่';
    }
    if (!_disposed) _changed(persist: false);
    return transfer;
  }

  List<Metric> get metrics {
    if (liveMode) return _liveMetrics;
    final d = active, r = d?.readings ?? {};
    final ready = d?.canOperate ?? false;
    final ram = r['ramUsed'] ?? 0, total = r['ramTotal'] ?? 16;
    Metric metric(
      String id,
      String label,
      String value,
      double percent,
      String caption,
    ) => Metric(
      id,
      label,
      ready ? value : '—',
      ready ? percent.clamp(0, 100) : 0,
      caption,
    );
    return [
      metric(
        'cpu',
        'CPU',
        '${(r['cpu'] ?? 0).round()}%',
        r['cpu'] ?? 0,
        'การใช้งาน',
      ),
      metric(
        'gpu',
        'GPU',
        '${(r['gpu'] ?? 0).round()}%',
        r['gpu'] ?? 0,
        'การใช้งาน',
      ),
      metric(
        'ram',
        'RAM',
        '${ram.toStringAsFixed(1)} GB',
        ram / total * 100,
        'จาก ${total.round()} GB · ใช้ไป ${(ram / total * 100).round()}%',
      ),
      metric(
        'cpu-temp',
        'อุณหภูมิ CPU',
        '${(r['cpuTemp'] ?? 0).round()}°C',
        r['cpuTemp'] ?? 0,
        '',
      ),
      metric(
        'gpu-temp',
        'อุณหภูมิ GPU',
        '${(r['gpuTemp'] ?? 0).round()}°C',
        r['gpuTemp'] ?? 0,
        '',
      ),
    ];
  }

  List<Json> get weeklyDays {
    if (liveMode) {
      final snapshot = _freshSnapshot;
      if (snapshot != null) return snapshot.weeklyDays;
      return (seed['INITIAL_WEEKLY_USAGE']['days'] as List)
          .map(
            (day) => {
              ...Map<String, dynamic>.from(day as Map),
              'minutes': null,
              'percent': 0.0,
            },
          )
          .toList();
    }
    final id = activeDeviceId ?? '',
        scale = id == 'desktop'
            ? 1.0
            : id == 'studio'
            ? 1.15
            : 1.0 + (id.codeUnits.fold<int>(0, (a, b) => a + b) % 5) * .1;
    return (seed['INITIAL_WEEKLY_USAGE']['days'] as List).map((day) {
      final d = Map<String, dynamic>.from(day as Map);
      final hours = active?.canOperate == true
          ? (d['hours'] as num) * scale
          : 0.0;
      return {
        ...d,
        'minutes': (hours * 60).round(),
        'percent': (hours / 15).clamp(0, 1).toDouble(),
      };
    }).toList();
  }

  String get weeklyTotal {
    if (liveMode && weeklyDays.every((d) => d['minutes'] == null)) return '—';
    final minutes = weeklyDays.fold<int>(
      0,
      (sum, d) => sum + ((d['minutes'] as num?)?.toInt() ?? 0),
    );
    return '${minutes ~/ 60} ชม. ${minutes % 60} นาที';
  }

  LiveSnapshot? get _freshSnapshot {
    final data = liveSnapshots[activeDeviceId];
    return data != null &&
            liveConnected &&
            active?.agent == AgentStatus.ready &&
            DateTime.now().difference(data.sampledAt).abs() <
                const Duration(seconds: 25)
        ? data
        : null;
  }

  String get weeklyLabel => liveMode
      ? (_freshSnapshot?.weeklyLabel ??
            'เวลาออนไลน์ที่ Agent บันทึกได้สัปดาห์นี้')
      : 'เวลาใช้งานคอมพิวเตอร์สัปดาห์นี้';
  String get dataSourceLabel => !liveMode
      ? 'ข้อมูลจำลอง'
      : _freshSnapshot == null
      ? (liveError ?? 'กำลังเชื่อมต่อเครื่อง')
      : 'เชื่อมต่อแล้ว';
  List<Metric> get _liveMetrics {
    final data = _freshSnapshot, r = data?.readings ?? <String, double>{};
    Metric value(String id, String key, String label, String unit) {
      final reading = r[key];
      return Metric(
        id,
        label,
        reading == null ? '—' : '${reading.round()}$unit',
        reading?.clamp(0, 100) ?? 0,
        reading == null
            ? (data?.availability[key] ?? 'ยังไม่มีข้อมูลเซนเซอร์')
            : unit == '°C'
            ? 'อุณหภูมิที่อ่านได้'
            : 'การใช้งาน',
      );
    }

    final ram = r['ramUsed'], total = r['ramTotal'];
    return [
      value('cpu', 'cpu', 'CPU', '%'),
      value('gpu', 'gpu', 'GPU', '%'),
      Metric(
        'ram',
        'RAM',
        ram == null ? '—' : '${ram.toStringAsFixed(1)} GB',
        ram != null && total != null && total > 0
            ? (ram / total * 100).clamp(0, 100)
            : 0,
        total == null
            ? 'ยังไม่มีข้อมูลหน่วยความจำ'
            : 'จาก ${total.toStringAsFixed(1)} GB · ใช้ไป ${ram == null ? '—' : (ram / total * 100).round()}%',
      ),
      value('cpu-temp', 'cpuTemp', 'อุณหภูมิ CPU', '°C'),
      value('gpu-temp', 'gpuTemp', 'อุณหภูมิ GPU', '°C'),
    ];
  }

  void disconnectAgent() {
    _autoReconnect = false;
    if (discovery is AgentClient) (discovery as AgentClient).disconnect();
    _refreshVersion++;
    liveSnapshots.clear();
    for (final d in devices) {
      d.agent = AgentStatus.unreachable;
      d.readings = {};
    }
    liveError = 'ยกเลิกการเชื่อมต่อแล้ว กรุณาจับคู่ใหม่';
    _changed(persist: false);
  }

  Future<void> refreshLive() async {
    purgeClipboard();
    if (!liveMode || _disposed || _refreshing) return;
    _fallback();
    if (!liveConnected) {
      if (_autoReconnect &&
          gatewayUrl.isNotEmpty &&
          !connectingAgent &&
          (_retryAfter == null || DateTime.now().isAfter(_retryAfter!))) {
        await connectAgent();
        return;
      }
      liveSnapshots.clear();
      liveError ??=
          'เปิด Tailscale และเปิด Mimo Agent บน PC แล้วลองค้นหาอีกครั้ง';
      _changed(persist: false);
      return;
    }
    final source = discovery as LiveDataSource,
        version = _refreshVersion,
        id = activeDeviceId;
    _refreshing = true;
    try {
      final available = await discovery.discover('live');
      if (_disposed || version != _refreshVersion) return;
      for (final d in devices) {
        final found = available.where((a) => a.machine.id == d.id).firstOrNull;
        if (found != null) {
          if (d.id != id) observeOnline(d.id, found.machine.online);
          d.machine = found.machine;
          d.agent = found.agent;
        } else {
          d.agent = AgentStatus.unreachable;
        }
      }
      final device = devices.where((d) => d.id == id).firstOrNull;
      if (device == null) {
        liveError = null;
        _changed(persist: false);
        return;
      }
      if (!device.canOperate &&
          !(device.machine.online && device.machine.agentUrl.isNotEmpty)) {
        observeOnline(device.id, false);
        liveSnapshots.remove(id);
        device.readings = {};
        liveError = device.blockedReason;
        _changed(persist: false);
        return;
      }
      final snapshot = await source.fetchSnapshot(device.id);
      if (_disposed ||
          version != _refreshVersion ||
          !source.connected ||
          !devices.contains(device)) {
        return;
      }
      liveSnapshots[device.id] = snapshot;
      device.readings = {...snapshot.readings};
      device.agent = AgentStatus.ready;
      observeOnline(device.id, true);
      if (snapshot.clipboard) await refreshClipboard(device.id);
      liveError = null;
      _changed(persist: false);
    } catch (error) {
      if (_disposed || version != _refreshVersion) return;
      liveSnapshots.remove(id);
      final device = devices.where((d) => d.id == id).firstOrNull;
      if (device != null) {
        observeOnline(device.id, false);
        device.agent = AgentStatus.unreachable;
        device.readings = {};
      }
      liveError = error.toString();
      _changed(persist: false);
    } finally {
      _refreshing = false;
      if (!_disposed && version == _refreshVersion && id != activeDeviceId) {
        unawaited(refreshLive());
      }
    }
  }

  String _id(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_serial++}';
  void _tick() {
    final d = active;
    if (d == null || !d.canOperate) return;
    final random = Random();
    d.readings['cpu'] = ((d.readings['cpu'] ?? 18) + random.nextInt(7) - 3)
        .clamp(5, 98)
        .toDouble();
    d.readings['gpu'] = ((d.readings['gpu'] ?? 29) + random.nextInt(5) - 2)
        .clamp(2, 99)
        .toDouble();
    d.readings['cpuTemp'] = (38 + (d.readings['cpu'] ?? 18) * .22)
        .roundToDouble();
    d.readings['gpuTemp'] = (40 + (d.readings['gpu'] ?? 29) * .2)
        .roundToDouble();
    _changed(persist: false);
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshVersion++;
    if (discovery is AgentClient) (discovery as AgentClient).close();
    _sequence++;
    _telemetry?.cancel();
    for (final timer in _transfersTimers) {
      timer.cancel();
    }
    super.dispose();
  }
}
