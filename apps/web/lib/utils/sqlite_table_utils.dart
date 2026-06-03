/// Returns true for framework-managed SQLite tables (`_`-prefixed names).
bool isSystemSqliteTable(String sqliteName) => sqliteName.startsWith('_');
