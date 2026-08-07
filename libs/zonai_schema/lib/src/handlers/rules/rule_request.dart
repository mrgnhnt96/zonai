import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/types/supported_auths.dart';
import 'package:zonai_schema/src/update/update.dart';

sealed class RuleRequest extends Request {
  const RuleRequest({
    required super.path,
    required super.id,
    required super.jwt,
  });

  factory RuleRequest.fromRequest(UnknownRequest request) {
    switch (request.path) {
      case TableRulesRequest._path:
        return TableRulesRequest.fromRequest(request);
      case RowRulesRequest._path:
        return RowRulesRequest.fromRequest(request);
      case BatchRowRulesRequest._path:
        return BatchRowRulesRequest.fromRequest(request);
      case AuthTableRulesRequest._path:
        return AuthTableRulesRequest.fromRequest(request);
      case AuthRowRulesRequest._path:
        return AuthRowRulesRequest.fromRequest(request);
      case GetAllTableCollectionActionsRequest._path:
        return GetAllTableCollectionActionsRequest.fromRequest(request);
      default:
        throw ArgumentError('Invalid rule request path: ${request.path}');
    }
  }
}

final class AuthTableRulesRequest extends RuleRequest {
  AuthTableRulesRequest({
    required this.table,
    required this.authType,
    required super.jwt,
  }) : super(path: _path, id: Request.generateId());

  AuthTableRulesRequest._({
    required super.id,
    required this.table,
    required this.authType,
    required super.jwt,
  }) : super(path: _path);

  factory AuthTableRulesRequest.fromRequest(UnknownRequest request) {
    return AuthTableRulesRequest._(
      id: request.id,
      table: request.payload['table'] as String,
      authType: AuthType.values.byName(request.payload['authType'] as String),
      jwt: request.jwt,
    );
  }

  static const _path = '${Request.prefix}.table.auth.can_authenticate';

  final String table;
  final AuthType authType;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'table': table, 'authType': authType.name};
  }

  @override
  String toString() {
    return 'CanAuthenticateRequest(table: $table, authType: $authType)';
  }
}

final class AuthRowRulesRequest extends RuleRequest {
  AuthRowRulesRequest({
    required this.table,
    required this.authType,
    required this.operation,
    required super.jwt,
  }) : super(path: _path, id: Request.generateId());

  AuthRowRulesRequest._({
    required super.id,
    required this.table,
    required this.authType,
    required this.operation,
    required super.jwt,
  }) : super(path: _path);

  factory AuthRowRulesRequest.fromRequest(UnknownRequest request) {
    return AuthRowRulesRequest._(
      id: request.id,
      table: request.payload['table'] as String,
      authType: AuthType.values.byName(request.payload['authType'] as String),
      operation: AuthOperation.values.byName(
        request.payload['operation'] as String,
      ),
      jwt: request.jwt,
    );
  }

  static const _path = '${Request.prefix}.row.auth.can_authenticate';

  final String table;
  final AuthType authType;
  final AuthOperation operation;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'table': table,
      'authType': authType.name,
      'operation': operation.name,
    };
  }

  @override
  String toString() {
    return 'AuthRowRulesRequest(table: $table, authType: $authType)';
  }
}

final class TableRulesRequest extends RuleRequest {
  TableRulesRequest({
    required this.table,
    required this.operation,
    required super.jwt,
  }) : super(path: _path, id: Request.generateId());

  TableRulesRequest._({
    required super.id,
    required this.table,
    required this.operation,
    required super.jwt,
  }) : super(path: _path);

  factory TableRulesRequest.fromRequest(UnknownRequest request) {
    return TableRulesRequest._(
      id: request.id,
      table: request.payload['table'] as String,
      operation: request.payload['operation'] as String,
      jwt: request.jwt,
    );
  }

  static const _path = '${Request.prefix}.table.can_access';

  final String table;
  final String operation;

  TableOperation? get classicOperation => .fromString(operation);

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'table': table, 'operation': operation};
  }
}

// TODO(future): this and BatchRowRulesRequest below gained an `updates`
// field (issue #23) without bumping `IpcCodec.version` — the protocol stamp
// only guards the outer framing/codec, not individual request shapes, so a
// stale worker/host pairing across this change fails with a raw decode
// error rather than the friendly WorkerProtocolMismatchException. Still an
// open question (raised, not yet resolved) whether wire-shape changes like
// this one should force a stamp bump too.
final class RowRulesRequest extends RuleRequest {
  RowRulesRequest({
    required this.table,
    required this.operation,
    required this.data,
    this.updates = const [],
    required super.jwt,
  }) : super(path: _path, id: Request.generateId());

  RowRulesRequest._({
    required super.id,
    required this.table,
    required this.operation,
    required this.data,
    required this.updates,
    required super.jwt,
  }) : super(path: _path);

  factory RowRulesRequest.fromRequest(UnknownRequest request) {
    return RowRulesRequest._(
      id: request.id,
      table: request.payload['table'] as String,
      operation: RowOperation.fromString(
        request.payload['operation'] as String,
      )!,
      data: request.payload['data'] as Map<String, dynamic>,
      updates: [
        for (final u in request.payload['updates'] as List? ?? const [])
          Update.fromJson(Map<String, dynamic>.from(u as Map)),
      ],
      jwt: request.jwt,
    );
  }

  static const _path = '${Request.prefix}.row.can_access';

  final String table;
  final RowOperation operation;
  final Map<String, dynamic> data;

  /// The pending update payload, present only for [RowOperation.update] —
  /// used to simulate the post-write row for [BaseRowRules.canUpdate].
  final List<Update> updates;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'table': table,
      'operation': operation.name,
      'data': data,
      'updates': [for (final u in updates) u.toJson()],
    };
  }
}

/// Checks row access for many rows in one worker round-trip.
///
/// List/stream paths previously issued one [RowRulesRequest] per row, which
/// serializes ~N JSON IPC hops through a single rules worker pipe. Batching
/// collapses that to one request so throughput scales with SQL, not pipe RTT.
final class BatchRowRulesRequest extends RuleRequest {
  BatchRowRulesRequest({
    required this.table,
    required this.operation,
    required this.rows,
    this.updates = const [],
    required super.jwt,
  }) : super(path: _path, id: Request.generateId());

  BatchRowRulesRequest._({
    required super.id,
    required this.table,
    required this.operation,
    required this.rows,
    required this.updates,
    required super.jwt,
  }) : super(path: _path);

  factory BatchRowRulesRequest.fromRequest(UnknownRequest request) {
    final rawRows = request.payload['rows'] as List? ?? const [];
    return BatchRowRulesRequest._(
      id: request.id,
      table: request.payload['table'] as String,
      operation: RowOperation.fromString(
        request.payload['operation'] as String,
      )!,
      rows: [for (final row in rawRows) Map<String, dynamic>.from(row as Map)],
      updates: [
        for (final u in request.payload['updates'] as List? ?? const [])
          Update.fromJson(Map<String, dynamic>.from(u as Map)),
      ],
      jwt: request.jwt,
    );
  }

  static const _path = '${Request.prefix}.row.can_access_batch';

  final String table;
  final RowOperation operation;
  final List<Map<String, dynamic>> rows;

  /// The pending update payload, shared across every row in [rows] — one
  /// `UPDATE ... SET` clause applies uniformly to every matched row.
  /// Present only for [RowOperation.update].
  final List<Update> updates;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'table': table,
      'operation': operation.name,
      'rows': rows,
      'updates': [for (final u in updates) u.toJson()],
    };
  }
}

enum AuthOperation { signIn, signUp, passwordReset }

enum TableOperation {
  create,
  update,
  delete,
  view,
  list,
  count;

  const TableOperation();

  static TableOperation? fromString(String operation) {
    for (final value in values) {
      if (value.name == operation) {
        return value;
      }
    }
    return null;
  }

  RowOperation get rowOperation => switch (this) {
    .create => .create,
    .update => .update,
    .delete => .delete,
    .view => .view,
    .list => .view,
    .count => .view,
  };

  bool get requireObject => switch (this) {
    .create => true,
    .update => true,
    .delete => true,
    .view => false,
    .list => false,
    .count => false,
  };

  @override
  String toString() {
    return name;
  }
}

final class GetAllTableCollectionActionsRequest extends RuleRequest {
  GetAllTableCollectionActionsRequest({super.jwt})
    : super(path: _path, id: Request.generateId());

  GetAllTableCollectionActionsRequest._({required super.id, super.jwt})
    : super(path: _path);

  factory GetAllTableCollectionActionsRequest.fromRequest(
    UnknownRequest request,
  ) {
    return GetAllTableCollectionActionsRequest._(
      id: request.id,
      jwt: request.jwt,
    );
  }

  static const _path = '${Request.prefix}.table.collection_actions';
}

enum RowOperation {
  view,
  create,
  update,
  delete;

  const RowOperation();

  static RowOperation? fromString(String operation) {
    for (final value in values) {
      if (value.name == operation) {
        return value;
      }
    }

    return null;
  }

  @override
  String toString() {
    return name;
  }
}
