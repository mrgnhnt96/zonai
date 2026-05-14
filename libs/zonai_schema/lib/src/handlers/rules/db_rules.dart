import 'package:raindrop/raindrop.dart';
import 'package:raindrop_sqlite/raindrop_sqlite.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/handlers/rules/rule_request.dart';
import 'package:zonai_schema/src/handlers/rules/rule_response.dart';
import 'package:zonai_schema/src/rules/rules.dart';
import 'package:zonai_schema/src/table_extensions.dart';

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
          logger.debug(
            'Error handling request',
            properties: {'request': msg.toJson(), 'error': e.toString()},
          );
          return MessageErrorResponse(
            id: msg.id,
            message: 'Error handling request',
            error: e.toString(),
            stackTrace: stack.toString(),
          );
        }

        switch (request) {
          case final CollectionRulesRequest request:
            return await _collectionRules(request);
          case final RecordRulesRequest request:
            return await _recordRules(request);
          case final AuthCollectionRulesRequest request:
            return await _authCollectionRules(request);
          case final AuthRecordRulesRequest request:
            return await _authRecordRules(request);
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

  Future<CollectionRulesResponse> _collectionRules(
    CollectionRulesRequest request,
  ) async {
    final rules = rulesByTable[request.collection];
    final collectionRules = rules?.collection;

    // TODO(future): We can support custom operations by forwarding
    // the request operation to the rules
    final op = request.classicOperation;
    if (op == null) {
      return CollectionRulesResponse(
        id: request.id,
        collection: request.collection,
        operation: request.operation,
        canAccess: false,
      );
    }

    if (collectionRules == null) {
      logger.warn('No rules found for collection: ${request.collection}');
      return CollectionRulesResponse(
        id: request.id,
        collection: request.collection,
        operation: request.operation,
        canAccess: false,
      );
    }

    logger.info(
      '[RULES]: ${op.name} | ${collectionRules.schema.runtimeType} (Auth? ${collectionRules is AuthCollectionRules})',
    );

    if (op == .create && collectionRules is AuthCollectionRules) {
      throw StateError('Cannot create auth records, use the auth API instead');
    }

    final canAccess = await switch (op) {
      .create => collectionRules.canCreate(request.jwt),
      .update => collectionRules.canUpdate(request.jwt),
      .delete => collectionRules.canDelete(request.jwt),
      .view => collectionRules.canView(request.jwt),
      .list => collectionRules.canList(request.jwt),
    };

    return CollectionRulesResponse(
      id: request.id,
      collection: request.collection,
      operation: request.operation,
      canAccess: canAccess,
    );
  }

  Future<AuthCollectionRulesResponse> _authCollectionRules(
    AuthCollectionRulesRequest request,
  ) async {
    final rules = rulesByTable[request.collection];
    final collectionRules = rules?.collection;
    if (collectionRules case AuthCollectionRules(:final canAuthenticate)) {
      return AuthCollectionRulesResponse(
        id: request.id,
        collection: request.collection,
        canAuthenticate: await canAuthenticate(request.jwt, request.authType),
        authType: request.authType,
      );
    }

    throw StateError(
      'Cannot authenticate for collection: ${request.collection}',
    );
  }

  Future<AuthRecordRulesResponse> _authRecordRules(
    AuthRecordRulesRequest request,
  ) async {
    final rules = rulesByTable[request.collection];
    final recordRules = rules?.record;
    if (recordRules case AuthRecordRules(:final canSignIn, :final canSignUp)) {
      return AuthRecordRulesResponse(
        id: request.id,
        collection: request.collection,
        canAccess: switch (request.operation) {
          .signIn => await canSignIn(request.jwt, request.authType),
          .signUp => await canSignUp(request.jwt, request.authType),
        },
        authType: request.authType,
        operation: request.operation,
      );
    }

    throw StateError(
      'Cannot authenticate for collection: ${request.collection}',
    );
  }

  Future<RecordRulesResponse> _recordRules(RecordRulesRequest request) async {
    final rules = rulesByTable[request.collection];
    final recordRules = rules?.record;

    final op = request.operation;
    if (recordRules == null) {
      logger.warn('No rules found for record: ${request.collection}');
      return RecordRulesResponse(
        id: request.id,
        collection: request.collection,
        operation: request.operation,
        canPerform: false,
      );
    }

    if (recordRules case AuthRecordRules() when op == .create) {
      throw StateError('Cannot create auth records, use the auth API instead');
    }

    final object = recordRules.table.safeCreate(request.data);

    final canPerform = await switch (op) {
      .view => recordRules.canView(request.jwt, object),
      .update => recordRules.canUpdate(request.jwt, object),
      .delete => recordRules.canDelete(request.jwt, object),
      .create => recordRules.canCreate(request.jwt, object),
    };

    return RecordRulesResponse(
      id: request.id,
      collection: request.collection,
      operation: request.operation,
      canPerform: canPerform,
    );
  }
}
