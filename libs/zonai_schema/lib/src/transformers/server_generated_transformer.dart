import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';

/// A transformer for a column whose real value is supplied later by a
/// custom `TableOperations.insert` override (e.g. a server-generated API
/// key or token) — never trust a client-supplied value for it.
///
/// `Table.safeCreate` fills in a blank placeholder for this column when a
/// create payload omits it, the same way it does for [SecretTransformer]
/// columns, so the column can stay non-nullable while still being buildable
/// at rule-check time (rules run before operations, against a row built
/// from the raw request data — see docs/rules.md and docs/operations.md).
///
/// Unlike [SecretTransformer], values using this transformer are **not**
/// stripped from responses during sanitization — use this when the
/// column's eventual value should be visible to ordinary callers (unlike a
/// password), just not something the client provides at create time.
///
/// `tableSchemaShapeFromTable` also flags these columns `isReadOnly`, so the
/// admin dashboard displays the value but doesn't offer a raw text field to
/// overwrite it directly.
abstract interface class ServerGeneratedTransformer<T, O>
    extends ColumnTransformer<T, O> {
  const ServerGeneratedTransformer();
}
