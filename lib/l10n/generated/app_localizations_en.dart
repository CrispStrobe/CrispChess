// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'CrispChess';

  @override
  String get yourTurn => 'Your turn';

  @override
  String get whiteToMove => 'White to move';

  @override
  String get blackToMove => 'Black to move';

  @override
  String get thinking => 'Thinking...';

  @override
  String get engineError => 'Engine error';

  @override
  String loading(Object engineName) {
    return 'Loading $engineName...';
  }

  @override
  String get downloading => 'Downloading & initializing...';

  @override
  String engineReady(Object engineName) {
    return '$engineName ready';
  }

  @override
  String engineThinking(Object engineName) {
    return '$engineName is thinking...';
  }

  @override
  String get newGame => 'New Game';

  @override
  String get newGameConfirm => 'Current game will be lost.';

  @override
  String get settings => 'Settings';

  @override
  String get about => 'About';

  @override
  String get aboutCrispChess => 'About CrispChess';

  @override
  String get puzzles => 'Puzzles';

  @override
  String get flipBoard => 'Flip Board';

  @override
  String get copyPgn => 'Copy PGN';

  @override
  String get pastePgn => 'Paste PGN';

  @override
  String get loadFen => 'Load FEN';

  @override
  String get setupPosition => 'Setup Position';

  @override
  String get pgnDatabase => 'PGN Database';

  @override
  String get offerDraw => 'Offer Draw';

  @override
  String get resign => 'Resign';

  @override
  String resignConfirm(Object engineName) {
    return '$engineName wins by resignation.';
  }

  @override
  String drawDeclined(Object engineName) {
    return '$engineName declines the draw offer.';
  }

  @override
  String get drawAgreed => 'Draw agreed';

  @override
  String get youResigned => 'You resigned';

  @override
  String get gameResumed => 'Game resumed';

  @override
  String get resumeGame => 'Resume game?';

  @override
  String savedGameMoves(Object count) {
    return 'You have a saved game ($count moves).';
  }

  @override
  String get discard => 'Discard';

  @override
  String get resume => 'Resume';

  @override
  String get cancel => 'Cancel';

  @override
  String get review => 'Review';

  @override
  String get undo => 'Undo';

  @override
  String get redo => 'Redo';

  @override
  String get hint => 'Hint';

  @override
  String get analyze => 'Analyze';

  @override
  String get abort => 'Abort';

  @override
  String get playAsWhite => 'White';

  @override
  String get playAsBlack => 'Black';

  @override
  String get playAsRandom => 'Random';

  @override
  String get twoPlayer => 'Two Player (local)';

  @override
  String get passAndPlay => 'Pass and play';

  @override
  String get playAs => 'Play as';

  @override
  String get chessEngine => 'Chess Engine';

  @override
  String get opponentStrength => 'Opponent Strength';

  @override
  String get hintDepth => 'Hint Depth';

  @override
  String analysisDepth(Object depth) {
    return 'Analysis Depth: $depth';
  }

  @override
  String get hintEngine => 'Hint Engine';

  @override
  String get sameAsOpponent => 'Same as opponent';

  @override
  String get game => 'Game';

  @override
  String get showValidMoves => 'Show Valid Moves';

  @override
  String get showValidMovesSubtitle =>
      'Highlight legal moves when selecting a piece';

  @override
  String get allowUndo => 'Allow Undo';

  @override
  String get allowUndoSubtitle => 'Disable for discipline mode';

  @override
  String get solidBlackPieces => 'Solid Black Pieces';

  @override
  String get solidBlackPiecesSubtitle =>
      'Render black pieces as solid black instead of grey gradient';

  @override
  String get animationSpeed => 'Animation Speed';

  @override
  String get instant => 'Instant';

  @override
  String get fast => 'Fast';

  @override
  String get normal => 'Normal';

  @override
  String get slow => 'Slow';

  @override
  String get timeControl => 'Time Control';

  @override
  String get playAsBlackSetting => 'Play as Black';

  @override
  String get playAsBlackSubtitle => 'Engine makes the first move';

  @override
  String get pieceStyle => 'Piece Style';

  @override
  String get theme => 'Theme';

  @override
  String get language => 'Language';

  @override
  String get systemDefault => 'System Default';

  @override
  String get system => 'System';

  @override
  String get light => 'Light';

  @override
  String get darkAmoled => 'Dark (AMOLED)';

  @override
  String get resetToDefaults => 'Reset to defaults';

  @override
  String get save => 'Save';

  @override
  String get pgnCopied => 'PGN copied to clipboard';

  @override
  String get pgnLoaded => 'PGN loaded';

  @override
  String get invalidPgn => 'Invalid PGN';

  @override
  String get noPgnInClipboard => 'No PGN found in clipboard';

  @override
  String get noMovesYet => 'No moves yet';

  @override
  String get solved => 'solved';

  @override
  String get showSolution => 'Show Solution';

  @override
  String get nextPuzzle => 'Next Puzzle';

  @override
  String get skip => 'Skip';

  @override
  String wrongMove(Object remaining) {
    return 'Wrong move. Try again. ($remaining left)';
  }

  @override
  String get puzzleSolved => 'Correct! Puzzle solved.';

  @override
  String get findNextMove => 'Correct! Find the next move.';

  @override
  String get gameSummary => 'Game Summary';

  @override
  String get yourAccuracy => 'Your Accuracy';

  @override
  String get accuracy => 'Accuracy';

  @override
  String get good => 'Good';

  @override
  String get mistakes => 'Mistakes';

  @override
  String get myMistakes => 'My Mistakes';

  @override
  String get blunders => 'Blunders';

  @override
  String get evaluation => 'Evaluation';

  @override
  String get yourBestMove => 'Your Best Move';

  @override
  String get biggestMistake => 'Biggest Mistake';

  @override
  String get moves => 'Moves';

  @override
  String get tapToViewPosition => 'Tap to view position';

  @override
  String moveN(Object n) {
    return 'Move $n';
  }

  @override
  String get welcome => 'Welcome to CrispChess';

  @override
  String get welcomeSubtitle => 'Play chess against AI engines or a friend.';

  @override
  String get letsPlay => 'Let\'s play!';

  @override
  String get switchToBuiltIn => 'Switch to Built-in';

  @override
  String failedToInitialize(Object engineName) {
    return '$engineName: failed to initialize';
  }

  @override
  String get checkmate => 'Checkmate';

  @override
  String get stalemate => 'Stalemate';

  @override
  String get drawThreefold => 'Draw — threefold repetition';

  @override
  String get drawInsufficient => 'Draw — insufficient material';

  @override
  String get drawFiftyMove => 'Draw — fifty-move rule';

  @override
  String get resignation => 'Resignation';

  @override
  String get drawByAgreement => 'Draw by agreement';

  @override
  String get gameOver => 'Game Over';

  @override
  String get boardScreenshot => 'Board Screenshot';

  @override
  String get clearAnnotations => 'Clear Annotations';

  @override
  String get bookmarkPosition => 'Bookmark Position';

  @override
  String get positionBookmarked => 'Position bookmarked';

  @override
  String get askCoach => 'Ask Coach';

  @override
  String get drills => 'Drills';

  @override
  String get engineVsEngine => 'Engine vs Engine';

  @override
  String get stats => 'Stats';

  @override
  String get statsAndAchievements => 'Stats & Achievements';

  @override
  String get achievements => 'Achievements';

  @override
  String get games => 'Games';

  @override
  String get wins => 'Wins';

  @override
  String get badges => 'Badges';

  @override
  String get engineManager => 'Engine Manager';

  @override
  String get engineManagerSubtitle => 'Engine Manager — Add Custom UCI Engines';

  @override
  String get addEngine => 'Add Engine';

  @override
  String get addUciEngine => 'Add UCI Engine';

  @override
  String get engineBinaryPath => 'Engine binary path';

  @override
  String get displayName => 'Display name (optional)';

  @override
  String get leaveBlankAutoDetect => 'Leave blank to auto-detect';

  @override
  String get add => 'Add';

  @override
  String get remove => 'Remove';

  @override
  String get configure => 'Configure';

  @override
  String get probingEngine => 'Probing engine...';

  @override
  String engineAdded(Object name) {
    return 'Added: $name';
  }

  @override
  String engineInitFailed(Object error) {
    return 'Engine failed to initialize: $error';
  }

  @override
  String get loadingEngineOptions => 'Loading engine options...';

  @override
  String get noCustomEngines => 'No custom engines added';

  @override
  String get noCustomEnginesSubtitle =>
      'Add any UCI-compatible chess engine\nby providing the path to its binary.';

  @override
  String get removeEngine => 'Remove Engine?';

  @override
  String removeEngineConfirm(Object name) {
    return 'Remove \"$name\" from your engine list?';
  }

  @override
  String get noConfigurableOptions => 'No configurable options';

  @override
  String get reset => 'Reset';

  @override
  String get run => 'Run';

  @override
  String rangeMinMax(Object min, Object max) {
    return 'Range: $min – $max';
  }

  @override
  String get positionEditor => 'Position Editor';

  @override
  String get startingPosition => 'Starting position';

  @override
  String get clearBoard => 'Clear board';

  @override
  String get sideToMove => 'Side to move:';

  @override
  String get castling => 'Castling:';

  @override
  String get copyFen => 'Copy FEN';

  @override
  String get fenCopied => 'FEN copied';

  @override
  String get loadPosition => 'Load Position';

  @override
  String get invalidFen => 'Invalid FEN string';

  @override
  String get positionLoaded => 'Position loaded from FEN';

  @override
  String get customPositionLoaded => 'Custom position loaded';

  @override
  String get pawnsOnEdgeRank => 'Pawns cannot be on the first or last rank';

  @override
  String get needOneWhiteKing => 'White must have exactly one king';

  @override
  String get needOneBlackKing => 'Black must have exactly one king';

  @override
  String get pasteFenHint => 'Paste FEN string...';

  @override
  String get pasteFromClipboard => 'Paste from clipboard';

  @override
  String get load => 'Load';

  @override
  String get databaseStatistics => 'Database Statistics';

  @override
  String nGames(Object count) {
    return '$count games';
  }

  @override
  String get results => 'Results';

  @override
  String get whiteWins => 'White wins';

  @override
  String get blackWins => 'Black wins';

  @override
  String get draws => 'Draws';

  @override
  String get topOpenings => 'Top Openings (ECO)';

  @override
  String get mostActivePlayers => 'Most Active Players';

  @override
  String get close => 'Close';

  @override
  String get noDatabaseLoaded => 'No database loaded';

  @override
  String get noDatabaseSubtitle =>
      'Copy a PGN file with multiple games\nto your clipboard, then tap the paste icon.';

  @override
  String get searchByPlayer => 'Search by player...';

  @override
  String get result => 'Result';

  @override
  String get all => 'All';

  @override
  String get draw => 'Draw';

  @override
  String get noGamesFound => 'No games found in PGN';

  @override
  String get noPgnData => 'No PGN data in clipboard';

  @override
  String get gameLoadedFromDb => 'Game loaded from database';

  @override
  String get match => 'Match';

  @override
  String get tournament => 'Tournament';

  @override
  String get selectTwoDifferent => 'Select two different engines';

  @override
  String get selectAtLeast3 => 'Select at least 3 engines';

  @override
  String selectEngines(Object count) {
    return 'Select engines ($count selected, min 3):';
  }

  @override
  String get depth => 'Depth';

  @override
  String get startMatch => 'Start Match';

  @override
  String get startTournament => 'Start Tournament';

  @override
  String get stopped => 'Stopped';

  @override
  String get vs => 'vs';

  @override
  String get multiEngineAnalysis => 'Multi-Engine Analysis';

  @override
  String get multiEngine => 'Multi-Engine';

  @override
  String get stopMultiEngine => 'Stop multi-engine';

  @override
  String get selectEnginesToCompare => 'Select engines to compare:';

  @override
  String get currentOpponent => '(current opponent)';

  @override
  String get start => 'Start';

  @override
  String multiEngineFailed(Object error) {
    return 'Multi-engine failed: $error';
  }

  @override
  String get reAnalyze => 'Re-analyze';

  @override
  String get tapRefreshToAnalyze => 'Tap refresh to analyze';

  @override
  String get engineLoading => 'Engine loading...';

  @override
  String get analysis => 'Analysis';

  @override
  String get engineNotReady => 'Engine not ready';

  @override
  String get positionRestored => 'Position restored';

  @override
  String get resignQuestion => 'Resign?';

  @override
  String dailyLogin(Object xp, Object streak) {
    return 'Daily login: +$xp XP (streak: $streak)';
  }

  @override
  String get levelUp => 'Level Up!';

  @override
  String youReached(Object level) {
    return 'You reached $level!';
  }

  @override
  String get continueButton => 'Continue';

  @override
  String get couldNotCaptureBoard => 'Could not capture board';

  @override
  String boardCaptured(Object size) {
    return 'Board captured ($size KB)';
  }

  @override
  String screenshotFailed(Object error) {
    return 'Screenshot failed: $error';
  }

  @override
  String get illegalMove => 'Illegal Move!';

  @override
  String premove(Object move) {
    return 'Premove: $move';
  }

  @override
  String get premoveIllegal => 'Premove illegal — your turn';

  @override
  String get drillComplete => 'Drill Complete!';

  @override
  String correctOnFirstTry(Object correct, Object total) {
    return '$correct / $total correct on first try';
  }

  @override
  String get done => 'Done';

  @override
  String stepOf(Object current, Object total) {
    return 'Step $current of $total';
  }

  @override
  String get next => 'Next';

  @override
  String get finish => 'Finish';

  @override
  String get findBestMove => 'Find the best move.';

  @override
  String get correct => 'Correct!';

  @override
  String get notQuiteTryAgain => 'Not quite — try again!';

  @override
  String get aiCoach => 'AI Coach';

  @override
  String get privacy => 'Privacy';

  @override
  String get privacyNotice =>
      'Your API key is stored locally on your device only. Game data (FEN/PGN) is sent directly to your chosen AI provider. CrispChess does not store, log, or transmit any data to its own servers. You can delete your API key at any time.';

  @override
  String get enterApiKey => 'Enter your API key to get started:';

  @override
  String keyConfigured(Object provider) {
    return '$provider key configured';
  }

  @override
  String get removeKey => 'Remove key';

  @override
  String get noMistakesYet => 'No mistakes tracked yet!';

  @override
  String get noMistakesSubtitle =>
      'Play games with analysis enabled to track blunders.';

  @override
  String get clearAll => 'Clear all';

  @override
  String get unknownMove => 'Unknown move';

  @override
  String get serviceProvider => 'Service Provider';

  @override
  String get license => 'License';

  @override
  String get chessEngines => 'Chess Engines';

  @override
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get disclaimer => 'Disclaimer';

  @override
  String get sourceCode => 'Source Code';

  @override
  String get urlCopied => 'URL copied to clipboard';

  @override
  String get contributionsWelcome =>
      'Contributions welcome. Open an issue first for major changes.';

  @override
  String get openSourceLicenses => 'Open Source Licenses';

  @override
  String get hintsAndAnalysis => 'Hints & Analysis';

  @override
  String get maia3Model => 'Maia3 Model';

  @override
  String get stockfishVersion => 'Stockfish Version';

  @override
  String get maiaWeight => 'Maia Weight (ELO level)';

  @override
  String get gameMode => 'Game Mode';

  @override
  String get standard => 'Standard';

  @override
  String get kingOfTheHill => 'King of the Hill';

  @override
  String get threeCheck => 'Three-Check';

  @override
  String get customTimeControl => 'Custom...';

  @override
  String get boardColorThemeLabel => 'Board Color';

  @override
  String get notationStyleLabel => 'Notation';

  @override
  String get blindfoldMode => 'Blindfold Mode';

  @override
  String get blindfoldModeSubtitle => 'Hide pieces — play by memory';

  @override
  String get importExport => 'Import / Export';

  @override
  String get boardToolsMenu => 'Board Tools';

  @override
  String get learnMenu => 'Learn';

  @override
  String get progressMenu => 'Progress';

  @override
  String get openingExplorer => 'Opening Explorer';

  @override
  String get coordinateTrainer => 'Coordinate Trainer';

  @override
  String get gameHistory => 'Game History';
}
