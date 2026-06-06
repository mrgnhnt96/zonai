/// Table-level actions allowed for the current caller on a collection.
final class TableCollectionActions {
  const TableCollectionActions({
    required this.table,
    required this.canList,
    required this.canView,
    required this.canCreate,
    required this.canUpdate,
    required this.canDelete,
  });

  final String table;
  final bool canList;
  final bool canView;
  final bool canCreate;
  final bool canUpdate;
  final bool canDelete;

  factory TableCollectionActions.denied(String table) {
    return TableCollectionActions(
      table: table,
      canList: false,
      canView: false,
      canCreate: false,
      canUpdate: false,
      canDelete: false,
    );
  }

  factory TableCollectionActions.fromJson(Map<String, dynamic> json) {
    return TableCollectionActions(
      table: json['table'] as String,
      canList: json['canList'] as bool? ?? false,
      canView: json['canView'] as bool? ?? false,
      canCreate: json['canCreate'] as bool? ?? false,
      canUpdate: json['canUpdate'] as bool? ?? false,
      canDelete: json['canDelete'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'table': table,
    'canList': canList,
    'canView': canView,
    'canCreate': canCreate,
    'canUpdate': canUpdate,
    'canDelete': canDelete,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TableCollectionActions &&
        table == other.table &&
        canList == other.canList &&
        canView == other.canView &&
        canCreate == other.canCreate &&
        canUpdate == other.canUpdate &&
        canDelete == other.canDelete;
  }

  @override
  int get hashCode =>
      Object.hash(table, canList, canView, canCreate, canUpdate, canDelete);
}
