import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/src/email/courier.dart';

final courierProvider = create<Courier>(Courier.new);

Courier get courier => read(courierProvider);
