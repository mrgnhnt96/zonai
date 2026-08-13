// Stand-in for the `purchases` table the docs invent for their email and
// after-create examples.
//
// Named `Purchase` rather than `Order` deliberately: `zonai_schema` exports an
// `Order` enum (the `orderBy({column: Order.asc})` one), so a row class called
// `Order` is ambiguous in any file that imports the schema package -- which is
// every extension and rules file. The docs used to teach `Order`, and could
// not have compiled in a reader's project. See tasks.dart for why these fixtures exist and when
// to extend them.
import 'package:zonai_schema/zonai_schema.dart';

import 'ids.dart';

final class Purchase {
  const Purchase({
    required this.id,
    required this.userId,
    required this.total,
    required this.status,
  });

  final PurchasesId id;

  /// The buyer, as an ID rather than a `String` -- the examples read
  /// `order.userId.value` and compare it against `Jwt.userId`.
  final UsersId userId;
  final int total;
  final String status;
}

final class PurchaseTable extends Table<Purchase> {
  PurchaseTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: PurchasesId.new,
        generate: PurchasesId.generate,
      ),
      userId = $.id(
        'user_id',
        (s) => s.userId,
        fromString: UsersId.new,
        generate: UsersId.generate,
        isPrimaryKey: false,
      ),
      total = $.integer('total', (s) => s.total),
      status = $.text('status', (s) => s.status);

  @override
  Purchase fromRow(RowReader read) => Purchase(
    id: read(id),
    userId: read(userId),
    total: read(total),
    status: read(status),
  );

  final IdColumn<PurchasesId> id;
  final IdColumn<UsersId> userId;
  final IntColumn total;
  final TextColumn status;
}

final purchases = table('purchases', PurchaseTable.new);
