import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationsDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Localizations support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you'll need to edit this
/// file.
///
/// Read more about configuring the Info.plist at
/// <https://developer.apple.com/documentation/bundleresources/information_property_list>
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'CrispChess'**
  String get appTitle;

  /// No description provided for @yourTurn.
  ///
  /// In en, this message translates to:
  /// **'Your turn'**
  String get yourTurn;

  /// No description provided for @whiteToMove.
  ///
  /// In en, this message translates to:
  /// **'White to move'**
  String get whiteToMove;

  /// No description provided for @blackToMove.
  ///
  /// In en, this message translates to:
  /// **'Black to move'**
  String get blackToMove;

  /// No description provided for @thinking.
  ///
  /// In en, this message translates to:
  /// **'Thinking...'**
  String get thinking;

  /// No description provided for @engineError.
  ///
  /// In en, this message translates to:
  /// **'Engine error'**
  String get engineError;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading {engineName}...'**
  String loading(String engineName);

  /// No description provided for @downloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading & initializing...'**
  String get downloading;

  /// No description provided for @engineReady.
  ///
  /// In en, this message translates to:
  /// **'{engineName} ready'**
  String engineReady(String engineName);

  /// No description provided for @engineThinking.
  ///
  /// In en, this message translates to:
  /// **'{engineName} is thinking...'**
  String engineThinking(String engineName);

  /// No description provided for @newGame.
  ///
  /// In en, this message translates to:
  /// **'New Game'**
  String get newGame;

  /// No description provided for @newGameConfirm.
  ///
  /// In en, this message translates to:
  /// **'Current game will be lost.'**
  String get newGameConfirm;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @aboutCrispChess.
  ///
  /// In en, this message translates to:
  /// **'About CrispChess'**
  String get aboutCrispChess;

  /// No description provided for @puzzles.
  ///
  /// In en, this message translates to:
  /// **'Puzzles'**
  String get puzzles;

  /// No description provided for @flipBoard.
  ///
  /// In en, this message translates to:
  /// **'Flip Board'**
  String get flipBoard;

  /// No description provided for @copyPgn.
  ///
  /// In en, this message translates to:
  /// **'Copy PGN'**
  String get copyPgn;

  /// No description provided for @pastePgn.
  ///
  /// In en, this message translates to:
  /// **'Paste PGN'**
  String get pastePgn;

  /// No description provided for @loadFen.
  ///
  /// In en, this message translates to:
  /// **'Load FEN'**
  String get loadFen;

  /// No description provided for @setupPosition.
  ///
  /// In en, this message translates to:
  /// **'Setup Position'**
  String get setupPosition;

  /// No description provided for @pgnDatabase.
  ///
  /// In en, this message translates to:
  /// **'PGN Database'**
  String get pgnDatabase;

  /// No description provided for @offerDraw.
  ///
  /// In en, this message translates to:
  /// **'Offer Draw'**
  String get offerDraw;

  /// No description provided for @resign.
  ///
  /// In en, this message translates to:
  /// **'Resign'**
  String get resign;

  /// No description provided for @resignConfirm.
  ///
  /// In en, this message translates to:
  /// **'{engineName} wins by resignation.'**
  String resignConfirm(String engineName);

  /// No description provided for @drawDeclined.
  ///
  /// In en, this message translates to:
  /// **'{engineName} declines the draw offer.'**
  String drawDeclined(String engineName);

  /// No description provided for @drawAgreed.
  ///
  /// In en, this message translates to:
  /// **'Draw agreed'**
  String get drawAgreed;

  /// No description provided for @youResigned.
  ///
  /// In en, this message translates to:
  /// **'You resigned'**
  String get youResigned;

  /// No description provided for @gameResumed.
  ///
  /// In en, this message translates to:
  /// **'Game resumed'**
  String get gameResumed;

  /// No description provided for @resumeGame.
  ///
  /// In en, this message translates to:
  /// **'Resume game?'**
  String get resumeGame;

  /// No description provided for @savedGameMoves.
  ///
  /// In en, this message translates to:
  /// **'You have a saved game ({count} moves).'**
  String savedGameMoves(String count);

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @resume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resume;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @review.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get review;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @redo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get redo;

  /// No description provided for @hint.
  ///
  /// In en, this message translates to:
  /// **'Hint'**
  String get hint;

  /// No description provided for @analyze.
  ///
  /// In en, this message translates to:
  /// **'Analyze'**
  String get analyze;

  /// No description provided for @abort.
  ///
  /// In en, this message translates to:
  /// **'Abort'**
  String get abort;

  /// No description provided for @playAsWhite.
  ///
  /// In en, this message translates to:
  /// **'White'**
  String get playAsWhite;

  /// No description provided for @playAsBlack.
  ///
  /// In en, this message translates to:
  /// **'Black'**
  String get playAsBlack;

  /// No description provided for @playAsRandom.
  ///
  /// In en, this message translates to:
  /// **'Random'**
  String get playAsRandom;

  /// No description provided for @twoPlayer.
  ///
  /// In en, this message translates to:
  /// **'Two Player (local)'**
  String get twoPlayer;

  /// No description provided for @passAndPlay.
  ///
  /// In en, this message translates to:
  /// **'Pass and play'**
  String get passAndPlay;

  /// No description provided for @playAs.
  ///
  /// In en, this message translates to:
  /// **'Play as'**
  String get playAs;

  /// No description provided for @chessEngine.
  ///
  /// In en, this message translates to:
  /// **'Chess Engine'**
  String get chessEngine;

  /// No description provided for @opponentStrength.
  ///
  /// In en, this message translates to:
  /// **'Opponent Strength'**
  String get opponentStrength;

  /// No description provided for @hintDepth.
  ///
  /// In en, this message translates to:
  /// **'Hint Depth'**
  String get hintDepth;

  /// No description provided for @analysisDepth.
  ///
  /// In en, this message translates to:
  /// **'Analysis Depth: {depth}'**
  String analysisDepth(String depth);

  /// No description provided for @hintEngine.
  ///
  /// In en, this message translates to:
  /// **'Hint Engine'**
  String get hintEngine;

  /// No description provided for @sameAsOpponent.
  ///
  /// In en, this message translates to:
  /// **'Same as opponent'**
  String get sameAsOpponent;

  /// No description provided for @game.
  ///
  /// In en, this message translates to:
  /// **'Game'**
  String get game;

  /// No description provided for @showValidMoves.
  ///
  /// In en, this message translates to:
  /// **'Show Valid Moves'**
  String get showValidMoves;

  /// No description provided for @showValidMovesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Highlight legal moves when selecting a piece'**
  String get showValidMovesSubtitle;

  /// No description provided for @allowUndo.
  ///
  /// In en, this message translates to:
  /// **'Allow Undo'**
  String get allowUndo;

  /// No description provided for @allowUndoSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Disable for discipline mode'**
  String get allowUndoSubtitle;

  /// No description provided for @solidBlackPieces.
  ///
  /// In en, this message translates to:
  /// **'Solid Black Pieces'**
  String get solidBlackPieces;

  /// No description provided for @solidBlackPiecesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Render black pieces as solid black instead of grey gradient'**
  String get solidBlackPiecesSubtitle;

  /// No description provided for @animationSpeed.
  ///
  /// In en, this message translates to:
  /// **'Animation Speed'**
  String get animationSpeed;

  /// No description provided for @instant.
  ///
  /// In en, this message translates to:
  /// **'Instant'**
  String get instant;

  /// No description provided for @fast.
  ///
  /// In en, this message translates to:
  /// **'Fast'**
  String get fast;

  /// No description provided for @normal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get normal;

  /// No description provided for @slow.
  ///
  /// In en, this message translates to:
  /// **'Slow'**
  String get slow;

  /// No description provided for @timeControl.
  ///
  /// In en, this message translates to:
  /// **'Time Control'**
  String get timeControl;

  /// No description provided for @playAsBlackSetting.
  ///
  /// In en, this message translates to:
  /// **'Play as Black'**
  String get playAsBlackSetting;

  /// No description provided for @playAsBlackSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Engine makes the first move'**
  String get playAsBlackSubtitle;

  /// No description provided for @pieceStyle.
  ///
  /// In en, this message translates to:
  /// **'Piece Style'**
  String get pieceStyle;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @systemDefault.
  ///
  /// In en, this message translates to:
  /// **'System Default'**
  String get systemDefault;

  /// No description provided for @system.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get system;

  /// No description provided for @light.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get light;

  /// No description provided for @darkAmoled.
  ///
  /// In en, this message translates to:
  /// **'Dark (AMOLED)'**
  String get darkAmoled;

  /// No description provided for @resetToDefaults.
  ///
  /// In en, this message translates to:
  /// **'Reset to defaults'**
  String get resetToDefaults;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @pgnCopied.
  ///
  /// In en, this message translates to:
  /// **'PGN copied to clipboard'**
  String get pgnCopied;

  /// No description provided for @pgnLoaded.
  ///
  /// In en, this message translates to:
  /// **'PGN loaded'**
  String get pgnLoaded;

  /// No description provided for @invalidPgn.
  ///
  /// In en, this message translates to:
  /// **'Invalid PGN'**
  String get invalidPgn;

  /// No description provided for @noPgnInClipboard.
  ///
  /// In en, this message translates to:
  /// **'No PGN found in clipboard'**
  String get noPgnInClipboard;

  /// No description provided for @noMovesYet.
  ///
  /// In en, this message translates to:
  /// **'No moves yet'**
  String get noMovesYet;

  /// No description provided for @solved.
  ///
  /// In en, this message translates to:
  /// **'solved'**
  String get solved;

  /// No description provided for @showSolution.
  ///
  /// In en, this message translates to:
  /// **'Show Solution'**
  String get showSolution;

  /// No description provided for @nextPuzzle.
  ///
  /// In en, this message translates to:
  /// **'Next Puzzle'**
  String get nextPuzzle;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @wrongMove.
  ///
  /// In en, this message translates to:
  /// **'Wrong move. Try again. ({remaining} left)'**
  String wrongMove(String remaining);

  /// No description provided for @puzzleSolved.
  ///
  /// In en, this message translates to:
  /// **'Correct! Puzzle solved.'**
  String get puzzleSolved;

  /// No description provided for @findNextMove.
  ///
  /// In en, this message translates to:
  /// **'Correct! Find the next move.'**
  String get findNextMove;

  /// No description provided for @gameSummary.
  ///
  /// In en, this message translates to:
  /// **'Game Summary'**
  String get gameSummary;

  /// No description provided for @yourAccuracy.
  ///
  /// In en, this message translates to:
  /// **'Your Accuracy'**
  String get yourAccuracy;

  /// No description provided for @accuracy.
  ///
  /// In en, this message translates to:
  /// **'Accuracy'**
  String get accuracy;

  /// No description provided for @good.
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get good;

  /// No description provided for @mistakes.
  ///
  /// In en, this message translates to:
  /// **'Mistakes'**
  String get mistakes;

  /// No description provided for @myMistakes.
  ///
  /// In en, this message translates to:
  /// **'My Mistakes'**
  String get myMistakes;

  /// No description provided for @blunders.
  ///
  /// In en, this message translates to:
  /// **'Blunders'**
  String get blunders;

  /// No description provided for @evaluation.
  ///
  /// In en, this message translates to:
  /// **'Evaluation'**
  String get evaluation;

  /// No description provided for @yourBestMove.
  ///
  /// In en, this message translates to:
  /// **'Your Best Move'**
  String get yourBestMove;

  /// No description provided for @biggestMistake.
  ///
  /// In en, this message translates to:
  /// **'Biggest Mistake'**
  String get biggestMistake;

  /// No description provided for @moves.
  ///
  /// In en, this message translates to:
  /// **'Moves'**
  String get moves;

  /// No description provided for @tapToViewPosition.
  ///
  /// In en, this message translates to:
  /// **'Tap to view position'**
  String get tapToViewPosition;

  /// No description provided for @moveN.
  ///
  /// In en, this message translates to:
  /// **'Move {n}'**
  String moveN(String n);

  /// No description provided for @welcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome to CrispChess'**
  String get welcome;

  /// No description provided for @welcomeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Play chess against AI engines or a friend.'**
  String get welcomeSubtitle;

  /// No description provided for @letsPlay.
  ///
  /// In en, this message translates to:
  /// **'Let\'s play!'**
  String get letsPlay;

  /// No description provided for @switchToBuiltIn.
  ///
  /// In en, this message translates to:
  /// **'Switch to Built-in'**
  String get switchToBuiltIn;

  /// No description provided for @failedToInitialize.
  ///
  /// In en, this message translates to:
  /// **'{engineName}: failed to initialize'**
  String failedToInitialize(String engineName);

  /// No description provided for @checkmate.
  ///
  /// In en, this message translates to:
  /// **'Checkmate'**
  String get checkmate;

  /// No description provided for @stalemate.
  ///
  /// In en, this message translates to:
  /// **'Stalemate'**
  String get stalemate;

  /// No description provided for @drawThreefold.
  ///
  /// In en, this message translates to:
  /// **'Draw — threefold repetition'**
  String get drawThreefold;

  /// No description provided for @drawInsufficient.
  ///
  /// In en, this message translates to:
  /// **'Draw — insufficient material'**
  String get drawInsufficient;

  /// No description provided for @drawFiftyMove.
  ///
  /// In en, this message translates to:
  /// **'Draw — fifty-move rule'**
  String get drawFiftyMove;

  /// No description provided for @resignation.
  ///
  /// In en, this message translates to:
  /// **'Resignation'**
  String get resignation;

  /// No description provided for @drawByAgreement.
  ///
  /// In en, this message translates to:
  /// **'Draw by agreement'**
  String get drawByAgreement;

  /// No description provided for @gameOver.
  ///
  /// In en, this message translates to:
  /// **'Game Over'**
  String get gameOver;

  /// No description provided for @boardScreenshot.
  ///
  /// In en, this message translates to:
  /// **'Board Screenshot'**
  String get boardScreenshot;

  /// No description provided for @clearAnnotations.
  ///
  /// In en, this message translates to:
  /// **'Clear Annotations'**
  String get clearAnnotations;

  /// No description provided for @bookmarkPosition.
  ///
  /// In en, this message translates to:
  /// **'Bookmark Position'**
  String get bookmarkPosition;

  /// No description provided for @positionBookmarked.
  ///
  /// In en, this message translates to:
  /// **'Position bookmarked'**
  String get positionBookmarked;

  /// No description provided for @askCoach.
  ///
  /// In en, this message translates to:
  /// **'Ask Coach'**
  String get askCoach;

  /// No description provided for @drills.
  ///
  /// In en, this message translates to:
  /// **'Drills'**
  String get drills;

  /// No description provided for @engineVsEngine.
  ///
  /// In en, this message translates to:
  /// **'Engine vs Engine'**
  String get engineVsEngine;

  /// No description provided for @stats.
  ///
  /// In en, this message translates to:
  /// **'Stats'**
  String get stats;

  /// No description provided for @statsAndAchievements.
  ///
  /// In en, this message translates to:
  /// **'Stats & Achievements'**
  String get statsAndAchievements;

  /// No description provided for @achievements.
  ///
  /// In en, this message translates to:
  /// **'Achievements'**
  String get achievements;

  /// No description provided for @games.
  ///
  /// In en, this message translates to:
  /// **'Games'**
  String get games;

  /// No description provided for @wins.
  ///
  /// In en, this message translates to:
  /// **'Wins'**
  String get wins;

  /// No description provided for @badges.
  ///
  /// In en, this message translates to:
  /// **'Badges'**
  String get badges;

  /// No description provided for @engineManager.
  ///
  /// In en, this message translates to:
  /// **'Engine Manager'**
  String get engineManager;

  /// No description provided for @engineManagerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Engine Manager — Add Custom UCI Engines'**
  String get engineManagerSubtitle;

  /// No description provided for @addEngine.
  ///
  /// In en, this message translates to:
  /// **'Add Engine'**
  String get addEngine;

  /// No description provided for @addUciEngine.
  ///
  /// In en, this message translates to:
  /// **'Add UCI Engine'**
  String get addUciEngine;

  /// No description provided for @engineBinaryPath.
  ///
  /// In en, this message translates to:
  /// **'Engine binary path'**
  String get engineBinaryPath;

  /// No description provided for @displayName.
  ///
  /// In en, this message translates to:
  /// **'Display name (optional)'**
  String get displayName;

  /// No description provided for @leaveBlankAutoDetect.
  ///
  /// In en, this message translates to:
  /// **'Leave blank to auto-detect'**
  String get leaveBlankAutoDetect;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @configure.
  ///
  /// In en, this message translates to:
  /// **'Configure'**
  String get configure;

  /// No description provided for @probingEngine.
  ///
  /// In en, this message translates to:
  /// **'Probing engine...'**
  String get probingEngine;

  /// No description provided for @engineAdded.
  ///
  /// In en, this message translates to:
  /// **'Added: {name}'**
  String engineAdded(String name);

  /// No description provided for @engineInitFailed.
  ///
  /// In en, this message translates to:
  /// **'Engine failed to initialize: {error}'**
  String engineInitFailed(String error);

  /// No description provided for @loadingEngineOptions.
  ///
  /// In en, this message translates to:
  /// **'Loading engine options...'**
  String get loadingEngineOptions;

  /// No description provided for @noCustomEngines.
  ///
  /// In en, this message translates to:
  /// **'No custom engines added'**
  String get noCustomEngines;

  /// No description provided for @noCustomEnginesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Add any UCI-compatible chess engine\nby providing the path to its binary.'**
  String get noCustomEnginesSubtitle;

  /// No description provided for @removeEngine.
  ///
  /// In en, this message translates to:
  /// **'Remove Engine?'**
  String get removeEngine;

  /// No description provided for @removeEngineConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove "{name}" from your engine list?'**
  String removeEngineConfirm(String name);

  /// No description provided for @noConfigurableOptions.
  ///
  /// In en, this message translates to:
  /// **'No configurable options'**
  String get noConfigurableOptions;

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// No description provided for @run.
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get run;

  /// No description provided for @rangeMinMax.
  ///
  /// In en, this message translates to:
  /// **'Range: {min} – {max}'**
  String rangeMinMax(String min, String max);

  /// No description provided for @positionEditor.
  ///
  /// In en, this message translates to:
  /// **'Position Editor'**
  String get positionEditor;

  /// No description provided for @startingPosition.
  ///
  /// In en, this message translates to:
  /// **'Starting position'**
  String get startingPosition;

  /// No description provided for @clearBoard.
  ///
  /// In en, this message translates to:
  /// **'Clear board'**
  String get clearBoard;

  /// No description provided for @sideToMove.
  ///
  /// In en, this message translates to:
  /// **'Side to move:'**
  String get sideToMove;

  /// No description provided for @castling.
  ///
  /// In en, this message translates to:
  /// **'Castling:'**
  String get castling;

  /// No description provided for @copyFen.
  ///
  /// In en, this message translates to:
  /// **'Copy FEN'**
  String get copyFen;

  /// No description provided for @fenCopied.
  ///
  /// In en, this message translates to:
  /// **'FEN copied'**
  String get fenCopied;

  /// No description provided for @loadPosition.
  ///
  /// In en, this message translates to:
  /// **'Load Position'**
  String get loadPosition;

  /// No description provided for @invalidFen.
  ///
  /// In en, this message translates to:
  /// **'Invalid FEN string'**
  String get invalidFen;

  /// No description provided for @positionLoaded.
  ///
  /// In en, this message translates to:
  /// **'Position loaded from FEN'**
  String get positionLoaded;

  /// No description provided for @customPositionLoaded.
  ///
  /// In en, this message translates to:
  /// **'Custom position loaded'**
  String get customPositionLoaded;

  /// No description provided for @pawnsOnEdgeRank.
  ///
  /// In en, this message translates to:
  /// **'Pawns cannot be on the first or last rank'**
  String get pawnsOnEdgeRank;

  /// No description provided for @needOneWhiteKing.
  ///
  /// In en, this message translates to:
  /// **'White must have exactly one king'**
  String get needOneWhiteKing;

  /// No description provided for @needOneBlackKing.
  ///
  /// In en, this message translates to:
  /// **'Black must have exactly one king'**
  String get needOneBlackKing;

  /// No description provided for @pasteFenHint.
  ///
  /// In en, this message translates to:
  /// **'Paste FEN string...'**
  String get pasteFenHint;

  /// No description provided for @pasteFromClipboard.
  ///
  /// In en, this message translates to:
  /// **'Paste from clipboard'**
  String get pasteFromClipboard;

  /// No description provided for @load.
  ///
  /// In en, this message translates to:
  /// **'Load'**
  String get load;

  /// No description provided for @databaseStatistics.
  ///
  /// In en, this message translates to:
  /// **'Database Statistics'**
  String get databaseStatistics;

  /// No description provided for @nGames.
  ///
  /// In en, this message translates to:
  /// **'{count} games'**
  String nGames(String count);

  /// No description provided for @results.
  ///
  /// In en, this message translates to:
  /// **'Results'**
  String get results;

  /// No description provided for @whiteWins.
  ///
  /// In en, this message translates to:
  /// **'White wins'**
  String get whiteWins;

  /// No description provided for @blackWins.
  ///
  /// In en, this message translates to:
  /// **'Black wins'**
  String get blackWins;

  /// No description provided for @draws.
  ///
  /// In en, this message translates to:
  /// **'Draws'**
  String get draws;

  /// No description provided for @topOpenings.
  ///
  /// In en, this message translates to:
  /// **'Top Openings (ECO)'**
  String get topOpenings;

  /// No description provided for @mostActivePlayers.
  ///
  /// In en, this message translates to:
  /// **'Most Active Players'**
  String get mostActivePlayers;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @noDatabaseLoaded.
  ///
  /// In en, this message translates to:
  /// **'No database loaded'**
  String get noDatabaseLoaded;

  /// No description provided for @noDatabaseSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Copy a PGN file with multiple games\nto your clipboard, then tap the paste icon.'**
  String get noDatabaseSubtitle;

  /// No description provided for @searchByPlayer.
  ///
  /// In en, this message translates to:
  /// **'Search by player...'**
  String get searchByPlayer;

  /// No description provided for @result.
  ///
  /// In en, this message translates to:
  /// **'Result'**
  String get result;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @draw.
  ///
  /// In en, this message translates to:
  /// **'Draw'**
  String get draw;

  /// No description provided for @noGamesFound.
  ///
  /// In en, this message translates to:
  /// **'No games found in PGN'**
  String get noGamesFound;

  /// No description provided for @noPgnData.
  ///
  /// In en, this message translates to:
  /// **'No PGN data in clipboard'**
  String get noPgnData;

  /// No description provided for @gameLoadedFromDb.
  ///
  /// In en, this message translates to:
  /// **'Game loaded from database'**
  String get gameLoadedFromDb;

  /// No description provided for @match.
  ///
  /// In en, this message translates to:
  /// **'Match'**
  String get match;

  /// No description provided for @tournament.
  ///
  /// In en, this message translates to:
  /// **'Tournament'**
  String get tournament;

  /// No description provided for @selectTwoDifferent.
  ///
  /// In en, this message translates to:
  /// **'Select two different engines'**
  String get selectTwoDifferent;

  /// No description provided for @selectAtLeast3.
  ///
  /// In en, this message translates to:
  /// **'Select at least 3 engines'**
  String get selectAtLeast3;

  /// No description provided for @selectEngines.
  ///
  /// In en, this message translates to:
  /// **'Select engines ({count} selected, min 3):'**
  String selectEngines(String count);

  /// No description provided for @depth.
  ///
  /// In en, this message translates to:
  /// **'Depth'**
  String get depth;

  /// No description provided for @startMatch.
  ///
  /// In en, this message translates to:
  /// **'Start Match'**
  String get startMatch;

  /// No description provided for @startTournament.
  ///
  /// In en, this message translates to:
  /// **'Start Tournament'**
  String get startTournament;

  /// No description provided for @stopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get stopped;

  /// No description provided for @vs.
  ///
  /// In en, this message translates to:
  /// **'vs'**
  String get vs;

  /// No description provided for @multiEngineAnalysis.
  ///
  /// In en, this message translates to:
  /// **'Multi-Engine Analysis'**
  String get multiEngineAnalysis;

  /// No description provided for @multiEngine.
  ///
  /// In en, this message translates to:
  /// **'Multi-Engine'**
  String get multiEngine;

  /// No description provided for @stopMultiEngine.
  ///
  /// In en, this message translates to:
  /// **'Stop multi-engine'**
  String get stopMultiEngine;

  /// No description provided for @selectEnginesToCompare.
  ///
  /// In en, this message translates to:
  /// **'Select engines to compare:'**
  String get selectEnginesToCompare;

  /// No description provided for @currentOpponent.
  ///
  /// In en, this message translates to:
  /// **'(current opponent)'**
  String get currentOpponent;

  /// No description provided for @start.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get start;

  /// No description provided for @multiEngineFailed.
  ///
  /// In en, this message translates to:
  /// **'Multi-engine failed: {error}'**
  String multiEngineFailed(String error);

  /// No description provided for @reAnalyze.
  ///
  /// In en, this message translates to:
  /// **'Re-analyze'**
  String get reAnalyze;

  /// No description provided for @tapRefreshToAnalyze.
  ///
  /// In en, this message translates to:
  /// **'Tap refresh to analyze'**
  String get tapRefreshToAnalyze;

  /// No description provided for @engineLoading.
  ///
  /// In en, this message translates to:
  /// **'Engine loading...'**
  String get engineLoading;

  /// No description provided for @analysis.
  ///
  /// In en, this message translates to:
  /// **'Analysis'**
  String get analysis;

  /// No description provided for @engineNotReady.
  ///
  /// In en, this message translates to:
  /// **'Engine not ready'**
  String get engineNotReady;

  /// No description provided for @positionRestored.
  ///
  /// In en, this message translates to:
  /// **'Position restored'**
  String get positionRestored;

  /// No description provided for @resignQuestion.
  ///
  /// In en, this message translates to:
  /// **'Resign?'**
  String get resignQuestion;

  /// No description provided for @dailyLogin.
  ///
  /// In en, this message translates to:
  /// **'Daily login: +{xp} XP (streak: {streak})'**
  String dailyLogin(String xp, String streak);

  /// No description provided for @levelUp.
  ///
  /// In en, this message translates to:
  /// **'Level Up!'**
  String get levelUp;

  /// No description provided for @youReached.
  ///
  /// In en, this message translates to:
  /// **'You reached {level}!'**
  String youReached(String level);

  /// No description provided for @continueButton.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueButton;

  /// No description provided for @couldNotCaptureBoard.
  ///
  /// In en, this message translates to:
  /// **'Could not capture board'**
  String get couldNotCaptureBoard;

  /// No description provided for @boardCaptured.
  ///
  /// In en, this message translates to:
  /// **'Board captured ({size} KB)'**
  String boardCaptured(String size);

  /// No description provided for @screenshotFailed.
  ///
  /// In en, this message translates to:
  /// **'Screenshot failed: {error}'**
  String screenshotFailed(String error);

  /// No description provided for @illegalMove.
  ///
  /// In en, this message translates to:
  /// **'Illegal Move!'**
  String get illegalMove;

  /// No description provided for @premove.
  ///
  /// In en, this message translates to:
  /// **'Premove: {move}'**
  String premove(String move);

  /// No description provided for @premoveIllegal.
  ///
  /// In en, this message translates to:
  /// **'Premove illegal — your turn'**
  String get premoveIllegal;

  /// No description provided for @drillComplete.
  ///
  /// In en, this message translates to:
  /// **'Drill Complete!'**
  String get drillComplete;

  /// No description provided for @correctOnFirstTry.
  ///
  /// In en, this message translates to:
  /// **'{correct} / {total} correct on first try'**
  String correctOnFirstTry(String correct, String total);

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @stepOf.
  ///
  /// In en, this message translates to:
  /// **'Step {current} of {total}'**
  String stepOf(String current, String total);

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @finish.
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get finish;

  /// No description provided for @findBestMove.
  ///
  /// In en, this message translates to:
  /// **'Find the best move.'**
  String get findBestMove;

  /// No description provided for @correct.
  ///
  /// In en, this message translates to:
  /// **'Correct!'**
  String get correct;

  /// No description provided for @notQuiteTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Not quite — try again!'**
  String get notQuiteTryAgain;

  /// No description provided for @aiCoach.
  ///
  /// In en, this message translates to:
  /// **'AI Coach'**
  String get aiCoach;

  /// No description provided for @privacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get privacy;

  /// No description provided for @privacyNotice.
  ///
  /// In en, this message translates to:
  /// **'Your API key is stored locally on your device only. Game data (FEN/PGN) is sent directly to your chosen AI provider. CrispChess does not store, log, or transmit any data to its own servers. You can delete your API key at any time.'**
  String get privacyNotice;

  /// No description provided for @enterApiKey.
  ///
  /// In en, this message translates to:
  /// **'Enter your API key to get started:'**
  String get enterApiKey;

  /// No description provided for @keyConfigured.
  ///
  /// In en, this message translates to:
  /// **'{provider} key configured'**
  String keyConfigured(String provider);

  /// No description provided for @removeKey.
  ///
  /// In en, this message translates to:
  /// **'Remove key'**
  String get removeKey;

  /// No description provided for @noMistakesYet.
  ///
  /// In en, this message translates to:
  /// **'No mistakes tracked yet!'**
  String get noMistakesYet;

  /// No description provided for @noMistakesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Play games with analysis enabled to track blunders.'**
  String get noMistakesSubtitle;

  /// No description provided for @clearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get clearAll;

  /// No description provided for @unknownMove.
  ///
  /// In en, this message translates to:
  /// **'Unknown move'**
  String get unknownMove;

  /// No description provided for @serviceProvider.
  ///
  /// In en, this message translates to:
  /// **'Service Provider'**
  String get serviceProvider;

  /// No description provided for @license.
  ///
  /// In en, this message translates to:
  /// **'License'**
  String get license;

  /// No description provided for @chessEngines.
  ///
  /// In en, this message translates to:
  /// **'Chess Engines'**
  String get chessEngines;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// No description provided for @disclaimer.
  ///
  /// In en, this message translates to:
  /// **'Disclaimer'**
  String get disclaimer;

  /// No description provided for @sourceCode.
  ///
  /// In en, this message translates to:
  /// **'Source Code'**
  String get sourceCode;

  /// No description provided for @urlCopied.
  ///
  /// In en, this message translates to:
  /// **'URL copied to clipboard'**
  String get urlCopied;

  /// No description provided for @contributionsWelcome.
  ///
  /// In en, this message translates to:
  /// **'Contributions welcome. Open an issue first for major changes.'**
  String get contributionsWelcome;

  /// No description provided for @openSourceLicenses.
  ///
  /// In en, this message translates to:
  /// **'Open Source Licenses'**
  String get openSourceLicenses;

  /// No description provided for @hintsAndAnalysis.
  ///
  /// In en, this message translates to:
  /// **'Hints & Analysis'**
  String get hintsAndAnalysis;

  /// No description provided for @maia3Model.
  ///
  /// In en, this message translates to:
  /// **'Maia3 Model'**
  String get maia3Model;

  /// No description provided for @stockfishVersion.
  ///
  /// In en, this message translates to:
  /// **'Stockfish Version'**
  String get stockfishVersion;

  /// No description provided for @maiaWeight.
  ///
  /// In en, this message translates to:
  /// **'Maia Weight (ELO level)'**
  String get maiaWeight;

  /// No description provided for @gameMode.
  ///
  /// In en, this message translates to:
  /// **'Game Mode'**
  String get gameMode;

  /// No description provided for @standard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get standard;

  /// No description provided for @kingOfTheHill.
  ///
  /// In en, this message translates to:
  /// **'King of the Hill'**
  String get kingOfTheHill;

  /// No description provided for @threeCheck.
  ///
  /// In en, this message translates to:
  /// **'Three-Check'**
  String get threeCheck;

  /// No description provided for @customTimeControl.
  ///
  /// In en, this message translates to:
  /// **'Custom...'**
  String get customTimeControl;

  /// No description provided for @boardColorThemeLabel.
  ///
  /// In en, this message translates to:
  /// **'Board Color'**
  String get boardColorThemeLabel;

  /// No description provided for @notationStyleLabel.
  ///
  /// In en, this message translates to:
  /// **'Notation'**
  String get notationStyleLabel;

  /// No description provided for @blindfoldMode.
  ///
  /// In en, this message translates to:
  /// **'Blindfold Mode'**
  String get blindfoldMode;

  /// No description provided for @blindfoldModeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Hide pieces — play by memory'**
  String get blindfoldModeSubtitle;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
