// Members of the extension over the `purchases` table the docs invent.
import 'package:my_app/src/schemas/purchases.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class PurchaseExtensions extends Extension<Purchase> {
  PurchaseExtensions() : super(purchases);

  // <<body>>
}
