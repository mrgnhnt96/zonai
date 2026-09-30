import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';
import 'package:zonai_schema/src/transformers/server_generated_transformer.dart';

extension RevisionColumnDefinition<S> on SchemaBuilder<S> {
  /// A revision counter the server maintains: `0` when the row is created,
  /// and one higher on every update, whatever the update changed.
  ///
  /// It is how a client knows which version of a row it holds, so it can
  /// update only if nobody else did in between (`UpdateBody.expect`,
  /// `Eq('rev', 3)`). Being server-maintained is the whole point: a value a
  /// client could write proves nothing, so a create or update that sets it is
  /// refused with a `400` rather than quietly ignored -- a client that thinks
  /// it wrote the revision is exactly the one that must be told it did not.
  ///
  /// `INTEGER NOT NULL DEFAULT 0`, so adding it to a table that already has
  /// rows migrates them to revision `0`.
  ColumnType<int> revision(String name, Field<S, int> field) {
    return custom<int, int, int>(
      name,
      field,
      transformer: const RevisionTransformer(),
      sqlType: 'INTEGER',
      defaultValue: 0,
    );
  }
}

/// Marks a column as a server-maintained revision; see
/// [RevisionColumnDefinition.revision].
///
/// A [ServerGeneratedTransformer], so the dashboard shows it read-only and the
/// generated client treats it as set by the server.
class RevisionTransformer implements ServerGeneratedTransformer<int, int> {
  const RevisionTransformer();

  @override
  int encode(int input) => input;

  @override
  int decode(int input) => input;
}
