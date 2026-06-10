---
title: Defining Tables
description: How to define database tables and columns using Dart schema files.
---

Schemas define the structure of your database. They are Dart files in `lib/src/schemas/` that describe tables and their columns. When you change a schema file, Zonai generates the SQL migration to keep the database in sync.

## The table() Function

`table('table_name', TableClass.new)` registers a table with Zonai. The first argument is the table name as it appears in the database (snake_case, plural). The second is the constructor of the Dart class that defines the columns. The return value is a table reference used in rules, operations, extensions, and rate limits.

## Typed IDs

Every table uses a typed ID class extending `Id`. This prevents accidentally passing a `tasks` ID where a `users` ID is expected:

```dart
class TasksId extends Id {
  const TasksId(super.value);
  factory TasksId.generate() => TasksId(Id.generate('tk'));  // 'tk' is a short suffix
}
```

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
| `$.updatedAt(...)` | `DateTime` | INTEGER NOT NULL (auto-updated) |

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
import 'package:zonai_schema/zonai_schema.dart';

final class Post {
  const Post({
    required this.id,
    required this.title,
    required this.body,
    this.publishedAt,
    required this.viewCount,
    required this.createdAt,
    required this.updatedAt,
  });

  final PostsId id;
  final String title;
  final String body;
  final DateTime? publishedAt;  // nullable — not published yet
  final int viewCount;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class PostsId extends Id {
  const PostsId(super.value);
  factory PostsId.generate() => PostsId(Id.generate('po'));
}

final class PostTable extends Table<Post> {
  PostTable(super.$)
    : id = $.id('id', (s) => s.id, fromString: PostsId.new, generate: PostsId.generate),
      title = $.text('title', (s) => s.title),
      body = $.text('body', (s) => s.body),
      publishedAt = $.dateTime('published_at', (s) => s.publishedAt, isNullable: true),
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
  final DateTimeColumn? publishedAt;
  final IntegerColumn viewCount;
  final CreatedAtColumn createdAt;
  final UpdatedAtColumn updatedAt;
}

final posts = table('posts', PostTable.new, (t) {
  index('posts_title_index').on(t.title);
});
```
