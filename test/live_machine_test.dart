// Explicitly opt-in: talks to the local read-only Mimo Agent, never used by CI.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:mimo_companion/data/agent_client.dart';
import 'package:mimo_companion/data/services.dart';
import 'package:mimo_companion/domain/models.dart';
import 'package:mimo_companion/state/mimo_store.dart';
import 'package:mimo_companion/ui/mimo_app.dart';

void main() {
  if (!const bool.fromEnvironment('MIMO_LIVE_TEST')) {
    test(
      'real machine integration requires MIMO_LIVE_TEST',
      () {},
      skip: 'opt-in local Agent test',
    );
    return;
  }
  // Construct real IO transport before the widget test installs its fake HTTP override.
  final transport = HttpClient();
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Flutter displays authenticated live PC telemetry, without synthetic temperatures',
    (tester) async {
      final client = AgentClient(client: IOClient(transport));
      final store = MimoStore(
        repository: MemoryRepository(),
        discovery: client,
        liveMode: true,
      );
      final seed =
          jsonDecode(File('assets/data/seed.json').readAsStringSync()) as Json;
      await tester.runAsync(() async {
        await store.initialize(fixture: seed, simulate: false);
        final private =
            jsonDecode(
                  File(
                    '${const String.fromEnvironment('MIMO_AGENT_STATE', defaultValue: '.local/agent')}/pairing.local.json',
                  ).readAsStringSync(),
                )
                as Map;
        await client.pair(
          const String.fromEnvironment(
            'MIMO_AGENT_URL',
            defaultValue: 'http://127.0.0.1:8765',
          ),
          private['code'] as String,
        );
        await store.searchDevices('live');
        final host = store.discovered.firstWhere(
          (d) => d.agent == AgentStatus.ready,
        );
        store.saveDevice(
          host.machine.id,
          'คอมของฉัน · ข้อมูลจริง',
          candidate: host,
        );
        for (int i = 0; i < 20 && store.liveSnapshots.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
        await store.refreshLive();
        expect(store.metrics.first.value, isNot('—'), reason: store.liveError);
        expect(store.metrics[2].value, isNot('—'));
        expect(
          store.canRunCommands,
          store.liveSnapshots[store.activeDeviceId]!.commands,
        );
        expect(store.canSendFiles, isFalse);
        final readings = store.liveSnapshots[store.activeDeviceId]!.readings;
        expect(readings['cpu'], inInclusiveRange(0, 100));
        expect(readings['ramTotal'], greaterThan(0));
        if (!readings.containsKey('cpuTemp')) {
          expect(store.metrics[3].value, '—');
        }
        for (final entry in {
          'Poppins': ['Poppins-Regular.ttf', 'Poppins-Bold.ttf'],
          'MimoDisplay': ['LilitaOne-Regular.ttf'],
          'NotoSansThai': ['NotoSansThai.ttf'],
          'MaterialIcons': ['../unused'],
        }.entries) {
          final loader = FontLoader(entry.key);
          for (final font in entry.value) {
            loader.addFont(
              rootBundle.load(
                entry.key == 'MaterialIcons'
                    ? 'fonts/MaterialIcons-Regular.otf'
                    : 'assets/fonts/$font',
              ),
            );
          }
          await loader.load();
        }
      });
      for (final width in [320.0, 390.0]) {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        store.navigate(DemoScreen.status);
        await tester.pumpWidget(
          RepaintBoundary(
            key: const Key('live-proof'),
            child: MimoApp(store: store),
          ),
        );
        await tester.runAsync(() async {
          final context = tester.element(find.byType(MimoApp));
          await Future.wait([
            for (final name in [
              'room-header-original.png',
              'profile-original.png',
              'settings-original.png',
              'bell-original.png',
            ])
              precacheImage(AssetImage('assets/art/$name'), context),
          ]);
        });
        await tester.pumpAndSettle();
        expect(find.textContaining('ข้อมูลจริง'), findsWidgets);
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final boundary = tester.firstRenderObject<RenderRepaintBoundary>(
            find.byKey(const Key('live-proof')),
          );
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          Directory('.local/verification').createSync(recursive: true);
          File(
            '.local/verification/live-status-${width.toInt()}.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
      store.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
}
