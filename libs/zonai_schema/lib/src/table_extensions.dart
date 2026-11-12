import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart' as rd;
import 'package:zonai_schema/src/column_types/created_at_column.dart';
import 'package:zonai_schema/src/column_types/create_primary_key.dart';
import 'package:zonai_schema/src/column_types/revision_column.dart';
import 'package:zonai_schema/src/column_types/updated_at_column.dart';
import 'package:zonai_schema/src/payloads/parse_body.dart';
import 'package:zonai_schema/src/transformers/secret_transformer.dart';
import 'package:zonai_schema/src/transformers/server_generated_transformer.dart';

extension TableExtensions<S extends rd.Schema<R>, R> on rd.TableMeta<S, R> {
  /// Builds a row from [data] that is safe to hand to rules and hooks.
  ///
  /// For a row about to be **inserted** (the default), the server's own
  /// columns are stamped: `createdAt` is now, a nullable `updatedAt` is null.
  ///
  /// For a row that already exists -- [stored] -- those columns keep the values
  /// [data] carries. Stamping them there fabricated history: a rule reading
  /// `created_at` saw the moment the worker decoded the row, and a nullable
  /// `updated_at` was always null (issue #40). A stored NULL is kept too, on
  /// a nullable column: a row written before the column existed has no
  /// creation time, and `now()` would invent one. A timestamp [data] does not
  /// carry at all is still filled in as for an insert, so a partial row can
  /// build.
  ///
  /// [fromCaller] says whether [data]'s values came from the caller: by
  /// default a row about to be inserted did, and a stored row did not. A
  /// caller's value its column cannot hold -- a required column it left out
  /// or sent as null, or a value of the wrong type -- is refused with an
  /// [InvalidBodyException] naming the column, a 400. Building the row used to
  /// throw a bare `TypeError` from inside the app's `fromRow`, before any rule
  /// could look at it, and the caller got a 500 for its own bad body. A stored
  /// row that cannot be built is still that `TypeError`: it is a server fault.
  R safeCreate(
    Map<String, dynamic> data, {
    bool stored = false,
    bool? fromCaller,
  }) {
    final mutable = {...data};
    for (final column in columns) {
      switch (column.transformer) {
        case CreatedAtTransformer() || UpdatedAtTransformer()
            when stored &&
                mutable.containsKey(column.name) &&
                (mutable[column.name] != null || column.isNullable):
          break;
        case final CreatedAtTransformer transformer:
          mutable[column.name] = transformer.encode(.now());
        case final UpdatedAtTransformer transformer:
          if (column.isNullable) {
            mutable[column.name] = null;
          } else {
            mutable[column.name] = transformer.encode(.now());
          }
        case final CreatePrimaryKey transformer:
          if (column.autoIncrement) continue;
          if (!column.isPrimaryKey) continue;
          mutable[column.name] ??= transformer.encodedPrimaryKey();
        // Before the ServerGeneratedTransformer case below, which it also
        // is: that one fills a blank string, and a revision is an integer.
        // A stored row keeps its real revision (rules rebuild rows read back
        // from the database). A row about to be inserted starts at 0 whatever
        // it carries: a client that SENDS one is refused before it gets here
        // -- see `TableOperations` -- and this is the second line.
        case RevisionTransformer():
          if (stored) {
            mutable[column.name] ??= 0;
          } else {
            mutable[column.name] = 0;
          }
        case SecretTransformer() || ServerGeneratedTransformer():
          if (!mutable.containsKey(column.name)) {
            mutable[column.name] = column.isNullable ? null : '';
          }
        default:
          break;
      }
    }

    if (!(fromCaller ?? !stored)) return create(mutable);

    T read<T extends Object?>(rd.ColumnType<T>? column) {
      if (column == null) {
        throw StateError('Tried to read a null column reference on $name.');
      }

      final value = mutable[column.name];

      // The value's type, never the value: the message goes back to the
      // caller and into the logs.
      Never refuse() => throw InvalidBodyException(switch (value) {
        null when !mutable.containsKey(column.name) =>
          'Column "${column.name}" on "$name" is required',
        null => 'Column "${column.name}" on "$name" cannot be null',
        _ =>
          'Column "${column.name}" on "$name" cannot hold a '
              '${value.runtimeType}',
      });

      try {
        return column.decode(value) as T;
      } on TypeError {
        refuse();
      } on FormatException {
        refuse();
      } on ArgumentError {
        refuse();
      }
    }

    return schema.fromRow(read);
  }
}
