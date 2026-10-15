import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/models.dart';

abstract interface class DeviceDiscovery {
  Future<List<DiscoveredDevice>> discover(String scenario);
}

class MockDeviceDiscovery implements DeviceDiscovery {
  const MockDeviceDiscovery({this.delay = const Duration(milliseconds: 650)});
  final Duration delay;
  @override
  Future<List<DiscoveredDevice>> discover(String scenario) async {
    await Future<void>.delayed(delay);
    if (scenario == 'error') {
      throw StateError('ค้นหาไม่สำเร็จ กรุณาลองอีกครั้ง');
    }
    if (scenario == 'empty') return [];
    return const [
      DiscoveredDevice(
        TailMachine(
          id: 'ts-work-001',
          hostname: 'workstation-01',
          ip: '100.80.20.11',
          os: 'Windows 11',
          online: true,
        ),
        AgentStatus.ready,
      ),
      DiscoveredDevice(
        TailMachine(
          id: 'ts-laptop-002',
          hostname: 'personal-laptop',
          ip: '100.80.20.12',
          os: 'macOS',
          online: false,
        ),
        AgentStatus.unreachable,
      ),
      DiscoveredDevice(
        TailMachine(
          id: 'ts-linux-003',
          hostname: 'linux-home',
          ip: '100.80.20.13',
          os: 'Linux',
          online: true,
        ),
        AgentStatus.missing,
      ),
    ];
  }
}

abstract interface class LocalRepository {
  Future<Json?> read();
  Future<void> write(Json value);
}

class PreferencesRepository implements LocalRepository {
  static const key = 'mimo:flutter_prototype:v1';
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  @override
  Future<Json?> read() async {
    final raw = await _preferences.getString(key);
    return raw == null
        ? null
        : Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  @override
  Future<void> write(Json value) =>
      _preferences.setString(key, jsonEncode(value));
}

class MemoryRepository implements LocalRepository {
  Json? value;
  @override
  Future<Json?> read() async =>
      value == null ? null : jsonDecode(jsonEncode(value)) as Json;
  @override
  Future<void> write(Json value) async {
    this.value = jsonDecode(jsonEncode(value)) as Json;
  }
}

Future<Json> loadSeed() async =>
    jsonDecode(await rootBundle.loadString('assets/data/seed.json')) as Json;
