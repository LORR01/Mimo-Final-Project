import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mimo_companion/data/agent_client.dart';
import 'package:mimo_companion/data/services.dart';
import 'package:mimo_companion/domain/models.dart';
import 'package:mimo_companion/state/mimo_store.dart';
import 'package:mimo_companion/ui/mimo_app.dart';
import 'ui_test.dart' show fonts, capture;

void main() {
  for (final fails in [false, true]) {
    testWidgets(
      'Android Tailscale resume ${fails ? "failure and retry" : "device list"} has no URL form or fake login',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        int opens = 0, attempts = 0;
        var fail = fails;
        final ready = Completer<void>();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel('mimo/tailscale'), (
              call,
            ) async {
              if (call.method == 'isInstalled') return true;
              if (call.method == 'openTailscale') opens++;
              return null;
            });
        final client = AgentClient(
          client: MockClient((request) async {
            if (request.url.path == '/v1/tailscale-session') {
              attempts++;
              await ready.future;
              if (fail) {
                return http.Response(
                  jsonEncode({'error': 'PC ยังไม่พร้อม กรุณาเปิด Agent'}),
                  503,
                );
              }
              return http.Response(
                jsonEncode({
                  'token': 'private-session',
                  'expiresAt': DateTime.now()
                      .add(const Duration(hours: 1))
                      .toIso8601String(),
                  'deviceId': 'pc',
                  'clientDeviceId': 'phone',
                }),
                200,
              );
            }
            return http.Response(
              jsonEncode({
                'devices': [
                  {
                    'machine': {
                      'id': 'pc',
                      'hostname': 'Work-PC',
                      'ip': '100.64.1.1',
                      'os': 'windows',
                      'online': true,
                    },
                    'agent': {'status': 'ready'},
                  },
                ],
              }),
              200,
            );
          }),
        );
        final store = MimoStore(
          repository: MemoryRepository(),
          discovery: client,
          liveMode: true,
          configuredGateway: 'https://pc.example.ts.net:8443',
        );
        await store.initialize(
          fixture:
              jsonDecode(File('assets/data/seed.json').readAsStringSync())
                  as Json,
          simulate: false,
        );
        try {
          await tester.runAsync(fonts);
          await tester.pumpWidget(
            RepaintBoundary(
              key: const Key('proof'),
              child: MimoApp(store: store),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('get-started')));
          await tester.pumpAndSettle();
          expect(opens, 1);
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(find.text('กำลังค้นหา…'), findsOneWidget);
          expect(store.username, 'USERNAME');
          expect(find.byKey(const Key('agent-url')), findsNothing);
          // A simultaneous startup/retry joins the in-flight request.
          final joining = store.connectAgent();
          ready.complete();
          await tester.pumpAndSettle();
          expect(await joining, !fails);
          expect(attempts, 1);
          if (fails) {
            expect(find.byKey(const Key('network-error')), findsOneWidget);
            expect(store.username, 'USERNAME');
            await capture(tester, 'tailscale-error-390');
            fail = false;
            await tester.tap(find.byKey(const Key('search-devices')));
            await tester.pumpAndSettle();
            expect(attempts, 2);
          }
          expect(find.byKey(const Key('discovered-pc')), findsOneWidget);
          expect(store.username, 'MIMO');
          expect(find.byType(TextField), findsNothing);
          expect(tester.takeException(), isNull);
          await capture(tester, 'tailscale-devices-390');
          await tester.tap(find.byTooltip('ปิด').last);
          await tester.pumpAndSettle();
          await tester.pumpWidget(const SizedBox());
        } finally {
          store.dispose();
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
                const MethodChannel('mimo/tailscale'),
                null,
              );
          debugDefaultTargetPlatformOverride = null;
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        }
      },
    );
  }
}
