/// Models for UCI engine options parsed from the `option` lines
/// sent during the UCI handshake.

enum UciOptionType { check, spin, combo, button, string }

class UciOption {
  final String name;
  final UciOptionType type;

  /// Current value (String representation). Null for button type.
  String? value;

  /// Default value from the engine.
  final String? defaultValue;

  /// For spin type: min/max bounds.
  final int? min;
  final int? max;

  /// For combo type: list of allowed values.
  final List<String>? comboValues;

  UciOption({
    required this.name,
    required this.type,
    this.value,
    this.defaultValue,
    this.min,
    this.max,
    this.comboValues,
  });

  /// Parse a UCI `option` line into a [UciOption].
  ///
  /// Format: `option name <name> type <type> [default <val>] [min <val>] [max <val>] [var <val>]*`
  static UciOption? parse(String line) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('option name ')) return null;

    // Extract name (everything between "option name " and " type ")
    final typeIndex = trimmed.indexOf(' type ');
    if (typeIndex < 0) return null;
    final name = trimmed.substring(12, typeIndex); // 12 = 'option name '.length

    final rest = trimmed.substring(typeIndex + 6); // 6 = ' type '.length

    // Parse type
    final UciOptionType type;
    String afterType;
    if (rest.startsWith('check')) {
      type = UciOptionType.check;
      afterType = rest.substring(5).trim();
    } else if (rest.startsWith('spin')) {
      type = UciOptionType.spin;
      afterType = rest.substring(4).trim();
    } else if (rest.startsWith('combo')) {
      type = UciOptionType.combo;
      afterType = rest.substring(5).trim();
    } else if (rest.startsWith('button')) {
      type = UciOptionType.button;
      afterType = rest.substring(6).trim();
    } else if (rest.startsWith('string')) {
      type = UciOptionType.string;
      afterType = rest.substring(6).trim();
    } else {
      return null;
    }

    String? defaultValue;
    int? min;
    int? max;
    List<String>? comboValues;

    // Parse remaining tokens
    final tokens = afterType.split(' ');
    for (int i = 0; i < tokens.length; i++) {
      switch (tokens[i]) {
        case 'default':
          // Collect everything until next keyword (min, max, var) or end
          final parts = <String>[];
          for (int j = i + 1; j < tokens.length; j++) {
            if (tokens[j] == 'min' || tokens[j] == 'max' || tokens[j] == 'var') break;
            parts.add(tokens[j]);
          }
          defaultValue = parts.join(' ');
          i += parts.length;
        case 'min':
          if (i + 1 < tokens.length) {
            min = int.tryParse(tokens[i + 1]);
            i++;
          }
        case 'max':
          if (i + 1 < tokens.length) {
            max = int.tryParse(tokens[i + 1]);
            i++;
          }
        case 'var':
          comboValues ??= [];
          // Collect value until next 'var' or end
          final parts = <String>[];
          for (int j = i + 1; j < tokens.length; j++) {
            if (tokens[j] == 'var') break;
            parts.add(tokens[j]);
          }
          if (parts.isNotEmpty) {
            comboValues.add(parts.join(' '));
            i += parts.length;
          }
      }
    }

    return UciOption(
      name: name,
      type: type,
      value: defaultValue,
      defaultValue: defaultValue,
      min: min,
      max: max,
      comboValues: comboValues,
    );
  }

  /// Format as UCI `setoption` command.
  String toSetOptionCommand() {
    if (type == UciOptionType.button) {
      return 'setoption name $name';
    }
    return 'setoption name $name value $value';
  }

  @override
  String toString() => 'UciOption($name, $type, value=$value)';
}
