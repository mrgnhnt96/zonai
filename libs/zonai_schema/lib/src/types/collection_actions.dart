/// Table-level actions allowed for the current caller on a collection.
final class TableCollectionActions {
  const TableCollectionActions({
    required this.table,
    required this.canCreate,
    required this.canUpdate,
    required this.canDelete,
  });

  final String table;
  final bool canCreate;
  final bool canUpdate;
  final bool canDelete;

  factory TableCollectionActions.denied(String table) {
    return TableCollectionActions(
      table: table,
      canCreate: false,
      canUpdate: false,
      canDelete: false,
    );
  }

  factory TableCollectionActions.fromJson(Map<String, dynamic> json) {
    return TableCollectionActions(
      table: json['table'] as String,
      canCreate: json['canCreate'] as bool? ?? false,
      canUpdate: json['canUpdate'] as bool? ?? false,
      canDelete: json['canDelete'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'table': table,
    'canCreate': canCreate,
    'canUpdate': canUpdate,
    'canDelete': canDelete,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TableCollectionActions &&
        table == other.table &&
        canCreate == other.canCreate &&
        canUpdate == other.canUpdate &&
        canDelete == other.canDelete;
  }

  @override
  int get hashCode => Object.hash(table, canCreate, canUpdate, canDelete);
}
