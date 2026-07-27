import 'package:zonai_schema/zonai_schema.dart';

import '../views/post_summary.dart';

PostSummaryRowRules main() => PostSummaryRowRules();

final class PostSummaryRowRules
    extends ViewRowRules<PostSummaryTable, PostSummary> {
  PostSummaryRowRules() : super(postSummary);

  @override
  Future<bool> canView(Jwt? jwt, PostSummary row) async => true;
}
