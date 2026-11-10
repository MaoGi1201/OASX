part of 'log_center_panel.dart';

/// Builds highlighted spans for one log line without selectable text overhead.
class _LogTextSpanBuilder {
  /// Creates one span builder.
  const _LogTextSpanBuilder(this.source, this.baseStyle);

  /// Raw log text.
  final String source;

  /// Base style inherited by all generated spans.
  final TextStyle baseStyle;

  /// Builds a compact set of spans for common log tokens.
  List<InlineSpan> build() {
    final value = _trimTrailingBreaks(source);
    final spans = <InlineSpan>[];
    var plainStart = 0;
    var index = 0;
    while (index < value.length) {
      final token = _matchToken(value, index);
      if (token == null) {
        index++;
        continue;
      }
      if (plainStart < index) {
        spans.add(TextSpan(text: value.substring(plainStart, index)));
      }
      spans.add(token);
      index += token.toPlainText().length;
      plainStart = index;
    }
    if (plainStart < value.length) {
      spans.add(TextSpan(text: value.substring(plainStart)));
    }
    return spans.isEmpty ? [TextSpan(text: value)] : spans;
  }

  /// Finds one token match at the current index.
  TextSpan? _matchToken(String value, int index) {
    final timestampLength = _timestampLength(value, index);
    if (timestampLength > 0) {
      return TextSpan(
        text: value.substring(index, index + timestampLength),
        style: baseStyle.copyWith(color: AppColors.logInfo),
      );
    }
    for (final token in _tokens) {
      if (_matchesToken(value, index, token.text)) {
        return TextSpan(text: token.text, style: token.style(baseStyle));
      }
    }
    return null;
  }

  /// Returns the matched timestamp length at the current index.
  int _timestampLength(String value, int index) {
    const fullLength = 23;
    const timeLength = 12;
    if (_matchesTimestamp(value, index, fullLength, hasDate: true)) {
      return fullLength;
    }
    if (_matchesTimestamp(value, index, timeLength, hasDate: false)) {
      return timeLength;
    }
    return 0;
  }

  /// Checks one timestamp pattern without allocating a regular expression.
  bool _matchesTimestamp(
    String value,
    int index,
    int length, {
    required bool hasDate,
  }) {
    if (index + length > value.length) {
      return false;
    }
    if (!hasDate) {
      return _isTime(value, index);
    }
    return _isDigitRange(value, index, 4) &&
        value[index + 4] == '-' &&
        _isDigitRange(value, index + 5, 2) &&
        value[index + 7] == '-' &&
        _isDigitRange(value, index + 8, 2) &&
        value[index + 10] == ' ' &&
        _isTime(value, index + 11);
  }

  /// Checks one HH:mm:ss.SSS timestamp portion.
  bool _isTime(String value, int index) {
    return _isDigitRange(value, index, 2) &&
        value[index + 2] == ':' &&
        _isDigitRange(value, index + 3, 2) &&
        value[index + 5] == ':' &&
        _isDigitRange(value, index + 6, 2) &&
        value[index + 8] == '.' &&
        _isDigitRange(value, index + 9, 3);
  }

  /// Checks whether a token starts at the current word boundary.
  bool _matchesToken(String value, int index, String token) {
    if (!value.startsWith(token, index)) {
      return false;
    }
    final before = index == 0 ? 32 : value.codeUnitAt(index - 1);
    final afterIndex = index + token.length;
    final after = afterIndex >= value.length
        ? 32
        : value.codeUnitAt(afterIndex);
    return !_isWordCode(before) && !_isWordCode(after);
  }

  /// Checks whether a range contains only digits.
  bool _isDigitRange(String value, int start, int length) {
    for (var offset = 0; offset < length; offset++) {
      final code = value.codeUnitAt(start + offset);
      if (code < 48 || code > 57) {
        return false;
      }
    }
    return true;
  }

  /// Checks whether one code unit is part of an identifier-like word.
  bool _isWordCode(int code) {
    return (code >= 48 && code <= 57) ||
        (code >= 65 && code <= 90) ||
        (code >= 97 && code <= 122) ||
        code == 95;
  }

  /// Removes trailing line breaks without allocating a regular expression.
  String _trimTrailingBreaks(String value) {
    var end = value.length;
    while (end > 0) {
      final codeUnit = value.codeUnitAt(end - 1);
      if (codeUnit != 10 && codeUnit != 13) {
        break;
      }
      end--;
    }
    return end == value.length ? value : value.substring(0, end);
  }

  /// Static token list used for bounded highlighting.
  static const _tokens = <_LogToken>[
    _LogToken('CRITICAL', _styleError),
    _LogToken('WARNING', _styleWarning),
    _LogToken('ERROR', _styleError),
    _LogToken('INFO', _styleInfo),
    _LogToken('True', _styleSuccess),
    _LogToken('False', _styleError),
    _LogToken('None', _styleNone),
  ];

  /// Styles the INFO token.
  static TextStyle _styleInfo(TextStyle base) {
    return base.copyWith(color: AppColors.logInfo);
  }

  /// Styles the WARNING token.
  static TextStyle _styleWarning(TextStyle base) {
    return base.copyWith(color: AppColors.logWarn);
  }

  /// Styles error-level tokens.
  static TextStyle _styleError(TextStyle base) {
    return base.copyWith(color: AppColors.logError);
  }

  /// Styles successful boolean-like tokens.
  static TextStyle _styleSuccess(TextStyle base) {
    return base.copyWith(color: AppColors.logSuccess);
  }

  /// Styles null-like tokens.
  static TextStyle _styleNone(TextStyle base) {
    return base.copyWith(color: AppColors.logDebug);
  }
}

/// Lightweight token descriptor for log rendering.
class _LogToken {
  const _LogToken(this.text, this.style);

  /// Token text to match.
  final String text;

  /// Style factory applied when the token matches.
  final TextStyle Function(TextStyle base) style;
}
