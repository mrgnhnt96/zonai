// Stand-in for the `articles` table the docs invent. See tasks.dart for why
// these fixtures exist and when to extend them.
import 'package:zonai_schema/zonai_schema.dart';

final class Article {
  const Article({required this.id, required this.title, required this.body});

  final ArticlesId id;
  final String title;
  final String body;
}

final class ArticlesId implements Id {
  const ArticlesId(this.value);

  factory ArticlesId.generate() => ArticlesId(Id.generate('ar'));

  @override
  final String value;

  @override
  bool operator ==(Object other) => other is Id && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

final class ArticleTable extends Table<Article> {
  ArticleTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: ArticlesId.new,
        generate: ArticlesId.generate,
      ),
      title = $.text('title', (s) => s.title),
      body = $.text('body', (s) => s.body);

  @override
  Article fromRow(RowReader read) =>
      Article(id: read(id), title: read(title), body: read(body));

  final IdColumn<ArticlesId> id;
  final TextColumn title;
  final TextColumn body;
}

final articles = table('articles', ArticleTable.new);
