import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimo_companion/ui/chord_keyboard.dart';
import 'package:mimo_companion/ui/mimo_app.dart';
import 'package:mimo_companion/state/mimo_store.dart';
import 'package:mimo_companion/data/services.dart';
import 'package:mimo_companion/domain/models.dart';
import 'package:mimo_companion/ui/design.dart';
import 'ui_test.dart' show fonts, capture;

void main() {
  testWidgets(
    'add-button flow captures a chord in nested sheet, removes preset command field and pins new key',
    (tester) async {
      await tester.runAsync(fonts);
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      final fixture =
          jsonDecode(File('assets/data/seed.json').readAsStringSync()) as Json;
      final store = MimoStore(repository: MemoryRepository());
      await store.initialize(fixture: fixture, simulate: false);
      store.navigate(DemoScreen.keys);
      store.selectGroup(store.groups.first['id'] as String);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('proof'),
          child: MimoApp(store: store),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('เพิ่มปุ่ม').first);
      await tester.tap(find.text('เพิ่มปุ่ม').first);
      await tester.pumpAndSettle();
      expect(find.text('คำสั่งตัวอย่าง'), findsNothing);
      await tester.enterText(find.byType(TextFormField).first, 'วางข้อความ');
      await tester.tap(find.byKey(const Key('shortcut-binding')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chord-Ctrl')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('chord-V')));
      await tester.pump();
      expect(find.text('เลือกคีย์ลัด'), findsOneWidget);
      await capture(tester, 'add-keyboard-dialog-390');
      await tester.ensureVisible(find.byKey(const Key('confirm-chord')));
      await tester.tap(find.byKey(const Key('confirm-chord')));
      await tester.pumpAndSettle();
      expect(find.text('เลือกคีย์ลัด'), findsNothing);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('shortcut-binding')))
            .controller!
            .text,
        'Ctrl + V',
      );
      await tester.ensureVisible(find.text('บันทึกปุ่ม'));
      await tester.tap(find.text('บันทึกปุ่ม'));
      await tester.pumpAndSettle();
      expect(store.buttons.last['name'], 'วางข้อความ');
      expect(store.buttons.last['binding'], 'Ctrl + V');
      final id = store.buttons.last['id'] as String;
      await tester.ensureVisible(find.byKey(ValueKey('pin-$id')));
      await tester.tap(find.byKey(ValueKey('pin-$id')));
      await tester.pumpAndSettle();
      expect(store.pinnedIds, [id]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
  testWidgets(
    'sequential keyboard selection toggles keys and requires explicit valid confirmation',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      final results = <List<String>>[];
      await tester.runAsync(fonts);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('proof'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: mimoTheme(Brightness.dark),
            home: Scaffold(
              body: SingleChildScrollView(
                child: ChordKeyboard(onConfirmed: results.add),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chord-Ctrl')));
      await tester.pump();
      expect(results, isEmpty);
      await tester.ensureVisible(find.byKey(const Key('confirm-chord')));
      await tester.tap(find.byKey(const Key('confirm-chord')));
      await tester.pump();
      expect(results, isEmpty); // Modifier-only selection is invalid.
      await tester.tap(find.byKey(const ValueKey('chord-C')));
      await tester.pump();
      expect(results, isEmpty); // Sequential taps do not auto-confirm.
      await capture(tester, 'keyboard-selected-390');
      await tester.tap(find.byKey(const Key('confirm-chord')));
      await tester.pump();
      expect(results.single, ['Ctrl', 'C']);
      await tester.tap(find.byKey(const ValueKey('chord-C'))); // Toggle C off.
      await tester.tap(find.byTooltip('คีย์ด้านขวา'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('คีย์ด้านขวา'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chord-F12')));
      await tester.tap(find.byKey(const Key('confirm-chord')));
      await tester.pump();
      expect(results.last, ['Ctrl', 'F12']);
      await tester.pumpWidget(const SizedBox());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
  testWidgets(
    'ORDER renders two pins on Home and all four in its panel on mobile',
    (tester) async {
      await tester.runAsync(fonts);
      final fixture =
          jsonDecode(File('assets/data/seed.json').readAsStringSync()) as Json;
      final store = MimoStore(repository: MemoryRepository());
      await store.initialize(fixture: fixture, simulate: false);
      final group = store.groups.first['id'] as String;
      for (var i = 1; i <= 4; i++) {
        store.addButton(
          'Pinned $i',
          '',
          'custom',
          'Ctrl + ${String.fromCharCode(64 + i)}',
          group,
        );
        store.togglePin(store.buttons.last['id'] as String);
      }
      for (final width in [320.0, 390.0]) {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        store.navigate(DemoScreen.home);
        await tester.pumpWidget(
          RepaintBoundary(
            key: const Key('proof'),
            child: MimoApp(store: store),
          ),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final context = tester.element(find.byType(MimoApp));
          await Future.wait([
            for (final name in [
              'room-header-original.png',
              'profile-original.png',
              'settings-original.png',
              'bell-original.png',
              'mimo-peeking-original.png',
              'computer-original.png',
            ])
              precacheImage(AssetImage('assets/art/$name'), context),
          ]);
        });
        await tester.pumpAndSettle();
        expect(find.text('Pinned 1'), findsOneWidget);
        expect(find.text('Pinned 2'), findsOneWidget);
        expect(find.text('Pinned 3'), findsNothing);
        await capture(tester, 'order-home-${width.toInt()}');
        await tester.ensureVisible(find.text('ORDER'));
        await tester.tap(find.text('ORDER'));
        await tester.pumpAndSettle();
        expect(find.text('Pinned 3'), findsOneWidget);
        expect(find.text('Pinned 4'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capture(tester, 'order-pins-${width.toInt()}');
        await tester.tap(find.byTooltip('ปิด').last);
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(const SizedBox());
      store.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
}
