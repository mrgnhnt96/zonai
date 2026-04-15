import 'package:raindrop/raindrop.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/handlers/rules/rule_requests.dart';
import 'package:zonai_schema/src/handlers/rules/rule_responses.dart';
import 'package:zonai_schema/src/request.dart' as auth;
import 'package:zonai_schema/src/rules.dart';
import 'package:zonai_schema/src/user.dart';

class DbRules {
  const DbRules({required this.rules});

  final List<Rules> rules;

  void start() {
    MessageHandler(
      onMessage: (UnknownRequest msg) async {
        return switch (RuleRequest.fromRequest(msg)) {
          final CanAccessRequest request => _canAccess(request),
        };
      },
    ).listen();
  }

  Future<CanAccessResponse> _canAccess(CanAccessRequest request) async {
    final op = request.classicOperation;
    if (op == null) {
      return CanAccessResponse(
        id: request.id,
        collection: request.collection,
        operation: request.operation,
        canAccess: false,
      );
    }

    final authRequest = auth.Request(
      user: User(isSuperUser: request.isSuperUser),
    );

    for (final rule in rules) {
      final table = Table.get(rule.schema as Schema);
      if (table == null || table.name != request.collection) continue;

      final canAccess = await switch (op) {
        .create => rule.canCreate(authRequest),
        .update => rule.canUpdate(authRequest),
        .delete => rule.canDelete(authRequest),
        .view => rule.canView(authRequest),
        .list => rule.canListOrSearch(authRequest),
        .search => rule.canListOrSearch(authRequest),
      };

      return CanAccessResponse(
        id: request.id,
        collection: request.collection,
        operation: request.operation,
        canAccess: canAccess,
      );
    }

    return CanAccessResponse(
      id: request.id,
      collection: request.collection,
      operation: request.operation,
      canAccess: false,
    );
  }
}
