// The Dart tokenizers against the reference `tokenizers` library, token for
// token, on chess notation in every format the bots use. The tokenizer.json
// files are several MB each and downloaded by the app, so they are not in the
// repo: point CHESS_LM_TOKENIZERS at a folder holding <owner>_<name>.json.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/engines/chesslm/tokenizer.dart';

void main() {
  final dir = Platform.environment['CHESS_LM_TOKENIZERS'];
  final probes = jsonDecode(
          File('test/fixtures/chess_lm/tokenizer_probes.json').readAsStringSync())
      as Map<String, dynamic>;
  for (final entry in probes.entries) {
    test('${entry.key} encodes like the tokenizers library', () {
      final tok = ChessLmTokenizer.fromJson(
          File('$dir/${entry.key}.json').readAsStringSync());
      for (final p in entry.value as List) {
        final text = p['text'] as String;
        expect(tok.encode(text, addSpecial: false), p['ids'],
            reason: 'without specials: "$text"');
        expect(tok.encode(text), p['ids_default'], reason: 'default: "$text"');
      }
    }, skip: dir == null ? 'set CHESS_LM_TOKENIZERS to run' : null);
  }
}
