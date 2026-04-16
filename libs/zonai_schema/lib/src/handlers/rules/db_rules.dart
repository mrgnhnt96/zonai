import 'package:raindrop/raindrop.dart';
import 'package:raindrop_sqlite/raindrop_sqlite.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/handlers/rules/rule_requests.dart';
import 'package:zonai_schema/src/handlers/rules/rule_responses.dart';
import 'package:zonai_schema/src/request.dart' as auth;
import 'package:zonai_schema/src/rules/rules.dart';
import 'package:zonai_schema/src/user.dart';

class _Rules {
  _Rules();

  CollectionRules? collection;
  RecordRules? record;
}

class DbRules {
  DbRules({required this.rules, this.dialect = const SQLiteDialect()});

  final List<Rules> rules;
  final BaseSqlDialect dialect;

  void start() {
    MessageHandler(
      onMessage: (UnknownRequest msg) async {
        return switch (RuleRequest.fromRequest(msg)) {
          final CollectionRulesRequest request => _collectionRules(request),
          final RecordRulesRequest request => _recordRules(request),
        };
      },
    ).listen();
  }

  Map<String, _Rules>? _rulesByTable;
  Map<String, _Rules> get rulesByTable {
    if (_rulesByTable case final rules?) return rules;

    final rules = <String, _Rules>{};
    for (final rule in this.rules) {
      final r = rules[rule.table.name] ??= _Rules();

      switch (rule) {
        case final CollectionRules rule:
          r.collection = rule;
        case final RecordRules rule:
          r.record = rule;
      }
    }

    return _rulesByTable = rules;
  }

  Future<CanAccessResponse> _collectionRules(
    CollectionRulesRequest request,
  ) async {
    final authRequest = auth.Request(
      user: User(isSuperUser: request.isSuperUser),
    );

    final rules = rulesByTable[request.collection];
    final collectionRules = rules?.collection;

    // TODO(future): We can support custom operations by forwarding
    // the request operation to the rules
    final op = request.classicOperation;
    if (collectionRules == null || op == null) {
      return CanAccessResponse(
        id: request.id,
        collection: request.collection,
        operation: request.operation,
        canAccess: request.isSuperUser,
      );
    }

    final canAccess = await switch (op) {
      .create => collectionRules.canCreate(authRequest),
      .update => collectionRules.canUpdate(authRequest),
      .delete => collectionRules.canDelete(authRequest),
      .view => collectionRules.canView(authRequest),
      .list => collectionRules.canListOrSearch(authRequest),
      .search => collectionRules.canListOrSearch(authRequest),
    };

    return CanAccessResponse(
      id: request.id,
      collection: request.collection,
      operation: request.operation,
      canAccess: canAccess,
    );
  }

  Future<RecordFilterResponse> _recordRules(RecordRulesRequest request) async {
    final authRequest = auth.Request(
      user: User(isSuperUser: request.isSuperUser),
    );

    final rules = rulesByTable[request.collection];
    final recordRules = rules?.record;

    final op = request.operation;
    if (recordRules == null) {
      return RecordFilterResponse(
        id: request.id,
        collection: request.collection,
        operation: request.operation,
        filter: null,
      );
    }

    final filter = await switch (op) {
      .view => recordRules.canView(authRequest),
      .update => recordRules.canUpdate(authRequest),
      .delete => recordRules.canDelete(authRequest),
    };

    if (filter == null) {
      return RecordFilterResponse(
        id: request.id,
        collection: request.collection,
        operation: request.operation,
        filter: null,
      );
    }

    return RecordFilterResponse(
      id: request.id,
      collection: request.collection,
      operation: request.operation,
      filter: dialect.translateFilter(filter, []),
    );
  }
}
