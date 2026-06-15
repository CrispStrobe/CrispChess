import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([super.locale = 'de']);

  @override
  String get appTitle => 'CrispChess';

  @override
  String get yourTurn => 'Du bist dran';

  @override
  String get whiteToMove => 'Weiß am Zug';

  @override
  String get blackToMove => 'Schwarz am Zug';

  @override
  String get thinking => 'Denkt nach...';

  @override
  String get engineError => 'Engine-Fehler';

  @override
  String loading(String engineName) {
    return 'Lade $engineName...';
  }

  @override
  String get downloading => 'Wird heruntergeladen...';

  @override
  String engineReady(String engineName) {
    return '$engineName bereit';
  }

  @override
  String engineThinking(String engineName) {
    return '$engineName denkt nach...';
  }

  @override
  String get newGame => 'Neue Partie';

  @override
  String get newGameConfirm => 'Die aktuelle Partie geht verloren.';

  @override
  String get settings => 'Einstellungen';

  @override
  String get about => 'Über';

  @override
  String get aboutCrispChess => 'Über CrispChess';

  @override
  String get puzzles => 'Aufgaben';

  @override
  String get flipBoard => 'Brett drehen';

  @override
  String get copyPgn => 'PGN kopieren';

  @override
  String get pastePgn => 'PGN einfügen';

  @override
  String get loadFen => 'FEN laden';

  @override
  String get setupPosition => 'Stellung aufbauen';

  @override
  String get pgnDatabase => 'PGN-Datenbank';

  @override
  String get offerDraw => 'Remis anbieten';

  @override
  String get resign => 'Aufgeben';

  @override
  String resignConfirm(String engineName) {
    return '$engineName gewinnt durch Aufgabe.';
  }

  @override
  String drawDeclined(String engineName) {
    return '$engineName lehnt das Remisangebot ab.';
  }

  @override
  String get drawAgreed => 'Remis vereinbart';

  @override
  String get youResigned => 'Du hast aufgegeben';

  @override
  String get gameResumed => 'Partie fortgesetzt';

  @override
  String get resumeGame => 'Partie fortsetzen?';

  @override
  String savedGameMoves(String count) {
    return 'Du hast eine gespeicherte Partie ($count Züge).';
  }

  @override
  String get discard => 'Verwerfen';

  @override
  String get resume => 'Fortsetzen';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get review => 'Analyse';

  @override
  String get undo => 'Rückgängig';

  @override
  String get redo => 'Wiederholen';

  @override
  String get hint => 'Hinweis';

  @override
  String get analyze => 'Analysieren';

  @override
  String get abort => 'Abbrechen';

  @override
  String get playAsWhite => 'Weiß';

  @override
  String get playAsBlack => 'Schwarz';

  @override
  String get playAsRandom => 'Zufall';

  @override
  String get twoPlayer => 'Zwei Spieler (lokal)';

  @override
  String get passAndPlay => 'Abwechselnd spielen';

  @override
  String get playAs => 'Spielen als';

  @override
  String get chessEngine => 'Schach-Engine';

  @override
  String get opponentStrength => 'Gegnerstärke';

  @override
  String get hintDepth => 'Analysetiefe';

  @override
  String analysisDepth(String depth) {
    return 'Analysetiefe: $depth';
  }

  @override
  String get hintEngine => 'Hinweis-Engine';

  @override
  String get sameAsOpponent => 'Wie Gegner';

  @override
  String get game => 'Partie';

  @override
  String get showValidMoves => 'Gültige Züge anzeigen';

  @override
  String get showValidMovesSubtitle => 'Legale Züge hervorheben bei Figurenauswahl';

  @override
  String get allowUndo => 'Rückgängig erlauben';

  @override
  String get allowUndoSubtitle => 'Für Disziplin deaktivieren';

  @override
  String get solidBlackPieces => 'Schwarze Figuren einfarbig';

  @override
  String get solidBlackPiecesSubtitle => 'Schwarze Figuren als reines Schwarz statt grauem Farbverlauf';

  @override
  String get animationSpeed => 'Animationsgeschwindigkeit';

  @override
  String get instant => 'Sofort';

  @override
  String get fast => 'Schnell';

  @override
  String get normal => 'Normal';

  @override
  String get slow => 'Langsam';

  @override
  String get timeControl => 'Zeitkontrolle';

  @override
  String get playAsBlackSetting => 'Als Schwarz spielen';

  @override
  String get playAsBlackSubtitle => 'Engine macht den ersten Zug';

  @override
  String get pieceStyle => 'Figurenstil';

  @override
  String get theme => 'Design';

  @override
  String get language => 'Sprache';

  @override
  String get systemDefault => 'Systemstandard';

  @override
  String get system => 'System';

  @override
  String get light => 'Hell';

  @override
  String get darkAmoled => 'Dunkel (AMOLED)';

  @override
  String get resetToDefaults => 'Auf Standard zurücksetzen';

  @override
  String get save => 'Speichern';

  @override
  String get pgnCopied => 'PGN in Zwischenablage kopiert';

  @override
  String get pgnLoaded => 'PGN geladen';

  @override
  String get invalidPgn => 'Ungültiges PGN';

  @override
  String get noPgnInClipboard => 'Kein PGN in der Zwischenablage';

  @override
  String get noMovesYet => 'Noch keine Züge';

  @override
  String get solved => 'gelöst';

  @override
  String get showSolution => 'Lösung zeigen';

  @override
  String get nextPuzzle => 'Nächste Aufgabe';

  @override
  String get skip => 'Überspringen';

  @override
  String wrongMove(String remaining) {
    return 'Falscher Zug. Nochmal versuchen. ($remaining übrig)';
  }

  @override
  String get puzzleSolved => 'Richtig! Aufgabe gelöst.';

  @override
  String get findNextMove => 'Richtig! Finde den nächsten Zug.';

  @override
  String get gameSummary => 'Partieübersicht';

  @override
  String get yourAccuracy => 'Deine Genauigkeit';

  @override
  String get accuracy => 'Genauigkeit';

  @override
  String get good => 'Gut';

  @override
  String get mistakes => 'Fehler';

  @override
  String get myMistakes => 'Meine Fehler';

  @override
  String get blunders => 'Patzer';

  @override
  String get evaluation => 'Bewertung';

  @override
  String get yourBestMove => 'Dein bester Zug';

  @override
  String get biggestMistake => 'Größter Fehler';

  @override
  String get moves => 'Züge';

  @override
  String get tapToViewPosition => 'Tippe um Stellung zu sehen';

  @override
  String moveN(String n) {
    return 'Zug $n';
  }

  @override
  String get welcome => 'Willkommen bei CrispChess';

  @override
  String get welcomeSubtitle => 'Spiele Schach gegen KI-Engines oder einen Freund.';

  @override
  String get letsPlay => 'Los geht\'s!';

  @override
  String get switchToBuiltIn => 'Zu Built-in wechseln';

  @override
  String failedToInitialize(String engineName) {
    return '$engineName: Initialisierung fehlgeschlagen';
  }

  @override
  String get checkmate => 'Schachmatt';

  @override
  String get stalemate => 'Patt';

  @override
  String get drawThreefold => 'Remis — dreifache Stellungswiederholung';

  @override
  String get drawInsufficient => 'Remis — ungenügendes Material';

  @override
  String get drawFiftyMove => 'Remis — 50-Züge-Regel';

  @override
  String get resignation => 'Aufgabe';

  @override
  String get drawByAgreement => 'Remis durch Vereinbarung';

  @override
  String get gameOver => 'Partie beendet';

  @override
  String get boardScreenshot => 'Brett-Screenshot';

  @override
  String get clearAnnotations => 'Markierungen löschen';

  @override
  String get bookmarkPosition => 'Stellung merken';

  @override
  String get positionBookmarked => 'Stellung gespeichert';

  @override
  String get askCoach => 'Coach fragen';

  @override
  String get drills => 'Übungen';

  @override
  String get engineVsEngine => 'Engine vs Engine';

  @override
  String get stats => 'Statistik';

  @override
  String get statsAndAchievements => 'Statistik & Erfolge';

  @override
  String get achievements => 'Erfolge';

  @override
  String get games => 'Partien';

  @override
  String get wins => 'Siege';

  @override
  String get badges => 'Abzeichen';

  @override
  String get engineManager => 'Engine-Verwaltung';

  @override
  String get engineManagerSubtitle => 'Engine-Verwaltung — UCI-Engines hinzufügen';

  @override
  String get addEngine => 'Engine hinzufügen';

  @override
  String get addUciEngine => 'UCI-Engine hinzufügen';

  @override
  String get engineBinaryPath => 'Engine-Dateipfad';

  @override
  String get displayName => 'Anzeigename (optional)';

  @override
  String get leaveBlankAutoDetect => 'Leer lassen für Autoerkennung';

  @override
  String get add => 'Hinzufügen';

  @override
  String get remove => 'Entfernen';

  @override
  String get configure => 'Konfigurieren';

  @override
  String get probingEngine => 'Engine wird geprüft...';

  @override
  String engineAdded(String name) {
    return 'Hinzugefügt: $name';
  }

  @override
  String engineInitFailed(String error) {
    return 'Engine-Initialisierung fehlgeschlagen: $error';
  }

  @override
  String get loadingEngineOptions => 'Engine-Optionen werden geladen...';

  @override
  String get noCustomEngines => 'Keine eigenen Engines';

  @override
  String get noCustomEnginesSubtitle => 'Füge eine UCI-kompatible Schach-Engine\nüber den Dateipfad hinzu.';

  @override
  String get removeEngine => 'Engine entfernen?';

  @override
  String removeEngineConfirm(String name) {
    return '"$name" aus der Engine-Liste entfernen?';
  }

  @override
  String get noConfigurableOptions => 'Keine konfigurierbaren Optionen';

  @override
  String get reset => 'Zurücksetzen';

  @override
  String get run => 'Ausführen';

  @override
  String rangeMinMax(String min, String max) {
    return 'Bereich: $min – $max';
  }

  @override
  String get positionEditor => 'Stellungseditor';

  @override
  String get startingPosition => 'Anfangsstellung';

  @override
  String get clearBoard => 'Brett leeren';

  @override
  String get sideToMove => 'Am Zug:';

  @override
  String get castling => 'Rochade:';

  @override
  String get copyFen => 'FEN kopieren';

  @override
  String get fenCopied => 'FEN kopiert';

  @override
  String get loadPosition => 'Stellung laden';

  @override
  String get invalidFen => 'Ungültiger FEN-String';

  @override
  String get positionLoaded => 'Stellung aus FEN geladen';

  @override
  String get customPositionLoaded => 'Eigene Stellung geladen';

  @override
  String get pawnsOnEdgeRank => 'Bauern können nicht auf der ersten oder letzten Reihe stehen';

  @override
  String get needOneWhiteKing => 'Weiß muss genau einen König haben';

  @override
  String get needOneBlackKing => 'Schwarz muss genau einen König haben';

  @override
  String get pasteFenHint => 'FEN-String einfügen...';

  @override
  String get pasteFromClipboard => 'Aus Zwischenablage einfügen';

  @override
  String get load => 'Laden';

  @override
  String get databaseStatistics => 'Datenbankstatistik';

  @override
  String nGames(String count) {
    return '$count Partien';
  }

  @override
  String get results => 'Ergebnisse';

  @override
  String get whiteWins => 'Weiß gewinnt';

  @override
  String get blackWins => 'Schwarz gewinnt';

  @override
  String get draws => 'Remis';

  @override
  String get topOpenings => 'Häufigste Eröffnungen (ECO)';

  @override
  String get mostActivePlayers => 'Aktivste Spieler';

  @override
  String get close => 'Schließen';

  @override
  String get noDatabaseLoaded => 'Keine Datenbank geladen';

  @override
  String get noDatabaseSubtitle => 'Kopiere eine PGN-Datei mit mehreren Partien\nin die Zwischenablage, dann tippe auf Einfügen.';

  @override
  String get searchByPlayer => 'Nach Spieler suchen...';

  @override
  String get result => 'Ergebnis';

  @override
  String get all => 'Alle';

  @override
  String get draw => 'Remis';

  @override
  String get noGamesFound => 'Keine Partien im PGN gefunden';

  @override
  String get noPgnData => 'Keine PGN-Daten in der Zwischenablage';

  @override
  String get gameLoadedFromDb => 'Partie aus Datenbank geladen';

  @override
  String get match => 'Duell';

  @override
  String get tournament => 'Turnier';

  @override
  String get selectTwoDifferent => 'Wähle zwei verschiedene Engines';

  @override
  String get selectAtLeast3 => 'Mindestens 3 Engines auswählen';

  @override
  String selectEngines(String count) {
    return 'Engines auswählen ($count gewählt, min. 3):';
  }

  @override
  String get depth => 'Tiefe';

  @override
  String get startMatch => 'Duell starten';

  @override
  String get startTournament => 'Turnier starten';

  @override
  String get stopped => 'Gestoppt';

  @override
  String get vs => 'gegen';

  @override
  String get multiEngineAnalysis => 'Multi-Engine-Analyse';

  @override
  String get multiEngine => 'Multi-Engine';

  @override
  String get stopMultiEngine => 'Multi-Engine stoppen';

  @override
  String get selectEnginesToCompare => 'Engines zum Vergleichen auswählen:';

  @override
  String get currentOpponent => '(aktueller Gegner)';

  @override
  String get start => 'Start';

  @override
  String multiEngineFailed(String error) {
    return 'Multi-Engine fehlgeschlagen: $error';
  }

  @override
  String get reAnalyze => 'Neu analysieren';

  @override
  String get tapRefreshToAnalyze => 'Tippe auf Aktualisieren';

  @override
  String get engineLoading => 'Engine lädt...';

  @override
  String get analysis => 'Analyse';

  @override
  String get engineNotReady => 'Engine nicht bereit';

  @override
  String get positionRestored => 'Stellung wiederhergestellt';

  @override
  String get resignQuestion => 'Aufgeben?';

  @override
  String dailyLogin(String xp, String streak) {
    return 'Täglicher Login: +$xp XP (Serie: $streak)';
  }

  @override
  String get levelUp => 'Aufstieg!';

  @override
  String youReached(String level) {
    return 'Du hast $level erreicht!';
  }

  @override
  String get continueButton => 'Weiter';

  @override
  String get couldNotCaptureBoard => 'Brett konnte nicht erfasst werden';

  @override
  String boardCaptured(String size) {
    return 'Brett erfasst ($size KB)';
  }

  @override
  String screenshotFailed(String error) {
    return 'Screenshot fehlgeschlagen: $error';
  }

  @override
  String get illegalMove => 'Ungültiger Zug!';

  @override
  String premove(String move) {
    return 'Vorzug: $move';
  }

  @override
  String get premoveIllegal => 'Vorzug ungültig — du bist dran';

  @override
  String get drillComplete => 'Übung abgeschlossen!';

  @override
  String correctOnFirstTry(String correct, String total) {
    return '$correct / $total beim ersten Versuch richtig';
  }

  @override
  String get done => 'Fertig';

  @override
  String stepOf(String current, String total) {
    return 'Schritt $current von $total';
  }

  @override
  String get next => 'Weiter';

  @override
  String get finish => 'Beenden';

  @override
  String get findBestMove => 'Finde den besten Zug.';

  @override
  String get correct => 'Richtig!';

  @override
  String get notQuiteTryAgain => 'Nicht ganz — versuche es nochmal!';

  @override
  String get aiCoach => 'KI-Coach';

  @override
  String get privacy => 'Datenschutz';

  @override
  String get privacyNotice => 'Dein API-Schlüssel wird nur lokal auf deinem Gerät gespeichert. Partiedaten (FEN/PGN) werden direkt an deinen KI-Anbieter gesendet. CrispChess speichert, protokolliert oder überträgt keine Daten an eigene Server. Du kannst deinen API-Schlüssel jederzeit löschen.';

  @override
  String get enterApiKey => 'Gib deinen API-Schlüssel ein:';

  @override
  String keyConfigured(String provider) {
    return '$provider-Schlüssel konfiguriert';
  }

  @override
  String get removeKey => 'Schlüssel entfernen';

  @override
  String get noMistakesYet => 'Noch keine Fehler erfasst!';

  @override
  String get noMistakesSubtitle => 'Spiele Partien mit Analyse, um Patzer zu verfolgen.';

  @override
  String get clearAll => 'Alle löschen';

  @override
  String get unknownMove => 'Unbekannter Zug';

  @override
  String get serviceProvider => 'Dienstanbieter';

  @override
  String get license => 'Lizenz';

  @override
  String get chessEngines => 'Schach-Engines';

  @override
  String get privacyPolicy => 'Datenschutzrichtlinie';

  @override
  String get disclaimer => 'Haftungsausschluss';

  @override
  String get sourceCode => 'Quellcode';

  @override
  String get urlCopied => 'URL in Zwischenablage kopiert';

  @override
  String get contributionsWelcome => 'Beiträge willkommen. Bitte zuerst ein Issue eröffnen.';

  @override
  String get openSourceLicenses => 'Open-Source-Lizenzen';

  @override
  String get hintsAndAnalysis => 'Hinweise & Analyse';

  @override
  String get maia3Model => 'Maia3-Modell';

  @override
  String get stockfishVersion => 'Stockfish-Version';

  @override
  String get maiaWeight => 'Maia-Gewicht (ELO-Stufe)';

  @override
  String get gameMode => 'Spielmodus';

  @override
  String get standard => 'Standard';

  @override
  String get kingOfTheHill => 'König des Hügels';

  @override
  String get threeCheck => 'Drei-Schach';

  @override
  String get customTimeControl => 'Benutzerdefiniert...';

  @override
  String get boardColorThemeLabel => 'Brettfarbe';

  @override
  String get notationStyleLabel => 'Notation';

  @override
  String get blindfoldMode => 'Blindfold-Modus';

  @override
  String get blindfoldModeSubtitle => 'Figuren ausblenden — aus dem Gedächtnis spielen';
}
