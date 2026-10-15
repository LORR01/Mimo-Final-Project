import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
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
  testWidgets(
    'mobile clipboard categories, image attachment preview, TTL removal and notification read state',
    (tester) async {
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII=',
      );
      final client = AgentClient(
        client: MockClient((request) async {
          if (request.url.path == '/v1/pair') {
            return http.Response(
              jsonEncode({
                'token': 'test-only',
                'deviceId': 'desktop',
                'expiresAt': DateTime.now()
                    .add(const Duration(hours: 1))
                    .toIso8601String(),
              }),
              200,
            );
          }
          return http.Response.bytes(png, 200);
        }),
      );
      final store = MimoStore(
        repository: MemoryRepository(),
        discovery: client,
      );
      await store.initialize(
        fixture:
            jsonDecode(File('assets/data/seed.json').readAsStringSync())
                as Json,
        simulate: false,
      );
      await client.pair('http://127.0.0.1:8765', '123456');
      store.selectDevice('desktop');
      store.clipboard['desktop'] = [
        for (final type in ['text', 'link', 'image', 'document', 'spreadsheet'])
          {
            'id': type,
            'deviceId': 'desktop',
            'type': type,
            'title': 'TEST $type',
            'preview': 'ข้อมูล $type',
            'expiresAt': DateTime.now()
                .add(const Duration(minutes: 30))
                .toUtc()
                .toIso8601String(),
            if (type == 'image') 'fileName': 'image.png',
            if (type == 'document') 'fileName': 'report.pdf',
            if (type == 'spreadsheet') 'fileName': 'table.tsv',
          },
      ];
      await tester.runAsync(fonts);
      try {
        for (final width in [320.0, 390.0]) {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          store.navigate(DemoScreen.clipboard);
          store.setClipFilter('all');
          await tester.pumpWidget(
            RepaintBoundary(
              key: const Key('proof'),
              child: MimoApp(store: store),
            ),
          );
          await tester.pumpAndSettle();
          for (final entry in {
            'ข้อความ': 'text',
            'ลิงก์': 'link',
            'รูปภาพ': 'image',
            'เอกสาร': 'document',
            'ตาราง': 'spreadsheet',
          }.entries) {
            final chip = find.widgetWithText(ChoiceChip, entry.key);
            await tester.ensureVisible(chip);
            await tester.tap(chip);
            await tester.pumpAndSettle();
            expect(find.text('TEST ${entry.value}'), findsOneWidget);
            if (entry.value == 'image') {
              await tester.ensureVisible(find.text('TEST image'));
              await tester.ensureVisible(find.text('ดูรูป'));
              await tester.tap(find.text('ดูรูป'));
              await tester.pumpAndSettle();
              expect(
                find.byKey(const Key('clipboard-preview')),
                findsOneWidget,
              );
              await capture(tester, 'clipboard-image-${width.toInt()}');
              await tester.tap(find.byTooltip('ปิด').last);
              await tester.pumpAndSettle();
            }
            expect(tester.takeException(), isNull);
          }
          store.setClipFilter('all');
          await tester.pumpAndSettle();
        }
        store.observeOnline('desktop', true);
        store.observeOnline('desktop', false);
        store.setTheme('dark'); // Notify UI after simulated status event.
        await tester.pumpAndSettle();
        expect(store.unreadNotifications, 1);
        await tester.ensureVisible(find.byTooltip('Notifications'));
        await tester.tap(find.byTooltip('Notifications'));
        await tester.pumpAndSettle();
        expect(find.textContaining('ออฟไลน์'), findsWidgets);
        await capture(tester, 'notifications-390');
        await tester.tap(find.byTooltip('ปิด').last);
        await tester.pumpAndSettle();
        expect(store.unreadNotifications, 0);
        for (final item in store.clips) {
          item['expiresAt'] = DateTime.now()
              .subtract(const Duration(seconds: 1))
              .toUtc()
              .toIso8601String();
        }
        store.purgeClipboard();
        await tester.pumpAndSettle();
        expect(store.clips, isEmpty);
        expect(find.text('TEST image'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      } finally {
        store.dispose();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    },
  );
}
