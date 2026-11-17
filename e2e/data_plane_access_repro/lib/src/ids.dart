import 'package:zonai_schema/zonai_schema.dart' as z;

/// A microsecond timestamp that never repeats within this process.
///
/// `DateTime.now()` is coarser than a microsecond on Windows, so two rows
/// created back to back -- a cron's `mutate.create` in a loop -- got the same
/// timestamp, and the second insert failed its primary key with a 409.
int _nextMicros() {
  final now = DateTime.now().microsecondsSinceEpoch;
  return _lastMicros = now > _lastMicros ? now : _lastMicros + 1;
}

int _lastMicros = 0;

final class AdminsId implements z.Id {
  const AdminsId(this.value);

  static const _suffix = 'adm';

  factory AdminsId.generate() => AdminsId('${_nextMicros()}_$_suffix');

  @override
  final String value;

  @override
  String toString() => value;

  String toJson() => value;
}

final class UsersId implements z.Id {
  const UsersId(this.value);

  static const _suffix = 'usr';

  factory UsersId.generate() => UsersId('${_nextMicros()}_$_suffix');

  @override
  final String value;

  @override
  String toString() => value;

  String toJson() => value;
}

final class NotesId implements z.Id {
  const NotesId(this.value);

  static const _suffix = 'note';

  factory NotesId.generate() => NotesId('${_nextMicros()}_$_suffix');

  @override
  final String value;

  @override
  String toString() => value;

  String toJson() => value;
}

final class JournalId implements z.Id {
  const JournalId(this.value);

  static const _suffix = 'jrnl';

  factory JournalId.generate() => JournalId('${_nextMicros()}_$_suffix');

  @override
  final String value;

  @override
  String toString() => value;

  String toJson() => value;
}

final class BoardsId implements z.Id {
  const BoardsId(this.value);

  static const _suffix = 'brd';

  factory BoardsId.generate() => BoardsId('${_nextMicros()}_$_suffix');

  @override
  final String value;

  @override
  String toString() => value;

  String toJson() => value;
}
