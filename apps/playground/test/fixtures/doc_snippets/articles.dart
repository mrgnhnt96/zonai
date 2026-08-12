// Stand-in for the `articles` table the docs invent. See tasks.dart for why
// these fixtures exist and when to extend them.
import 'package:zonai_schema/zonai_schema.dart';

import 'ids.dart';

final class Article {
  const Article({required this.id, required this.title, required this.body});

  final ArticlesId id;
  final String title;
  final String body;
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
