import 'package:zonai_schema/src/types/id.dart';

class User {
  const User({required this.isSuperUser, required this.id});
  const User.fake({required this.isSuperUser}) : id = const _FakeId();

  final bool isSuperUser;
  final Id id;
}

class _FakeId implements Id {
  const _FakeId();

  @override
  String get value => 'fake_id';
}
