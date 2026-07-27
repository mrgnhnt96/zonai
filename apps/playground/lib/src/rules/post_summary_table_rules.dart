import 'package:zonai_schema/zonai_schema.dart';

import '../operations/post_summary_operations.dart';

PostSummaryTableRules main() => PostSummaryTableRules();

final class PostSummaryTableRules
    extends ViewTableRules<PostSummaryTable, PostSummary> {
  PostSummaryTableRules() : super(postSummary);

  @override
  Future<bool> canView(Jwt? jwt) async => true;

  @override
  Future<bool> canList(Jwt? jwt) async => true;
}
