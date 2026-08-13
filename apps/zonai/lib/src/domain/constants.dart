/// Whether zonai is compiled and is in use by a developer
const kIsCompiled = bool.fromEnvironment('__ZONAI_COMPILED__');

/// SQLite schema name the log database is attached under.
///
/// `_log` is deliberately *not* qualified with this at the call sites that
/// read it -- an unqualified name resolves into an attached database when
/// `main` has none by that name, so the dashboard's raw `FROM "_log"`, the
/// table API and the retention crons all keep working untouched. The name is
/// needed only where a statement has to say *which file* it means: the
/// attach itself, `VACUUM`, `wal_checkpoint`, and the DDL that creates the
/// table there in the first place.
const kLogDbSchema = 'logdb';
