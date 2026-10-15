import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimo_companion/domain/shortcuts.dart';
import 'package:mimo_companion/domain/models.dart';
import 'package:mimo_companion/data/services.dart';
import 'package:mimo_companion/state/mimo_store.dart';

void main() {
  test(
    'chords confirm only simultaneous contacts after all release; cancel and sequential keys never merge',
    () {
      final capture = ChordCapture();
      capture.down(1, 'Ctrl');
      capture.down(2, 'C');
      expect(capture.up(2), isNull);
      expect(capture.active, isTrue);
      expect(capture.up(1), ['Ctrl', 'C']);
      capture.down(1, 'Ctrl');
      expect(capture.up(1), isNull);
      capture.down(2, 'V');
      expect(capture.up(2), ['V']);
      capture.down(1, 'Ctrl');
      capture.down(2, 'C');
      capture.up(2);
      capture.down(3, 'V');
      capture.up(3);
      expect(capture.up(1), isNull);
      capture.down(1, 'Alt');
      capture.down(2, 'Tab');
      capture.up(1, cancelled: true);
      expect(capture.up(2), isNull);
      expect(
        () => normalizeChord(['Ctrl', 'Alt', 'Delete']),
        throwsFormatException,
      );
      expect(() => parseChord('powershell.exe'), throwsFormatException);
    },
  );
  test(
    'pins cap at four, persist per machine, retain order on editing and disappear on removal',
    () async {
      final fixture =
          jsonDecode(File('assets/data/seed.json').readAsStringSync()) as Json;
      final repository = MemoryRepository();
      final store = MimoStore(repository: repository);
      await store.initialize(fixture: fixture, simulate: false);
      final group = store.groups.first['id'] as String;
      expect(store.addButton('bad', '', 'custom', '', group), isNotNull);
      final ids = <String>[];
      for (var i = 0; i < 5; i++) {
        expect(
          store.addButton(
            'ปุ่ม $i',
            '',
            'custom',
            'Ctrl + ${String.fromCharCode(65 + i)}',
            group,
          ),
          isNull,
        );
        ids.add(store.buttons.last['id'] as String);
      }
      for (final id in ids.take(4)) {
        expect(store.togglePin(id), isNull);
      }
      expect(store.togglePin(ids.last), contains('4'));
      expect(store.pinnedIds, ids.take(4).toList());
      expect(
        store.addButton(
          'แก้ไข',
          '',
          'custom',
          'Ctrl + Shift + S',
          group,
          editingId: ids.first,
        ),
        isNull,
      );
      expect(store.pinnedButtons.first['name'], 'แก้ไข');
      store.selectDevice('studio');
      expect(store.pinnedIds, isEmpty);
      store.selectDevice('desktop');
      await store.flush();
      final reloaded = MimoStore(repository: repository);
      await reloaded.initialize(fixture: fixture, simulate: false);
      expect(reloaded.pinnedIds, ids.take(4).toList());
      reloaded.removeButton(ids.first);
      expect(reloaded.pinnedIds.length, 3);
      reloaded.dispose();
      store.dispose();
    },
  );
}
