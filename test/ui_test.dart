import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimo_companion/data/services.dart';
import 'package:mimo_companion/domain/models.dart';
import 'package:mimo_companion/state/mimo_store.dart';
import 'package:mimo_companion/ui/mimo_app.dart';

bool _fontsLoaded = false;
Future<void> fonts() async {
  if (_fontsLoaded) return;
  final icons = FontLoader('MaterialIcons');
  icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
  for (final entry in {
    'Poppins': ['Poppins-Regular.ttf', 'Poppins-Bold.ttf'],
    'MimoDisplay': ['LilitaOne-Regular.ttf'],
    'NotoSansThai': ['NotoSansThai.ttf'],
  }.entries) {
    final loader = FontLoader(entry.key);
    for (final font in entry.value) {
      loader.addFont(rootBundle.load('assets/fonts/$font'));
    }
    await loader.load();
  }
  _fontsLoaded = true;
}

Future<void> capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('CAPTURE')) return;
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final boundary = tester.firstRenderObject<RenderRepaintBoundary>(
      find.byKey(const Key('proof')),
    );
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('docs/screenshots')
      ..createSync(recursive: true);
    File(
      '${directory.path}/$name.png',
    ).writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixture =
      jsonDecode(File('assets/data/seed.json').readAsStringSync()) as Json;
  testWidgets(
    'mobile screens at 320 and 390 in both themes, screenshots and empty states',
    (tester) async {
      await tester.runAsync(fonts);
      for (final width in [320.0, 390.0]) {
        for (final theme in ['dark', 'light']) {
          tester.view.physicalSize = Size(width, 844);
          tester.view.devicePixelRatio = 1;
          final store = MimoStore(repository: MemoryRepository());
          await store.initialize(fixture: fixture, simulate: false);
          store.setTheme(theme);
          await tester.pumpWidget(
            RepaintBoundary(
              key: const Key('proof'),
              child: MimoApp(store: store),
            ),
          );
          for (final screen in DemoScreen.values) {
            store.navigate(screen);
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: '${screen.name} $theme $width',
            );
            await capture(tester, '${screen.name}-$theme-${width.toInt()}');
          }
          store.focusMetric('cpu');
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await capture(tester, 'focus-$theme-${width.toInt()}');
          for (final d in [...store.devices]) {
            store.removeDevice(d.id);
          }
          for (final screen in [
            DemoScreen.home,
            DemoScreen.status,
            DemoScreen.keys,
            DemoScreen.devices,
            DemoScreen.clipboard,
            DemoScreen.files,
          ]) {
            store.navigate(screen);
            await tester.pumpAndSettle();
            expect(find.text('ยังไม่มีอุปกรณ์ใน Mimo'), findsOneWidget);
            expect(tester.takeException(), isNull);
          }
          await tester.pumpWidget(const SizedBox());
          store.dispose();
        }
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
  testWidgets(
    'native discovery/name sheet validation, select and header overlay',
    (tester) async {
      await tester.runAsync(fonts);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      final store = MimoStore(
        repository: MemoryRepository(),
        discovery: const MockDeviceDiscovery(delay: Duration.zero),
      );
      await store.initialize(fixture: fixture, simulate: false);
      store.navigate(DemoScreen.devices);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('proof'),
          child: MimoApp(store: store),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('add-device')),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('add-device')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('search-devices')));
      await tester.pumpAndSettle();
      expect(find.text('workstation-01'), findsOneWidget);
      await capture(tester, 'discovery-dark-390');
      await tester.tap(find.byKey(const Key('discovered-ts-work-001')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('device-name')), '   ');
      await tester.tap(find.byKey(const Key('save-device-name')));
      await tester.pumpAndSettle();
      expect(find.text('กรุณาใส่ชื่อแสดงใน Mimo'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('device-name')), 'คอมทำงาน');
      await capture(tester, 'naming-dark-390');
      await tester.tap(find.byKey(const Key('save-device-name')));
      await tester.pumpAndSettle();
      expect(store.active!.displayName, 'คอมทำงาน');
      store.navigate(DemoScreen.home);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('device-switcher')));
      await tester.pumpAndSettle();
      expect(find.text('เลือกอุปกรณ์ (SELECT DEVICE)'), findsOneWidget);
      await capture(tester, 'dropdown-dark-390');
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Studio-PC').last);
      await tester.pumpAndSettle();
      expect(store.activeDeviceId, 'studio');
      await tester.pumpWidget(const SizedBox());
      store.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
}
