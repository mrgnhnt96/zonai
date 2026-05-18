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

  Never _failAuthCollectionRules(
    String collection,
    _Rules? bucket,
    BaseCollectionRules? collectionRules,
  ) {
    final registered = rulesByTable.keys.toList()..sort();
    final buf = StringBuffer(
      'Auth collection rules request for "$collection" could not be handled.\n',
    );
    if (bucket == null) {
      buf
        ..writeln(
          'No rules are registered for table name "$collection". '
          'The rules list may be missing this collection (e.g. loadRule failed, '
          'or main() did not return Rules).',
        )
        ..writeln(
          'Registered table names: '
          '${registered.isEmpty ? '(none)' : registered.join(', ')}.',
        );
    } else if (collectionRules == null) {
      buf.writeln(
        'Rules exist for "$collection" but there are no collection-level rules '
        '(only record rules may be registered).',
      );
    } else {
      buf
        ..writeln(
          'Expected AuthCollectionRules for "$collection", but collection rules '
          'are ${collectionRules.runtimeType} '
          '(schema: ${collectionRules.schema.runtimeType}).',
        )
        ..writeln(
          'If you recently added both CollectionRules and AuthCollectionRules '
          'for the same table, note that the last registration wins when '
          'building the rules map.',
        );
    }
    final message = buf.toString().trim();
    logger.error(message);
    throw StateError(message);
  }

  Never _failAuthRecordRules(
    String collection,
    _Rules? bucket,
    BaseRecordRules? recordRules,
  ) {
    final registered = rulesByTable.keys.toList()..sort();
    final buf = StringBuffer(
      'Auth record rules request for "$collection" could not be handled.\n',
    );
    if (bucket == null) {
      buf
        ..writeln(
          'No rules are registered for table name "$collection". '
          'The rules list may be missing this collection (e.g. loadRule failed, '
          'or main() did not return Rules).',
        )
        ..writeln(
          'Registered table names: '
          '${registered.isEmpty ? '(none)' : registered.join(', ')}.',
        );
    } else if (recordRules == null) {
      buf.writeln(
        'Rules exist for "$collection" but there are no record-level rules.',
      );
    } else {
      buf
        ..writeln(
          'Expected AuthRecordRules for "$collection", but record rules are '
          '${recordRules.runtimeType} '
          '(schema: ${recordRules.schema.runtimeType}).',
        )
        ..writeln(
          'If you recently added both RecordRules and AuthRecordRules for the '
          'same table, note that the last registration wins when building the '
          'rules map.',
        );
    }
    final message = buf.toString().trim();
    logger.error(message);
    throw StateError(message);
  }

  Future<AuthCollectionRulesResponse> _authCollectionRules(
    AuthCollectionRulesRequest request,
  ) async {
    final bucket = rulesByTable[request.collection];
    final collectionRules = bucket?.collection;
    if (collectionRules is AuthCollectionRules) {
      return AuthCollectionRulesResponse(
        id: request.id,
        collection: request.collection,
        canAuthenticate: await collectionRules.canAuthenticate(
          request.jwt,
          request.authType,
        ),
        authType: request.authType,
      );
    }

    _failAuthCollectionRules(request.collection, bucket, collectionRules);
  }

  Future<AuthRecordRulesResponse> _authRecordRules(
    AuthRecordRulesRequest request,
  ) async {
    final bucket = rulesByTable[request.collection];
    final recordRules = bucket?.record;
    if (recordRules is AuthRecordRules) {
      return AuthRecordRulesResponse(
        id: request.id,
        collection: request.collection,
        canAccess: switch (request.operation) {
          .signIn => await recordRules.canSignIn(request.jwt, request.authType),
          .signUp => await recordRules.canSignUp(request.jwt, request.authType),
        },
        authType: request.authType,
        operation: request.operation,
      );
    }

    _failAuthRecordRules(request.collection, bucket, recordRules);
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
