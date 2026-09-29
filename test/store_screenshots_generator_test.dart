import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crispchess/chess/chess_game.dart';
import 'package:crispchess/chess/human_lens.dart';
import 'package:crispchess/engines/ghost_engine.dart';
import 'package:crispchess/l10n/generated/app_localizations.dart';
import 'package:crispchess/main.dart' as app;
import 'package:crispchess/screens/chess_game_screen.dart';
import 'package:crispchess/screens/scan_board_screen.dart';
import 'package:crispchess/services/human_lens_service.dart';
import 'package:crispchess/voice/voice_input.dart';
import 'package:crispchess/widgets/chess_board.dart';
import 'package:crispchess/widgets/ghost_profile_card.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Scenes in App Store order: the features no other chess app has come first.
/// tools/capture-appstore-screenshots.sh lists the same names.
const scenes = [
  '01-lens',
  '02-scan',
  '03-ghost',
  '04-voice',
  '05-play',
  '06-analysis',
  '07-tools',
];

// Model output the widgets show. Produced by the real services in
// tool/store/store_fixtures_test.dart — the test itself has no network to
// download the models — except the board scan, which runs here for real on
// the bundled model.
const _fixtures = 'test/fixtures/store';
Map<String, dynamic> _json(String name) =>
    jsonDecode(File('$_fixtures/$name').readAsStringSync())
        as Map<String, dynamic>;

final Map<String, dynamic> lens = _json('lens.json')['chosen'];
final Map<String, dynamic> ghost = _json('ghost.json');
final Map<String, dynamic> voice = _json('voice.json')['chosen'];
final List<String> ghostGames = [
  for (final g in jsonDecode(
          File('$_fixtures/ghost_games.json').readAsStringSync()) as List)
    g['pgn'] as String
];
// book_noto.png from the board-vision fixtures, its placeholder caption
// cropped off (the recogniser still reads the board; it runs live below).
const scanImage = 'test/fixtures/store/scan_diagram.png';

HumanLensReport lensReport(Map<String, dynamic> j) => HumanLensReport(
      elo: j['elo'] as int,
      bestMove: j['bestMove'] as String?,
      candidates: [
        for (final c in j['candidates'] as List)
          HumanCandidate(
            uci: c['uci'] as String,
            probability: (c['probability'] as num).toDouble(),
            evalAfter: (c['evalAfter'] as num?)?.toDouble(),
            winChanceLoss: (c['winChanceLoss'] as num?)?.toDouble(),
          )
      ],
      findabilityByElo: {
        for (final e in (j['findabilityByElo'] as Map).entries)
          int.parse(e.key as String): (e.value as num).toDouble()
      },
    );

List<String> lensMoves() =>
    (lens['positionCommand'] as String).split(' ').skip(3).toList();

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
  // Roboto has no chess symbols (captured pieces are drawn as text).
  await loadFont('StoreSymbols', [
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  ]);
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

/// Lets real asynchronous work (image decoding, a recognition isolate) finish
/// until [done] holds, pumping frames in between.
Future<void> waitFor(WidgetTester tester, bool Function() done,
    {String what = 'condition'}) async {
  for (var i = 0; i < 300; i++) {
    if (done()) return;
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  final texts = find.byType(Text).evaluate().map((e) => (e.widget as Text).data);
  throw TimeoutException('Timed out waiting for $what; on screen: ${texts.join(' | ')}');
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

/// A fresh app in [language], with [prefs] on top of the common settings.
Future<void> launch(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String language, [
  Map<String, Object> prefs = const {},
]) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await settle(tester);
  final preferences = await SharedPreferences.getInstance();
  await preferences.clear();
  await preferences.setBool('onboarding_shown', true);
  await preferences.setString('locale', language);
  await preferences.setString('engine', 'Built-in');
  await preferences.setString('themeMode', 'light');
  // Already greeted today: no "Daily login" snackbar across the shot.
  await preferences.setString(
      'lastLoginDate', DateTime.now().toIso8601String().substring(0, 10));
  for (final e in prefs.entries) {
    switch (e.value) {
      case final bool v:
        await preferences.setBool(e.key, v);
      case final int v:
        await preferences.setInt(e.key, v);
      case final String v:
        await preferences.setString(e.key, v);
      case final List<String> v:
        await preferences.setStringList(e.key, v);
    }
  }
  app.localeNotifier.value = Locale(language);
  app.themeNotifier.value = ThemeMode.light;
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundaryKey,
      child: const app.CrispChessApp(
        fontFamily: 'StoreScreenshot',
        fontFamilyFallback: ['StoreSymbols'],
      ),
    ),
  );
  await settle(tester);
}

AppLocalizations l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(ChessGameScreen)))!;

/// Starts the app on a saved game at [moves] and takes the "Resume" offer.
Future<void> launchGame(WidgetTester tester, GlobalKey boundaryKey,
    String language, List<String> moves) async {
  final game = ChessGame();
  for (final m in moves) {
    expect(game.makeMove(m), isTrue, reason: 'move $m');
  }
  await launch(tester, boundaryKey, language, {
    'gameFen': game.currentFEN,
    'gameMoves': moves.join(' '),
  });
  // The app offers the saved game half a second after start.
  await tester.pump(const Duration(seconds: 1));
  await settle(tester);
  final resume = find.widgetWithText(FilledButton, l10n(tester).resume);
  expect(resume, findsOneWidget);
  await tester.tap(resume);
  await settle(tester);
}

Future<void> openMenuItem(WidgetTester tester, List<String> path) async {
  await tester.tap(find.byIcon(Icons.more_vert));
  await settle(tester);
  for (final label in path) {
    await tester.tap(find.text(label).last);
    await settle(tester);
  }
}

Future<void> captureLocale(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String language,
  String locale,
  String suffix,
  double scale,
) async {
  Future<void> shot(String scene) =>
      saveShot(tester, boundaryKey, '$locale-$scene-$suffix', scale);

  // 01 Human Lens over a position of a real game.
  await launchGame(tester, boundaryKey, language, lensMoves());
  await tester.tap(find.byIcon(Icons.analytics_outlined));
  await settle(tester);
  await tester.tap(find.byIcon(Icons.groups));
  await settle(tester);
  expect(find.byIcon(Icons.star), findsWidgets);
  // Pull the sheet down to where it still fits, so more of the game shows.
  await tester.drag(find.byIcon(Icons.groups).last,
      Offset(0, tester.getSize(find.byType(MaterialApp)).height * 0.12));
  await settle(tester);
  await shot('01-lens');

  // 02 Board scan of a book diagram, recognised here by the bundled model.
  await launch(tester, boundaryKey, language);
  final l = l10n(tester);
  // What Import / Export > Scan board opens (a submenu opens on hover, which
  // a test cannot do).
  unawaited(Navigator.of(tester.element(find.byType(ChessGameScreen))).push(
      MaterialPageRoute<String>(builder: (_) => const ScanBoardScreen())));
  await settle(tester);
  // Tapped in the real zone, so that decoding the image and the recognition
  // isolate run on real time rather than the test's fake clock.
  await tester.runAsync(() async => tester.tap(find.byIcon(Icons.image_search)));
  await waitFor(
      tester,
      () =>
          // The recognised position's board appears under the image.
          find
              .descendant(
                  of: find.byType(ScanBoardScreen),
                  matching: find.byType(ChessBoard))
              .evaluate()
              .isNotEmpty &&
          find.byType(LinearProgressIndicator).evaluate().isEmpty,
      what: 'board recognition');
  // Something on the result keeps scheduling frames, so no pumpAndSettle.
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.drag(find.byType(ListView), const Offset(0, -2000));
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await shot('02-scan');

  // 03 Your Ghost in the engine settings, built from real games.
  await launch(tester, boundaryKey, language, {
    'gameHistory': ghostGames,
    ghostEloKey: ghost['elo'] as int,
    ghostEloGamesKey: ghost['games'] as int,
  });
  await openMenuItem(tester, [l.settings]);
  await tester.tap(find.text(ghostEngineName));
  await settle(tester);
  await tester.scrollUntilVisible(find.byType(GhostProfileCard), 300,
      scrollable: find.byType(Scrollable).first);
  // The card at the bottom, the engine list with its ratings above it.
  unawaited(Scrollable.ensureVisible(
      tester.element(find.byType(GhostProfileCard)),
      alignment: 0.7));
  await settle(tester);
  await shot('03-ghost');

  // 04 A spoken move the recogniser was unsure about: the app asks.
  final spoken = voice[language] as Map<String, dynamic>;
  ChessGameScreen.debugVoiceRanking = [
    for (final c in spoken['ranked'] as List)
      VoiceCandidate(c['uci'] as String, c['san'] as String,
          c['phrase'] as String, (c['score'] as num).toDouble())
  ];
  try {
    await launchGame(tester, boundaryKey, language,
        (spoken['moves'] as List).cast<String>());
    await tester.tap(find.byIcon(Icons.mic_none));
    await settle(tester);
    expect(find.text(l.voiceWhichMove), findsOneWidget);
    await shot('04-voice');
  } finally {
    ChessGameScreen.debugVoiceRanking = null;
  }

  // 05-07 The board, its analysis and the menu.
  await launch(tester, boundaryKey, language);
  await shot('05-play');

  final analysis = find.byIcon(Icons.analytics_outlined);
  expect(analysis, findsOneWidget);
  await tester.tap(analysis);
  await settle(tester);
  await shot('06-analysis');

  final menu = find.byIcon(Icons.more_vert);
  expect(menu, findsOneWidget);
  await tester.tap(menu);
  await settle(tester);
  await shot('07-tools');

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
  // STORE_DEVICES=iphone renders one size only, for a quick local look.
  final devices = (Platform.environment['STORE_DEVICES'] ?? 'iphone,ipad,mac')
      .split(',');

  testWidgets(
    'render exact EN/DE iPhone, iPad, and Mac store scenes',
    (tester) async {
      await tester.runAsync(loadStoreFonts);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      // A phone shows no keyboard focus rings; the test binding's default
      // (traditional) drew one around the Settings save button.
      FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
      // flutter_test draws every elevation shadow as a solid black outline
      // (debugDisableShadows); the store shots need the real shadows.
      debugDisableShadows = false;
      SharedPreferences.setMockInitialValues({});
      HumanLensService.debugReports = {
        '${lens['elo']} ${lens['positionCommand']}': lensReport(lens),
      };
      final scan = File(scanImage).readAsBytesSync();
      ScanBoardScreen.debugPickImage = () async => scan;
      try {
        if (devices.contains('iphone')) {
          await captureDevice(
            tester,
            logicalSize: const Size(440, 956),
            scale: 3,
            suffix: 'iphone',
          );
        }
        if (devices.contains('ipad')) {
          await captureDevice(
            tester,
            logicalSize: const Size(1032, 1376),
            scale: 2,
            suffix: 'ipad',
          );
        }
        if (devices.contains('mac')) {
          await captureDevice(
            tester,
            logicalSize: const Size(1440, 900),
            scale: 1,
            suffix: 'mac',
          );
        }
        await tester.binding.setSurfaceSize(null);
      } finally {
        debugDisableShadows = true;
        debugDefaultTargetPlatformOverride = null;
        HumanLensService.debugReports = null;
        ScanBoardScreen.debugPickImage = null;
      }
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
