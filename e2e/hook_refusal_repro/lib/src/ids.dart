import 'package:zonai_schema/zonai_schema.dart' as z;

final class PostsId implements z.Id {
  const PostsId(this.value);

  static const _suffix = 'pst';

  factory PostsId.generate() =>
      PostsId('${DateTime.now().microsecondsSinceEpoch}_$_suffix');

  @override
  final String value;

  @override
  String toString() => value;

  String toJson() => value;
}
