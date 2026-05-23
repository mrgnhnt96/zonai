import 'package:zonai_schema/zonai_schema.dart';

/// Collection rules for framework tables: never exposed via the public DB API.
base class InternalCollectionRules<S extends Collection<R>, R>
    extends CollectionRules<S, R> {
  const InternalCollectionRules(super.schema);

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
base class InternalRecordRules<S extends Collection<R>, R>
    extends RecordRules<S, R> {
  const InternalRecordRules(super.schema);

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
