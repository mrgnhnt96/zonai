---
title: Defining Tables
description: How to define database tables and columns using Dart schema files.
---

Schemas define the structure of your database. They are Dart files in `lib/src/schemas/` that describe tables and their columns. When you change a schema file, Zonai generates the SQL migration to keep the database in sync.

<Info>

Registering a table automatically exposes CRUD **and** live stream endpoints (`/db/stream*`). Clients should use `zonai_client` `db.listen` for live UI — [Streaming](/operations/streaming).

</Info>

## The table() Function

`table('table_name', TableClass.new)` registers a table with Zonai. The first argument is the table name as it appears in the database (snake_case, plural). The second is the constructor of the Dart class that defines the columns. The return value is a table reference used in rules, operations, extensions, and rate limits.

## Typed IDs

Every table has its own ID type, so a `tasks` ID can't be passed where a `users` ID is expected. They all live together in `lib/src/ids.dart`, under a `sealed` base class that supplies the shared `value` field:

```dart
import 'package:zonai_schema/zonai_schema.dart' as z;

sealed class Id implements z.Id {
  const Id(this.value);

  @override
  final String value;

  @override
  bool operator ==(Object other) => other is z.Id && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

class TasksId extends Id {
  const TasksId(super.value);

  factory TasksId.generate() => TasksId(z.Id.generate(_suffix));

  static const _suffix = 'tk';  // a short, per-table suffix
}
```

`zonai_schema` is imported as `z` because its `Id` is an `abstract interface class` — your base class *implements* it and declares `value` itself, rather than extending it. Making the base `sealed` is what lets a single `Id.fromJson` switch over every ID in the project exhaustively; see [Quick Start](/getting-started/quick-start) for that full file.

The suffix appears at the end of generated IDs (e.g. `abc123_tk`), making debugging easier.

## Column Types

Each column maps a Dart type to a SQLite type:

| Builder Method | Dart Type | SQLite Type |
|---------------|-----------|-------------|
| `$.text(...)` | `String` | TEXT NOT NULL |
| `$.text(...)` nullable | `String?` | TEXT |
| `$.integer(...)` | `int` | INTEGER NOT NULL |
| `$.real(...)` | `double` | REAL NOT NULL |
| `$.boolean(...)` | `bool` | INTEGER NOT NULL (0/1) |
| `$.dateTime(...)` | `DateTime` | INTEGER NOT NULL (Unix ms) |
| `$.id(...)` | Custom `Id` subclass | TEXT NOT NULL |
| `$.createdAt(...)` | `DateTime` | INTEGER NOT NULL (auto-set) |
| `$.updatedAt(...)` | `DateTime?` | INTEGER (auto-updated) |

A column is nullable when the accessor you hand the builder returns a nullable type — there is no `isNullable` argument. `$.text('bio', (s) => s.bio)` is a `TextColumn` when `bio` is a `String` and a `ColumnType<String?>` when it is a `String?`. `$.updatedAt(...)` is always nullable, since a freshly inserted row has not been updated yet.

## Indexes

Indexes are defined in a callback passed as the third argument to `table()`. Use `index()` for a regular index and `uniqueIndex()` for a unique index. Both take a name and then call `.on()` with the column(s) to index:

```dart
final posts = table('posts', PostTable.new, (t) {
  index('posts_title_index').on(t.title);
  uniqueIndex('posts_slug_unique').on(t.slug);
});
```

Composite indexes list multiple columns in `.on()`:

```dart
final posts = table('posts', PostTable.new, (t) {
  index('posts_author_created_index').on(t.authorId, t.createdAt);
});
```

## Naming Conventions

- Table name: snake_case, plural (`tasks`, `user_profiles`, `blog_posts`)
- Dart class: PascalCase, singular (`TaskTable`, `UserProfileTable`, `BlogPostTable`)
- Row type: PascalCase, singular (`Task`, `UserProfile`, `BlogPost`)
- Column names: snake_case

## Complete Example

```dart
import 'package:my_app/src/ids.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class Post {
  const Post({
    required this.id,
    required this.title,
    required this.body,
    this.publishedAt,
    required this.viewCount,
    required this.createdAt,
    this.updatedAt,
  });

  final PostsId id;
  final String title;
  final String body;
  final DateTime? publishedAt;  // nullable — not published yet
  final int viewCount;
  final DateTime createdAt;
  final DateTime? updatedAt;
}

final class PostTable extends Table<Post> {
  PostTable(super.$)
    : id = $.id('id', (s) => s.id, fromString: PostsId.new, generate: PostsId.generate),
      title = $.text('title', (s) => s.title),
      body = $.text('body', (s) => s.body),
      publishedAt = $.dateTime('published_at', (s) => s.publishedAt),
      viewCount = $.integer('view_count', (s) => s.viewCount),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      updatedAt = $.updatedAt('updated_at', (s) => s.updatedAt);

  @override
  Post fromRow(RowReader read) => Post(
    id: read(id),
    title: read(title),
    body: read(body),
    publishedAt: read(publishedAt),
    viewCount: read(viewCount),
    createdAt: read(createdAt),
    updatedAt: read(updatedAt),
  );

  final IdColumn<PostsId> id;
  final TextColumn title;
  final TextColumn body;
  final ColumnType<DateTime?> publishedAt;
  final IntColumn viewCount;
  final DateTimeColumn createdAt;
  final ColumnType<DateTime?> updatedAt;
}

final posts = table('posts', PostTable.new, (t) {
  index('posts_title_index').on(t.title);
});
```
