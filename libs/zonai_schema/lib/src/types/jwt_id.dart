import 'package:zonai_schema/src/types/id.dart';

class JwtId implements Id {
  const JwtId(this.value);
  static JwtId generate() => JwtId(Id.generate('jwt'));

  @override
  final String value;
}
