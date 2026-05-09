import 'package:zonai_schema/src/types/user.dart';

class Request<T> {
  const Request({required this.user});

  final User user;
}
