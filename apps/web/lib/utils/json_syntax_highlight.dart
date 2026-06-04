import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

enum JsonHighlightKind { key, string, number, boolean, nullToken, punctuation, whitespace }

final class JsonHighlightToken {
  const JsonHighlightToken(this.text, this.kind);

  final String text;
  final JsonHighlightKind kind;
}

List<Component> highlightedJsonSpans(String source) {
  return [
    for (final token in tokenizeJson(source))
      span(classes: jsonHighlightClass(token.kind), [.text(token.text)]),
  ];
}

String jsonHighlightClass(JsonHighlightKind kind) => switch (kind) {
  JsonHighlightKind.key => 'json-hl-key',
  JsonHighlightKind.string => 'json-hl-string',
  JsonHighlightKind.number => 'json-hl-number',
  JsonHighlightKind.boolean => 'json-hl-bool',
  JsonHighlightKind.nullToken => 'json-hl-null',
  JsonHighlightKind.punctuation => 'json-hl-punct',
  JsonHighlightKind.whitespace => 'json-hl-ws',
};

List<JsonHighlightToken> tokenizeJson(String source) {
  final tokens = <JsonHighlightToken>[];
  var i = 0;

  while (i < source.length) {
    final char = source[i];

    if (char == '"') {
      final start = i;
      i++;
      while (i < source.length) {
        if (source[i] == r'\') {
          i += 2;
          continue;
        }
        if (source[i] == '"') {
          i++;
          break;
        }
        i++;
      }
      final text = source.substring(start, i);
      var peek = i;
      while (peek < source.length && _isJsonWhitespace(source[peek])) {
        peek++;
      }
      final kind = peek < source.length && source[peek] == ':'
          ? JsonHighlightKind.key
          : JsonHighlightKind.string;
      tokens.add(JsonHighlightToken(text, kind));
      continue;
    }

    if (char == '{' || char == '}' || char == '[' || char == ']' || char == ':' || char == ',') {
      tokens.add(JsonHighlightToken(char, JsonHighlightKind.punctuation));
      i++;
      continue;
    }

    if (_isJsonWhitespace(char)) {
      final start = i;
      while (i < source.length && _isJsonWhitespace(source[i])) {
        i++;
      }
      tokens.add(JsonHighlightToken(source.substring(start, i), JsonHighlightKind.whitespace));
      continue;
    }

    if (char == '-' || _isJsonDigit(char)) {
      final start = i;
      if (source[i] == '-') i++;
      while (i < source.length) {
        final c = source[i];
        if (_isJsonDigit(c) || c == '.' || c == 'e' || c == 'E' || c == '+' || c == '-') {
          i++;
          continue;
        }
        break;
      }
      tokens.add(JsonHighlightToken(source.substring(start, i), JsonHighlightKind.number));
      continue;
    }

    if (source.startsWith('true', i)) {
      tokens.add(const JsonHighlightToken('true', JsonHighlightKind.boolean));
      i += 4;
      continue;
    }
    if (source.startsWith('false', i)) {
      tokens.add(const JsonHighlightToken('false', JsonHighlightKind.boolean));
      i += 5;
      continue;
    }
    if (source.startsWith('null', i)) {
      tokens.add(const JsonHighlightToken('null', JsonHighlightKind.nullToken));
      i += 4;
      continue;
    }

    tokens.add(JsonHighlightToken(char, JsonHighlightKind.punctuation));
    i++;
  }

  return tokens;
}

bool _isJsonWhitespace(String char) => char == ' ' || char == '\t' || char == '\n' || char == '\r';

bool _isJsonDigit(String char) {
  final code = char.codeUnitAt(0);
  return code >= 0x30 && code <= 0x39;
}
