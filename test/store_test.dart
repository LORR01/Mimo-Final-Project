import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimo_companion/domain/models.dart';
import 'package:mimo_companion/data/services.dart';
import 'package:mimo_companion/state/mimo_store.dart';

void main() {
  late MimoStore store;
  late MemoryRepository repository;
  final fixture =
      jsonDecode(File('assets/data/seed.json').readAsStringSync()) as Json;
  setUp(() async {
    repository = MemoryRepository();
    store = MimoStore(
      repository: repository,
      discovery: const MockDeviceDiscovery(delay: Duration.zero),
      transferDelay: Duration.zero,
    );
    await store.initialize(fixture: fixture, simulate: false);
  });
  tearDown(() => store.dispose());
  test(
    'discovery transitions, deduplicates, and keeps identity independent of alias',
    () async {
      final pending = store.searchDevices('found');
      expect(store.discoveryState, DiscoveryState.searching);
      await pending;
      expect(store.discovered.length, 3);
      final candidate = store.discovered.first;
      expect(
        store.saveDevice(candidate.machine.id, '   ', candidate: candidate),
        isNotNull,
      );
      expect(
        store.saveDevice(
          candidate.machine.id,
          'คอมทำงาน',
          candidate: candidate,
        ),
        isNull,
      );
      expect(store.activeDeviceId, 'ts-work-001');
      expect(store.active!.machine.hostname, 'workstation-01');
      await store.searchDevices('found');
      await store.searchDevices('found');
      expect(store.discovered.length, 2);
      expect(store.saveDevice('ts-work-001', 'ชื่อใหม่'), isNull);
      expect(store.active!.id, 'ts-work-001');
      await store.flush();
      final reloaded = MimoStore(repository: repository);
      await reloaded.initialize(fixture: fixture, simulate: false);
      expect(reloaded.active!.displayName, 'ชื่อใหม่');
      expect(reloaded.devices.length, 4);
      reloaded.dispose();
    },
  );
  test(
    'Tailscale online without Agent cannot send commands or files',
    () async {
      await store.searchDevices('found');
      final noAgent = store.discovered.last;
      store.saveDevice(noAgent.machine.id, 'Linux', candidate: noAgent);
      expect(store.active!.machine.online, isTrue);
      expect(store.active!.canOperate, isFalse);
      expect(store.sendFile(name: 'blocked.txt', size: 12), isNull);
      expect(store.toggleQuick('mic'), contains('Agent'));
      expect(store.metrics.first.value, '—');
      final offline = store.discovered.firstWhere((d) => !d.machine.online);
      store.saveDevice(offline.machine.id, 'Laptop', candidate: offline);
      expect(store.blockedReason, contains('ออฟไลน์'));
      expect(store.sendFile(name: 'blocked.txt', size: 12), isNull);
    },
  );
  test(
    'failure can retry, empty results and removing active/all devices persist',
    () async {
      await store.searchDevices('error');
      expect(store.discoveryState, DiscoveryState.error);
      await store.searchDevices('empty');
      expect(store.discoveryState, DiscoveryState.empty);
      await store.searchDevices('found');
      expect(store.discoveryState, DiscoveryState.found);
      store.removeDevice('desktop');
      expect(store.activeDeviceId, 'studio');
      for (final d in [...store.devices]) {
        store.removeDevice(d.id);
      }
      expect(store.active, isNull);
      expect(store.groups, isEmpty);
      expect(store.metrics.first.value, '—');
      await store.flush();
      final reloaded = MimoStore(repository: repository);
      await reloaded.initialize(fixture: fixture, simulate: false);
      expect(reloaded.devices, isEmpty);
      expect(reloaded.activeDeviceId, isNull);
      reloaded.dispose();
    },
  );
  test(
    'commands, clipboard, groups, weekly usage and transfers are per device',
    () async {
      final initial = store.weeklyTotal;
      store.toggleQuick('media');
      store.addClip('https://example.com');
      final clip = store.clips.first;
      store.toggleFavorite(clip['id'] as String);
      expect(store.favorites[clip['id']], isTrue);
      expect(store.addGroup('新 group', 'purple'), isNull);
      expect(store.addGroup('新 group', 'blue'), isNotNull);
      final group = store.groups.last['id'] as String;
      expect(
        store.addButton('Test', 'note', 'custom', 'Ctrl+M', group),
        isNull,
      );
      expect(
        store.runShortcut(store.buttons.last['id'] as String),
        contains('Ctrl + M'),
      );
      final transfer = store.sendFile(name: 'report.pdf', size: 1024);
      expect(transfer!.deviceId, 'desktop');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(transfer.done, isTrue);
      store.selectDevice('studio');
      expect(store.activeTransfers, isEmpty);
      expect(store.quick['media'], isFalse);
      expect(store.weeklyTotal, isNot(initial));
      expect(store.clips.any((c) => c['id'] == clip['id']), isFalse);
      store.selectDevice('desktop');
      expect(store.quick['media'], isTrue);
      store.setTheme('light');
      await store.flush();
      final reloaded = MimoStore(repository: repository);
      await reloaded.initialize(fixture: fixture, simulate: false);
      expect(reloaded.theme, 'light');
      expect(reloaded.clips.first['preview'], 'https://example.com');
      expect(reloaded.activeTransfers, isEmpty);
      reloaded.dispose();
    },
  );
}
