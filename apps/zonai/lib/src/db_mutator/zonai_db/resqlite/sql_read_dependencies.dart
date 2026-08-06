// Ported from raindrop_sqlite's sql_read_dependencies.dart -- see
// resqlite_delegate.dart in this directory for why.

import 'package:resqlite/resqlite.dart' as rs;

/// Best-effort table dependency extraction for read-only stream SQL.
///
/// Used by [HybridStreamEngine] when sqlite3 cannot install an authorizer.
/// Returns [rs.TableDependencies.unknown] when table references cannot be
/// determined reliably.
rs.TableDependencies readDependenciesForStreamSql(String sql) {
  final verb = _mainSqlVerb(sql);
  if (verb == null) return rs.TableDependencies.unknown;
  if (verb == 'VALUES') return rs.TableDependencies.none;

  final tables = _extractReferencedTables(sql);
  if (tables == null) return rs.TableDependencies.unknown;
  if (tables.isEmpty) return rs.TableDependencies.none;
  return rs.TableDependencies.fixed([
    for (final table in tables) rs.TableDependency(table),
  ]);
}

/// Returns `null` when parsing is inconclusive.
Set<String>? _extractReferencedTables(String sql) {
  final tables = <String>{};
  var i = 0;
  var afterFrom = false;

  while (i < sql.length) {
    i = _skipWhitespaceCommentsStrings(sql, i);
    if (i >= sql.length) break;

    final c = sql.codeUnitAt(i);
    if (c == 0x28) {
      i++;
      continue;
    }
    if (c == 0x29) {
      afterFrom = false;
      i++;
      continue;
    }
    if (c == 0x2C) {
      if (afterFrom) {
        i++;
        final table = _readTableReference(sql, i);
        if (table == null) return null;
        if (!table.isEmpty) tables.add(table.name);
        i = table.end;
        continue;
      }
      i++;
      continue;
    }

    final word = _readUpperWord(sql, i);
    if (word == null) {
      i++;
      continue;
    }

    switch (word.upper) {
      case 'FROM':
        afterFrom = true;
        i = word.after;
        final table = _readTableReference(sql, i);
        if (table == null) return null;
        if (!table.isEmpty) tables.add(table.name);
        i = table.end;
      case 'JOIN':
      case 'INNER':
      case 'LEFT':
      case 'RIGHT':
      case 'CROSS':
      case 'FULL':
      case 'NATURAL':
        afterFrom = false;
        i = _skipJoinModifiers(sql, word);
        final joined = _readTableReference(sql, i);
        if (joined == null) return null;
        if (!joined.isEmpty) tables.add(joined.name);
        i = joined.end;
      case 'UNION':
      case 'INTERSECT':
      case 'EXCEPT':
        return null;
      default:
        afterFrom = false;
        i = word.after;
    }
  }

  return tables;
}

int _skipJoinModifiers(String sql, ({String upper, int after}) word) {
  var i = word.after;
  while (true) {
    // Only whitespace/comments, not strings: the table right after JOIN (or
    // after a JOIN modifier) may be a quoted identifier, and skipping it here
    // as string noise would consume it before _readTableReference can parse
    // it, leaving `i` pointing at whatever word comes after (e.g. an alias's
    // AS keyword) instead of the table itself.
    i = _skipWhitespaceComments(sql, i);
    final next = _readUpperWord(sql, i);
    if (next == null) return i;
    switch (next.upper) {
      case 'OUTER':
      case 'INNER':
      case 'LEFT':
      case 'RIGHT':
      case 'CROSS':
      case 'FULL':
      case 'NATURAL':
        i = next.after;
        continue;
      case 'JOIN':
        return next.after;
      default:
        return i;
    }
  }
}

({String name, int end, bool isEmpty})? _readTableReference(String sql, int i) {
  // Only whitespace/comments here, NOT strings: the very next token may be
  // the quoted identifier this function itself needs to parse (the isQuote
  // branch below). Skipping strings generically would consume it as noise
  // before that branch ever runs, then mis-read whatever word comes after
  // it as the table name instead.
  i = _skipWhitespaceComments(sql, i);
  if (i >= sql.length) return (name: '', end: i, isEmpty: true);

  final c = sql.codeUnitAt(i);
  if (c == 0x28) {
    return (name: '', end: i, isEmpty: true);
  }

  String name;
  var end = i;
  if (c == 0x22 || c == 0x27 || c == 0x60) {
    final quoted = _readQuotedIdentifier(sql, i);
    if (quoted == null) return null;
    end = quoted.end;
    name = quoted.value;
  } else {
    final word = _readIdentifier(sql, i);
    if (word == null) return null;
    name = word.name;
    end = word.after;
  }

  // Same reasoning as above: only whitespace/comments, not strings -- a
  // quoted alias or the next clause's quoted identifier must not be
  // consumed here while merely checking for a schema-qualifying dot.
  i = _skipWhitespaceComments(sql, end);
  if (i < sql.length && sql.codeUnitAt(i) == 0x2E) {
    i++;
    i = _skipWhitespaceComments(sql, i);
    final second = _readTableReference(sql, i);
    if (second == null) return null;
    if (second.isEmpty) return null;
    return (name: second.name, end: second.end, isEmpty: false);
  }

  return (name: name, end: end, isEmpty: name.isEmpty);
}

({String value, int end})? _readQuotedIdentifier(String sql, int i) {
  final quote = sql.codeUnitAt(i);
  i++;
  final buffer = StringBuffer();
  while (i < sql.length) {
    final c = sql.codeUnitAt(i);
    if (c == quote) {
      if (quote == 0x27 &&
          i + 1 < sql.length &&
          sql.codeUnitAt(i + 1) == 0x27) {
        buffer.writeCharCode(0x27);
        i += 2;
        continue;
      }
      return (value: buffer.toString(), end: i + 1);
    }
    buffer.writeCharCode(c);
    i++;
  }
  return null;
}

bool _isWhitespace(int c) =>
    c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x0C;

bool _isIdentifierChar(String s, int i) {
  if (i >= s.length) return false;
  final c = s.codeUnitAt(i);
  if (c >= 0x30 && c <= 0x39) return true;
  if (c >= 0x41 && c <= 0x5A) return true;
  if (c >= 0x61 && c <= 0x7A) return true;
  if (c == 0x5F) return true;
  return false;
}

int _skipWhitespaceComments(String s, int i) {
  while (i < s.length) {
    if (_isWhitespace(s.codeUnitAt(i))) {
      i++;
      continue;
    }
    if (s.codeUnitAt(i) == 0x2D &&
        i + 1 < s.length &&
        s.codeUnitAt(i + 1) == 0x2D) {
      i += 2;
      while (i < s.length && s.codeUnitAt(i) != 0x0A) i++;
      continue;
    }
    if (s.codeUnitAt(i) == 0x2F &&
        i + 1 < s.length &&
        s.codeUnitAt(i + 1) == 0x2A) {
      i += 2;
      while (i + 1 < s.length &&
          !(s.codeUnitAt(i) == 0x2A && s.codeUnitAt(i + 1) == 0x2F)) {
        i++;
      }
      i += 2;
      continue;
    }
    break;
  }
  return i;
}

int _skipString(String s, int i) {
  final quote = s.codeUnitAt(i);
  i++;
  while (i < s.length) {
    final c = s.codeUnitAt(i);
    if (c == quote) {
      if (quote == 0x27 && i + 1 < s.length && s.codeUnitAt(i + 1) == 0x27) {
        i += 2;
        continue;
      }
      return i + 1;
    }
    i++;
  }
  return i;
}

int _skipWhitespaceCommentsStrings(String s, int i) {
  while (i < s.length) {
    final next = _skipWhitespaceComments(s, i);
    if (next != i) {
      i = next;
      continue;
    }
    final c = s.codeUnitAt(i);
    if (c == 0x27 || c == 0x22) {
      i = _skipString(s, i);
      continue;
    }
    break;
  }
  return i;
}

({String upper, int after})? _readUpperWord(String s, int i) {
  if (i >= s.length || !_isIdentifierChar(s, i)) return null;
  final start = i;
  i++;
  while (i < s.length && _isIdentifierChar(s, i)) i++;
  return (upper: s.substring(start, i).toUpperCase(), after: i);
}

({String name, int after})? _readIdentifier(String s, int i) {
  if (i >= s.length || !_isIdentifierChar(s, i)) return null;
  final start = i;
  i++;
  while (i < s.length && _isIdentifierChar(s, i)) i++;
  return (name: s.substring(start, i), after: i);
}

String? _mainSqlVerb(String query) {
  var i = _skipWhitespaceCommentsStrings(query, 0);
  if (i >= query.length) return null;
  final w = _readUpperWord(query, i);
  if (w == null) return null;
  if (w.upper != 'WITH') return w.upper;
  i = _skipWithClause(query, w.after);
  i = _skipWhitespaceCommentsStrings(query, i);
  if (i >= query.length) return null;
  return _readUpperWord(query, i)?.upper;
}

int _skipWithClause(String s, int i) {
  i = _skipWhitespaceCommentsStrings(s, i);
  final iFirst = i;
  final first = _readUpperWord(s, i);
  if (first == null) return i;
  if (first.upper == 'RECURSIVE') {
    i = _skipWhitespaceCommentsStrings(s, first.after);
  } else {
    i = iFirst;
  }
  while (true) {
    i = _skipWhitespaceCommentsStrings(s, i);
    final name = _readUpperWord(s, i);
    if (name == null) return i;
    i = _skipWhitespaceCommentsStrings(s, name.after);
    final asTok = _readUpperWord(s, i);
    if (asTok == null || asTok.upper != 'AS') return i;
    i = _skipWhitespaceCommentsStrings(s, asTok.after);
    if (i >= s.length || s.codeUnitAt(i) != 0x28) return i;
    var depth = 0;
    var j = i;
    while (j < s.length) {
      final c = s.codeUnitAt(j);
      if (c == 0x27 || c == 0x22) {
        j = _skipString(s, j);
        continue;
      }
      if (c == 0x28) {
        depth++;
        j++;
        continue;
      }
      if (c == 0x29) {
        depth--;
        j++;
        if (depth == 0) break;
        continue;
      }
      j++;
    }
    i = j;
    i = _skipWhitespaceCommentsStrings(s, i);
    if (i < s.length && s.codeUnitAt(i) == 0x2C) {
      i++;
      continue;
    }
    break;
  }
  return i;
}
