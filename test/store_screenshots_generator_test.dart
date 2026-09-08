import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crispchess/main.dart' as app;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> loadFont(String family, List<String> candidates) async {
  for (final path in candidates) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final bytes = await file.readAsBytes();
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
    return;
  }
  throw StateError('Could not find font files for $family');
}

Future<void> loadStoreFonts() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '';
  final bodyFontCandidates = [
    '$flutterRoot/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  ];
  for (final family in [
    'StoreScreenshot',
    'Ahem',
    'Roboto',
    '.SF UI Text',
    '.SF UI Display',
    'monospace',
  ]) {
    await loadFont(family, bodyFontCandidates);
  }
  await loadFont('MaterialIcons', [
    '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ]);
}

Future<void> settle(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 15),
  );
}

Future<void> saveShot(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name,
  double scale,
) async {
  debugPrint('STORE_RENDER_START:$name');
  await tester.runAsync(() async {
    final boundary = boundaryKey.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;
    final image = await boundary
        .toImage(pixelRatio: scale)
        .timeout(const Duration(seconds: 30), onTimeout: () {
          throw TimeoutException('Rasterization stalled for $name');
        });
    final data = await image
        .toByteData(format: ui.ImageByteFormat.png)
        .timeout(const Duration(seconds: 30), onTimeout: () {
          throw TimeoutException('PNG encoding stalled for $name');
        });
    if (data == null) throw StateError('Could not encode $name');
    final output = Directory(
      Platform.environment['SCREENSHOT_OUTPUT'] ?? 'appstore-shots',
    );
    output.createSync(recursive: true);
    await File('${output.path}/$name.png')
        .writeAsBytes(data.buffer.asUint8List())
        .timeout(const Duration(seconds: 30), onTimeout: () {
          throw TimeoutException('File writing stalled for $name');
        });
  });
  debugPrint('STORE_RENDER_DONE:$name');
}

Future<void> captureLocale(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String language,
  String locale,
  String suffix,
  double scale,
) async {
  final preferences = await SharedPreferences.getInstance();
  await preferences.clear();
  await preferences.setBool('onboarding_shown', true);
  await preferences.setString('locale', language);
  await preferences.setString('engine', 'Built-in');
  await preferences.setString('themeMode', 'light');
  app.localeNotifier.value = Locale(language);
  app.themeNotifier.value = ThemeMode.light;

  await tester.pumpWidget(
    RepaintBoundary(
      key: boundaryKey,
      child: const app.CrispChessApp(fontFamily: 'StoreScreenshot'),
    ),
  );
  debugPrint('STORE_RENDER_WIDGET:$locale-$suffix');
  await settle(tester);
  await saveShot(tester, boundaryKey, '$locale-01-play-$suffix', scale);

  final analysis = find.byIcon(Icons.analytics_outlined);
  expect(analysis, findsOneWidget);
  await tester.tap(analysis);
  await settle(tester);
  await saveShot(tester, boundaryKey, '$locale-02-analysis-$suffix', scale);

  final menu = find.byIcon(Icons.more_vert);
  expect(menu, findsOneWidget);
  await tester.tap(menu);
  await settle(tester);
  await saveShot(tester, boundaryKey, '$locale-03-tools-$suffix', scale);

  await tester.pumpWidget(const SizedBox.shrink());
  await settle(tester);
}

Future<void> captureDevice(
  WidgetTester tester, {
  required Size logicalSize,
  required double scale,
  required String suffix,
}) async {
  await tester.binding.setSurfaceSize(logicalSize);
  final boundaryKey = GlobalKey();
  await captureLocale(tester, boundaryKey, 'en', 'en-US', suffix, scale);
  await captureLocale(tester, boundaryKey, 'de', 'de-DE', suffix, scale);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final screenshotOutput = Platform.environment['SCREENSHOT_OUTPUT'];
  if (screenshotOutput == null || screenshotOutput.isEmpty) {
    test('store screenshot rendering is opt-in', () {}, skip: true);
    return;
  }

  testWidgets(
    'render exact EN/DE iPhone, iPad, and Mac store scenes',
    (tester) async {
      await tester.runAsync(loadStoreFonts);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      SharedPreferences.setMockInitialValues({});
      try {
        await captureDevice(
          tester,
          logicalSize: const Size(440, 956),
          scale: 3,
          suffix: 'iphone',
        );
        await captureDevice(
          tester,
          logicalSize: const Size(1032, 1376),
          scale: 2,
          suffix: 'ipad',
        );
        await captureDevice(
          tester,
          logicalSize: const Size(1440, 900),
          scale: 1,
          suffix: 'mac',
        );
        await tester.binding.setSurfaceSize(null);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
