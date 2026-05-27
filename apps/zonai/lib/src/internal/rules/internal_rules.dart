import 'package:zonai_schema/zonai_schema.dart';

/// Table rules for framework tables: never exposed via the public DB API.
base class InternalTableRules<S extends Table<R>, R>
    extends TableRules<S, R> {
  const InternalTableRules(super.schema, {this.canBeOverridden = false});

  final bool canBeOverridden;

  @override
  Future<bool> canCreate(Jwt? jwt) async => false;

  @override
  Future<bool> canUpdate(Jwt? jwt) async => false;

  @override
  Future<bool> canDelete(Jwt? jwt) async => false;

  @override
  Future<bool> canView(Jwt? jwt) async => false;

  @override
  Future<bool> canList(Jwt? jwt) async => switch (jwt?.admin.isAdmin) {
    true => true,
    _ => false,
  };
}

/// Record rules for framework tables: never exposed via the public DB API.
base class InternalRecordRules<S extends Table<R>, R>
    extends RecordRules<S, R> {
  const InternalRecordRules(super.schema, {this.canBeOverridden = false});

  final bool canBeOverridden;

  @override
  Future<bool> canView(Jwt? jwt, R record) async =>
      switch (jwt?.admin.isAdmin) {
        true => true,
        _ => false,
      };

  @override
  Future<bool> canUpdate(Jwt? jwt, R record) async => false;

  @override
  Future<bool> canDelete(Jwt? jwt, R record) async => false;

  @override
  Future<bool> canCreate(Jwt? jwt, R record) async => false;
}
