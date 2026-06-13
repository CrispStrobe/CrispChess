import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/services/sound_service.dart';

void main() {
  group('SoundService', () {
    test('is enabled by default', () {
      final svc = SoundService();
      expect(svc.enabled, isTrue);
    });

    test('can be disabled', () {
      final svc = SoundService();
      svc.enabled = false;
      expect(svc.enabled, isFalse);
    });

    test('volume clamps to 0-1 range', () {
      final svc = SoundService();
      svc.volume = -0.5;
      expect(svc.volume, 0.0);
      svc.volume = 1.5;
      expect(svc.volume, 1.0);
      svc.volume = 0.5;
      expect(svc.volume, 0.5);
    });

    test('play does not throw when enabled', () {
      final svc = SoundService();
      expect(() => svc.play(ChessSound.move), returnsNormally);
      expect(() => svc.play(ChessSound.capture), returnsNormally);
      expect(() => svc.play(ChessSound.check), returnsNormally);
      expect(() => svc.play(ChessSound.gameEnd), returnsNormally);
    });

    test('play does not throw when disabled', () {
      final svc = SoundService();
      svc.enabled = false;
      expect(() => svc.play(ChessSound.move), returnsNormally);
    });

    test('ChessSound enum has all expected values', () {
      expect(ChessSound.values.length, 8);
      expect(ChessSound.values, contains(ChessSound.move));
      expect(ChessSound.values, contains(ChessSound.capture));
      expect(ChessSound.values, contains(ChessSound.check));
      expect(ChessSound.values, contains(ChessSound.castle));
      expect(ChessSound.values, contains(ChessSound.promote));
      expect(ChessSound.values, contains(ChessSound.gameStart));
      expect(ChessSound.values, contains(ChessSound.gameEnd));
      expect(ChessSound.values, contains(ChessSound.illegal));
    });

    test('dispose does not throw', () {
      final svc = SoundService();
      expect(() => svc.dispose(), returnsNormally);
    });
  });
}
