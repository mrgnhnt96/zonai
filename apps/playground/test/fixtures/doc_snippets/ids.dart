// A stand-in for the `lib/src/ids.dart` that `zonai dev` writes into a new
// project. See tasks.dart for why these fixtures exist and when to extend them.
//
// The docs import it as `package:my_app/src/ids.dart` -- `my_app` being the
// reader's own project, which by definition doesn't exist here.
// doc_snippets_test.dart rewrites that import to this file.
//
// The shape is the one `zonai dev` generates once a project has more than one
// table: a sealed base holding `value` plus the JSON round-trip, and one
// subclass per table carrying only its suffix. `scaffoldUnionIdClass` in
// apps/zonai/lib/src/commands/dev/actions/schema_scaffold.dart is the source of
// truth -- keep this in step with it, since the docs teach it verbatim.
import 'package:zonai_schema/zonai_schema.dart' as z;

sealed class Id implements z.Id {
  const Id(this.value);

  factory Id.fromJson(String json) {
    final parts = json.split('_');

    if (parts.length != 2) {
      throw ArgumentError('Invalid ID format: $json');
    }

    return switch (parts[1]) {
      AdminsId._suffix => AdminsId(json),
      ArticlesId._suffix => ArticlesId(json),
      CommentsId._suffix => CommentsId(json),
      EventsId._suffix => EventsId(json),
      ItemsId._suffix => ItemsId(json),
      PurchasesId._suffix => PurchasesId(json),
      PostsId._suffix => PostsId(json),
      ProfilesId._suffix => ProfilesId(json),
      TasksId._suffix => TasksId(json),
      UsersId._suffix => UsersId(json),
      _ => throw ArgumentError('Invalid ID format: $json'),
    };
  }

  @override
  final String value;

  @override
  String toString() => value;

  String toJson() => value;

  @override
  bool operator ==(Object other) => other is z.Id && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

class AdminsId extends Id {
  const AdminsId(super.value);

  factory AdminsId.generate() => AdminsId(z.Id.generate(_suffix));

  static const _suffix = 'ad';
}

class ArticlesId extends Id {
  const ArticlesId(super.value);

  factory ArticlesId.generate() => ArticlesId(z.Id.generate(_suffix));

  static const _suffix = 'ar';
}

class CommentsId extends Id {
  const CommentsId(super.value);

  factory CommentsId.generate() => CommentsId(z.Id.generate(_suffix));

  static const _suffix = 'cm';
}

class EventsId extends Id {
  const EventsId(super.value);

  factory EventsId.generate() => EventsId(z.Id.generate(_suffix));

  static const _suffix = 'ev';
}

class PurchasesId extends Id {
  const PurchasesId(super.value);

  factory PurchasesId.generate() => PurchasesId(z.Id.generate(_suffix));

  static const _suffix = 'pu';
}

class ItemsId extends Id {
  const ItemsId(super.value);

  factory ItemsId.generate() => ItemsId(z.Id.generate(_suffix));

  static const _suffix = 'it';
}

class PostsId extends Id {
  const PostsId(super.value);

  factory PostsId.generate() => PostsId(z.Id.generate(_suffix));

  static const _suffix = 'po';
}

class ProfilesId extends Id {
  const ProfilesId(super.value);

  factory ProfilesId.generate() => ProfilesId(z.Id.generate(_suffix));

  static const _suffix = 'pr';
}

class TasksId extends Id {
  const TasksId(super.value);

  factory TasksId.generate() => TasksId(z.Id.generate(_suffix));

  static const _suffix = 'tk';
}

class UsersId extends Id {
  const UsersId(super.value);

  factory UsersId.generate() => UsersId(z.Id.generate(_suffix));

  static const _suffix = 'us';
}
