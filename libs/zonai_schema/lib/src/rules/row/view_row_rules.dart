part of rules;

/// [RowRules] for a read-only view.
///
/// [canCreate]/[canUpdate]/[canDelete] are fixed to always deny, regardless
/// of admin status — [BaseRowRules]'s defaults grant those to an admin JWT
/// unless overridden, which is exactly the gap a view must not have. Only
/// [canView] is meaningful to override.
class ViewRowRules<S extends Table<R>, R> extends RowRules<S, R> {
  const ViewRowRules(super.schema);

  @override
  Future<bool> canCreate(Jwt? jwt, R row) async => false;

  @override
  Future<bool> canUpdate(Jwt? jwt, R row) async => false;

  @override
  Future<bool> canDelete(Jwt? jwt, R row) async => false;
}
