import 'package:raindrop/raindrop.dart';
import 'package:raindrop_sqlite/raindrop_sqlite.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/handlers/rules/rule_request.dart';
import 'package:zonai_schema/src/handlers/rules/rule_response.dart';
import 'package:zonai_schema/src/rules/rules.dart';
import 'package:zonai_schema/src/table_extensions.dart';
import 'package:zonai_schema/src/types/request.dart' as auth;
import 'package:zonai_schema/src/types/user.dart';

class _Rules {
  _Rules();

  BaseCollectionRules? collection;
  BaseRecordRules? record;
}

class DbRules {
  DbRules({required this.rules, this.dialect = const SQLiteDialect()});

  final List<Rules> rules;
  final BaseSqlDialect dialect;

  void start() {
    MessageHandler(
      onMessage: (UnknownRequest msg) async {
        RuleRequest request;
        try {
          request = RuleRequest.fromRequest(msg);
        } catch (e, stack) {
          logger.error(
            'Error handling rule request',
            error: '$e',
            stackTrace: stack.toString(),
            properties: {'request': msg.toJson()},
          );
          return MessageErrorResponse(
            id: msg.id,
            message: 'Error handling rule request',
            error: e.toString(),
            stackTrace: stack.toString(),
          );
        }

        switch (request) {
          case final CollectionRulesRequest request:
            return await _collectionRules(request);
          case final RecordRulesRequest request:
            return await _recordRules(request);
          case final CanAuthenticateRequest request:
            return await _canAuthenticate(request);
        }
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
        case final AuthCollectionRules rule:
          r.collection = rule;

        case final RecordRules rule:
          r.record = rule;
        case final AuthRecordRules rule:
          r.record = rule;
      }
    }

    return _rulesByTable = rules;
  }

  Future<CanAccessResponse> _collectionRules(
    CollectionRulesRequest request,
  ) async {
    final authRequest = auth.Request(
      user: User.fake(isSuperUser: request.isSuperUser),
    );

    final rules = rulesByTable[request.collection];
    final collectionRules = rules?.collection;

    // TODO(future): We can support custom operations by forwarding
    // the request operation to the rules
    final op = request.classicOperation;
    if (op == null) {
      return CanAccessResponse(
        id: request.id,
        collection: request.collection,
        operation: request.operation,
        canAccess: request.isSuperUser,
      );
    }

    if (collectionRules == null) {
      logger.warn('No rules found for collection: ${request.collection}');
      return CanAccessResponse(
        id: request.id,
        collection: request.collection,
        operation: request.operation,
        canAccess: request.isSuperUser,
      );
    }

    logger.info(
      '[RULES]: ${op.name} | ${collectionRules.schema.runtimeType} (Auth? ${collectionRules is AuthCollectionRules})',
    );

    if (op == .create && collectionRules is AuthCollectionRules) {
      if (request.isSuperUser) {
        return CanAccessResponse(
          id: request.id,
          collection: request.collection,
          operation: request.operation,
          canAccess: true,
        );
      }

      throw StateError('Cannot create auth records, use the auth API instead');
    }

    final canAccess = await switch (op) {
      .create => collectionRules.canCreate(authRequest),
      .update => collectionRules.canUpdate(authRequest),
      .delete => collectionRules.canDelete(authRequest),
      .view => collectionRules.canView(authRequest),
      .list => collectionRules.canList(authRequest),
    };

    return CanAccessResponse(
      id: request.id,
      collection: request.collection,
      operation: request.operation,
      canAccess: canAccess,
    );
  }

  Future<CanAuthenticateResponse> _canAuthenticate(
    CanAuthenticateRequest request,
  ) async {
    final rules = rulesByTable[request.collection];
    final collectionRules = rules?.collection;
    if (collectionRules case AuthCollectionRules(:final canAuthenticate)) {
      return CanAuthenticateResponse(
        id: request.id,
        collection: request.collection,
        canAuthenticate: await canAuthenticate(request.authType),
        authType: request.authType,
      );
    }

    throw StateError(
      'Cannot authenticate for collection: ${request.collection}',
    );
  }

  Future<RecordFilterResponse> _recordRules(RecordRulesRequest request) async {
    final authRequest = auth.Request(
      user: User.fake(isSuperUser: request.isSuperUser),
    );

    final rules = rulesByTable[request.collection];
    final recordRules = rules?.record;

    final op = request.operation;
    if (recordRules == null) {
      logger.warn('No rules found for record: ${request.collection}');
      return RecordFilterResponse(
        id: request.id,
        collection: request.collection,
        operation: request.operation,
        canPerform: authRequest.user.isSuperUser,
      );
    }

    if (recordRules case AuthRecordRules() when op == .create) {
      if (request.isSuperUser) {
        return RecordFilterResponse(
          id: request.id,
          collection: request.collection,
          operation: request.operation,
          canPerform: true,
        );
      }

      throw StateError('Cannot create auth records, use the auth API instead');
    }

    final object = recordRules.table.safeCreate(request.data);

    final canPerform = await switch (op) {
      .view => recordRules.canView(authRequest, object),
      .update => recordRules.canUpdate(authRequest, object),
      .delete => recordRules.canDelete(authRequest, object),
      .create => recordRules.canCreate(authRequest, object),
    };

    return RecordFilterResponse(
      id: request.id,
      collection: request.collection,
      operation: request.operation,
      canPerform: canPerform,
    );
  }
}
