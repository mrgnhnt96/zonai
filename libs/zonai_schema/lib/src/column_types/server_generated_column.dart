import 'package:raindrop/raindrop.dart' hide Table;
import 'package:zonai_schema/src/transformers/server_generated_transformer.dart';

extension ServerGeneratedColumnDefinition<S> on SchemaBuilder<S> {
  /// A text column whose value is always overwritten by a custom
  /// `TableOperations.insert` override before a row is persisted — see
  /// [ServerGeneratedTransformer].
  ColumnType<W> serverGenerated<W extends String?>(
    String name,
    Field<S, W> field,
  ) {
    return custom<String, String, W>(
      name,
      field,
      sqlType: 'TEXT',
      transformer: const ServerGeneratedTextTransformer(),
    );
  }
}

class ServerGeneratedTextTransformer extends ColumnTransformer<String, String>
    implements ServerGeneratedTransformer<String, String> {
  const ServerGeneratedTextTransformer();

  @override
  String encode(String input) => input;

  @override
  String decode(String input) => input;
}
