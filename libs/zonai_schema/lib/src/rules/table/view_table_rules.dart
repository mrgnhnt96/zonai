part of rules;

/// [TableRules] for a read-only view.
///
/// [canCreate]/[canUpdate]/[canDelete] are fixed to always deny, regardless
/// of admin status — [BaseTableRules]'s defaults grant those to an admin
/// JWT unless overridden, which is exactly the gap a view must not have.
/// Only [canView]/[canList] are meaningful to override.
base class ViewTableRules<S extends Table<R>, R> extends TableRules<S, R> {
  const ViewTableRules(super.schema);

  @override
  Future<bool> canCreate(Jwt? jwt) async => false;

  @override
  Future<bool> canUpdate(Jwt? jwt) async => false;

  @override
  Future<bool> canDelete(Jwt? jwt) async => false;
}
