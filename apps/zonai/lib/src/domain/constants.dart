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

/// SQLite schema name the rate-limit database is attached under.
///
/// Same reasoning as [kLogDbSchema], for the same reason: `_rate_limit` is
/// disposable. Every request that reaches a limited operation reads it and
/// writes it, so on the shared file that churn lands in the application
/// database's WAL and competes with real writes for it -- for rows whose
/// entire lifetime is one rate-limit window and which nobody would want back
/// after a crash.
const kRateLimitDbSchema = 'ratedb';
