/// Reduces Dart source to the part of it that can change what crosses the
/// wire, so a contract hash (see `message_contract_hash.dart`) doesn't fire on
/// edits that cannot.
///
/// Two things are removed: comments, and the difference between one run of
/// whitespace and another. Both are invisible to a compiled worker, and both
/// change constantly in this repo -- the schema sources are more doc comment
/// than code, and `dart format` reflows them. Hashing raw bytes would make a
/// typo fix in a dartdoc refuse every worker on disk, which is how a guard
/// teaches people to ignore it.
///
/// String literals are *kept verbatim*. They are not decoration: the JSON keys
/// the handlers parse (`'operation'`, `'customOperation'`, `Request.prefix`)
/// are string literals, and renaming one is exactly the kind of silent
/// vocabulary change this exists to catch.
library;

const _slash = 0x2F; // /
const _star = 0x2A; // *
const _newline = 0x0A;
const _singleQuote = 0x27; // '
const _doubleQuote = 0x22; // "
const _backslash = 0x5C;
const _dollar = 0x24;
const _openBrace = 0x7B;
const _closeBrace = 0x7D;
const _lowerR = 0x72;

final _whitespaceRun = RegExp(r'\s+');

/// [source] with comments dropped and all whitespace runs collapsed to a
/// single space.
///
/// This is a scanner, not a parser: it knows just enough about string literals
/// (raw, triple-quoted, `${...}` interpolation) to avoid mistaking a `//`
/// inside one for a comment. Anything it gets wrong it gets wrong the same way
/// every time, which is all a hash needs -- both sides of a comparison run
/// this same function.
String normalizeDartSource(String source) {
  final out = StringBuffer();
  final length = source.length;
  var i = 0;

  while (i < length) {
    if (_startsWith(source, i, _slash, _slash)) {
      while (i < length && source.codeUnitAt(i) != _newline) {
        i++;
      }
      out.writeCharCode(_newline);
      continue;
    }

    if (_startsWith(source, i, _slash, _star)) {
      i = _skipBlockComment(source, i);
      out.writeCharCode(_newline);
      continue;
    }

    final unit = source.codeUnitAt(i);
    if (unit == _singleQuote || unit == _doubleQuote) {
      final end = _scanString(source, i, raw: _isRawStringStart(source, i));
      out.write(source.substring(i, end));
      i = end;
      continue;
    }

    out.writeCharCode(unit);
    i++;
  }

  return out.toString().replaceAll(_whitespaceRun, ' ').trim();
}

bool _startsWith(String source, int index, int first, int second) {
  return index + 1 < source.length &&
      source.codeUnitAt(index) == first &&
      source.codeUnitAt(index + 1) == second;
}

/// Dart block comments nest, so this counts depth rather than looking for the
/// first `*/`.
int _skipBlockComment(String source, int start) {
  final length = source.length;
  var depth = 1;
  var i = start + 2;

  while (i < length && depth > 0) {
    if (_startsWith(source, i, _slash, _star)) {
      depth++;
      i += 2;
    } else if (_startsWith(source, i, _star, _slash)) {
      depth--;
      i += 2;
    } else {
      i++;
    }
  }

  return i;
}

/// Whether the quote at [index] opens a raw string (`r'...'`), where a
/// backslash escapes nothing.
bool _isRawStringStart(String source, int index) {
  if (index == 0) return false;
  if (source.codeUnitAt(index - 1) != _lowerR) return false;
  if (index == 1) return true;

  // `r` only marks a raw string when it is a token of its own -- in
  // `myVar'...'` (not valid Dart, but the scanner must not guess) or
  // `other'` the preceding character would be part of an identifier.
  return !_isIdentifierPart(source.codeUnitAt(index - 2));
}

bool _isIdentifierPart(int unit) {
  return (unit >= 0x30 && unit <= 0x39) || // 0-9
      (unit >= 0x41 && unit <= 0x5A) || // A-Z
      (unit >= 0x61 && unit <= 0x7A) || // a-z
      unit == 0x5F || // _
      unit == _dollar;
}

/// Index just past the string literal opening at [start].
///
/// Returns the end of the source for an unterminated literal rather than
/// throwing: this runs over whatever is on disk, including a file mid-edit,
/// and refusing to hash a half-written file would turn an editor keystroke
/// into a failed compile.
int _scanString(String source, int start, {required bool raw}) {
  final length = source.length;
  final quote = source.codeUnitAt(start);
  final triple = _isTripleQuote(source, start, quote);
  final delimiterLength = triple ? 3 : 1;
  var i = start + delimiterLength;

  while (i < length) {
    final unit = source.codeUnitAt(i);

    if (!raw && unit == _backslash) {
      i += 2;
      continue;
    }

    // An unterminated single-line literal ends at the newline. Without this a
    // stray quote would swallow the rest of the file.
    if (!triple && unit == _newline) return i;

    if (!raw && unit == _dollar && _codeUnitAt(source, i + 1) == _openBrace) {
      i = _skipInterpolation(source, i + 1);
      continue;
    }

    if (unit == quote) {
      if (!triple) return i + 1;
      if (_isTripleQuote(source, i, quote)) return i + 3;
    }

    i++;
  }

  return length;
}

bool _isTripleQuote(String source, int index, int quote) {
  return _codeUnitAt(source, index + 1) == quote &&
      _codeUnitAt(source, index + 2) == quote;
}

/// Index just past the `}` closing the `${` at [openBrace], skipping nested
/// braces and any string literals inside the expression.
int _skipInterpolation(String source, int openBrace) {
  final length = source.length;
  var depth = 0;
  var i = openBrace;

  while (i < length) {
    final unit = source.codeUnitAt(i);

    if (unit == _singleQuote || unit == _doubleQuote) {
      i = _scanString(source, i, raw: _isRawStringStart(source, i));
      continue;
    }

    if (unit == _openBrace) {
      depth++;
    } else if (unit == _closeBrace) {
      depth--;
      if (depth == 0) return i + 1;
    }

    i++;
  }

  return length;
}

int? _codeUnitAt(String source, int index) {
  if (index < 0 || index >= source.length) return null;
  return source.codeUnitAt(index);
}
