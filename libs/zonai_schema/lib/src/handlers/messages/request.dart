part of 'message_handler.dart';

abstract base class Request {
  const Request({required this.path, required this.id, this.jwt});

  factory Request.fromJson(Map<String, dynamic> json) {
    final path = json['path'];
    if (path == null) {
      throw ArgumentError('Invalid request path: ${json['path']}');
    }

    if (!path.startsWith(prefix)) {
      throw ArgumentError(
        'Invalid request path: $path, should start with $prefix',
      );
    }

    final id = json['id'];
    if (id == null) {
      throw ArgumentError('Invalid request id: ${json['id']}');
    }

    return switch (path) {
      RequestPing._path => RequestPing.fromJson(json),
      RequestKill._path => RequestKill.fromJson(json),
      GetRecordRequest._path => GetRecordRequest.fromJson(json),
      CreateRecordRequest._path => CreateRecordRequest.fromJson(json),
      DeleteRecordRequest._path => DeleteRecordRequest.fromJson(json),
      PurgeRecordsRequest._path => PurgeRecordsRequest.fromJson(json),
      UpdateRecordRequest._path => UpdateRecordRequest.fromJson(json),
      SendEmailRequest._path => SendEmailRequest.fromJson(json),
      SendBuiltInEmailRequest._path => SendBuiltInEmailRequest.fromJson(json),
      NativeLibraryRequest._path => NativeLibraryRequest.fromJson(json),
      _ when path.startsWith(CronRequest.prefix) => CronRequest.fromJson(json),
      _ => UnknownRequest(
        path: path,
        id: id,
        payload: json,
        jwt: Jwt.maybeFromJson(json['jwt']),
      ),
    };
  }

  static const prefix = 'request/';

  static int _generateSeq = 0;

  /// Generates a unique ID for a request: time + seq + entropy (avoids same-ms collisions).
  static String generateId() {
    final t = DateTime.now().microsecondsSinceEpoch;
    final seq = _generateSeq = (_generateSeq + 1) & 0x3fffffff;
    final r = Random.secure().nextInt(0x40000000);
    return sha256
        .convert(utf8.encode('$t:$seq:$r'))
        .toString()
        .substring(0, 16);
  }

  final String path;
  final String id;
  final Jwt? jwt;

  @mustCallSuper
  Map<String, dynamic> toJson() {
    return {'path': path, 'id': id, 'jwt': ?jwt?.toJson()};
  }
}

final class UnknownRequest extends Request {
  UnknownRequest({
    required this.payload,
    required super.path,
    required super.id,
    super.jwt,
  });

  final Map<String, dynamic> payload;
}

final class RequestPing extends Request {
  RequestPing() : super(path: _path, id: Request.generateId());
  RequestPing._({required super.id}) : super(path: _path);

  factory RequestPing.fromJson(Map<String, dynamic> json) {
    return RequestPing._(id: json['id'] as String);
  }

  static const _path = '${Request.prefix}.ping';

  @override
  String get path => _path;
}

final class RequestKill extends Request {
  RequestKill() : super(path: _path, id: Request.generateId());

  factory RequestKill.fromJson(Map<String, dynamic> json) {
    return RequestKill();
  }

  static const _path = '${Request.prefix}.kill';

  @override
  String get path => _path;
}

final class GetRecordRequest extends Request {
  GetRecordRequest({
    required this.table,
    required this.where,
    this.limit,
    this.offset,
    super.jwt,
  }) : super(path: _path, id: Request.generateId());

  GetRecordRequest._({
    required super.id,
    required this.table,
    required this.where,
    this.limit,
    this.offset,
    super.jwt,
  }) : super(path: _path);

  factory GetRecordRequest.fromJson(Map<String, dynamic> json) {
    return GetRecordRequest._(
      id: json['id'] as String,
      table: json['table'] as String,
      where: Where.fromJson(json['where'] as Map<String, dynamic>),
      limit: json['limit'] as int?,
      offset: json['offset'] as int?,
      jwt: Jwt.maybeFromJson(json['jwt']),
    );
  }

  static const _path = '${Request.prefix}.get_record';

  final String table;
  final Where where;
  final int? limit;
  final int? offset;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'table': table,
      'where': where.toJson(),
      'limit': limit,
      'offset': offset,
    };
  }
}

/// Which embedded native library a worker is asking its spawner to
/// confirm/refresh on disk (see [NativeLibraryRequest]).
enum NativeLibraryKind { resqlite, argon2 }

/// Sent by a worker process up to whatever spawned it (the `zonai serve`
/// process, or a `zonai` process running a command directly), asking it to
/// ensure its own embedded copy of [library] is extracted to the shared
/// on-disk install path and to report that path back.
///
/// A worker executable is `dart compile exe --target-os X --target-arch Y`
/// compiled locally, which can cross-compile the executable format fine but
/// leaves the embedded native-library byte-array constants unaffected --
/// baked in by *this* host, not necessarily a match for wherever the
/// resulting binary actually runs. The spawner, by construction, is always
/// running natively on the machine both processes are on right now, so its
/// own embedded copy is guaranteed correct where the worker's might not be.
final class NativeLibraryRequest extends Request {
  NativeLibraryRequest({required this.library, super.jwt})
    : super(path: _path, id: Request.generateId());

  NativeLibraryRequest._({required super.id, required this.library, super.jwt})
    : super(path: _path);

  factory NativeLibraryRequest.fromJson(Map<String, dynamic> json) {
    return NativeLibraryRequest._(
      id: json['id'] as String,
      library: NativeLibraryKind.values.byName(json['library'] as String),
      jwt: Jwt.maybeFromJson(json['jwt']),
    );
  }

  static const _path = '${Request.prefix}.native_library';

  final NativeLibraryKind library;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'library': library.name};
  }
}

sealed class MutationRequest extends Request {
  const MutationRequest({
    required super.path,
    required super.id,
    required this.parent,
    required this.table,
    super.jwt,
  });

  final Request parent;
  final String table;

  @override
  @mustCallSuper
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'parent': parent.toJson(), 'table': table};
  }
}

final class DeleteRecordRequest extends MutationRequest {
  DeleteRecordRequest({
    required super.table,
    required this.where,
    required super.parent,
    this.limit,
    super.jwt,
  }) : super(path: _path, id: Request.generateId());

  DeleteRecordRequest._({
    required super.id,
    required super.table,
    required this.where,
    required super.parent,
    this.limit,
    super.jwt,
  }) : super(path: _path);

  factory DeleteRecordRequest.fromJson(Map<String, dynamic> json) {
    return DeleteRecordRequest._(
      id: json['id'] as String,
      parent: Request.fromJson(json['parent'] as Map<String, dynamic>),
      table: json['table'] as String,
      where: Where.fromJson(json['where'] as Map<String, dynamic>),
      limit: json['limit'] as int?,
      jwt: Jwt.maybeFromJson(json['jwt']),
    );
  }

  static const _path = '${Request.prefix}.delete_record';

  final Where where;
  final int? limit;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'where': where.toJson(), 'limit': limit};
  }
}

/// Bulk removal of rows from one of the framework's own tables, executed by
/// the host as a single `DELETE ... WHERE`.
///
/// Deliberately **not** a [MutationRequest], and the two differences are the
/// whole point:
///
/// * A [MutationRequest] is parked against its parent's id and replayed as a
///   side effect, with `expectResponse: false` — the caller cannot learn what
///   happened, or whether anything happened at all. This is answered directly
///   with a [PurgeRecordsResponse] carrying the row count. Retention that
///   cannot report what it deleted is indistinguishable from retention that
///   never ran, which is precisely how a production `_log` reached 4,164,727
///   rows while its nightly cron reported success (2026-08-13).
/// * [DeleteRecordRequest] reads every matching row into memory, dispatches a
///   row-rules check per row, sanitizes the set and hands it to `before`/
///   `after` extensions. That is correct for author tables and hopeless at
///   retention scale — the read alone is unbounded. A purge skips all of it.
///
/// Skipping row rules is only defensible because of what this may be pointed
/// at: the host restricts [table] to the framework's own internal tables,
/// which carry generated rules rather than author-supplied ones, and requires
/// an admin identity on top ([CronJwt] qualifies). `_photos` is excluded even
/// so — deleting a photo row also deletes a file, and that side effect only
/// exists on the per-row path.
final class PurgeRecordsRequest extends Request {
  PurgeRecordsRequest({required this.table, required this.where, super.jwt})
    : super(path: _path, id: Request.generateId());

  PurgeRecordsRequest._({
    required super.id,
    required this.table,
    required this.where,
    super.jwt,
  }) : super(path: _path);

  factory PurgeRecordsRequest.fromJson(Map<String, dynamic> json) {
    return PurgeRecordsRequest._(
      id: json['id'] as String,
      table: json['table'] as String,
      where: Where.fromJson(json['where'] as Map<String, dynamic>),
      jwt: Jwt.maybeFromJson(json['jwt']),
    );
  }

  static const _path = '${Request.prefix}.purge_records';

  final String table;
  final Where where;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'table': table, 'where': where.toJson()};
  }
}

final class CreateRecordRequest extends MutationRequest {
  CreateRecordRequest({
    required super.table,
    required this.objects,
    required super.parent,
    super.jwt,
  }) : super(path: _path, id: Request.generateId());

  CreateRecordRequest._({
    required super.id,
    required super.table,
    required this.objects,
    required super.parent,
    super.jwt,
  }) : super(path: _path);

  factory CreateRecordRequest.fromJson(Map<String, dynamic> json) {
    return CreateRecordRequest._(
      id: json['id'] as String,
      parent: Request.fromJson(json['parent'] as Map<String, dynamic>),
      table: json['table'] as String,
      objects: [
        for (final o in json['objects'] as List<dynamic>)
          Map<String, dynamic>.from(o as Map),
      ],
      jwt: Jwt.maybeFromJson(json['jwt']),
    );
  }

  static const _path = '${Request.prefix}.create_record';

  final List<Map<String, dynamic>> objects;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'objects': objects};
  }
}

final class UpdateRecordRequest extends MutationRequest {
  UpdateRecordRequest({
    required super.table,
    required this.where,
    required this.updates,
    required super.parent,
    this.limit,
    this.offset,
    super.jwt,
  }) : super(path: _path, id: Request.generateId());

  UpdateRecordRequest._({
    required super.id,
    required super.table,
    required this.where,
    required this.updates,
    required super.parent,
    this.limit,
    this.offset,
    super.jwt,
  }) : super(path: _path);

  factory UpdateRecordRequest.fromJson(Map<String, dynamic> json) {
    return UpdateRecordRequest._(
      id: json['id'] as String,
      parent: Request.fromJson(json['parent'] as Map<String, dynamic>),
      table: json['table'] as String,
      where: Where.fromJson(json['where'] as Map<String, dynamic>),
      updates: [
        for (final update in json['updates'] as List<dynamic>)
          Update.fromJson(update as Map<String, dynamic>),
      ],
      limit: json['limit'] as int?,
      offset: json['offset'] as int?,
      jwt: Jwt.maybeFromJson(json['jwt']),
    );
  }

  static const _path = '${Request.prefix}.update_record';

  final Where where;
  final List<Update> updates;
  final int? limit;
  final int? offset;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'where': where.toJson(),
      'limit': limit,
      'updates': updates.map((update) => update.toJson()).toList(),
      'offset': offset,
    };
  }
}

sealed class SendEmailRequestBase extends Request {
  const SendEmailRequestBase({
    required super.path,
    required super.id,
    super.jwt,
  });

  @override
  @mustCallSuper
  Map<String, dynamic> toJson() {
    return {...super.toJson()};
  }
}

final class SendEmailRequest extends SendEmailRequestBase {
  SendEmailRequest(Email this.email, {super.jwt})
    : super(path: _path, id: Request.generateId());

  SendEmailRequest._({required super.id, required this.email, super.jwt})
    : super(path: _path);

  factory SendEmailRequest.fromJson(Map<String, dynamic> json) {
    return SendEmailRequest._(
      id: json['id'] as String,
      email: Email.fromJson(json['email'] as Map<String, dynamic>),
      jwt: Jwt.maybeFromJson(json['jwt']),
    );
  }

  static const _path = '${Request.prefix}.send_email';

  final Email email;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'email': email.toJson()};
  }
}

final class SendBuiltInEmailRequest extends SendEmailRequestBase {
  SendBuiltInEmailRequest(
    BuiltInEmails this.builtIn, {
    required this.table,
    required this.to,
    this.object,
    this.variables,
    super.jwt,
  }) : super(path: _path, id: Request.generateId());

  SendBuiltInEmailRequest._({
    required super.id,
    required this.builtIn,
    required this.to,
    required this.table,
    this.object,
    this.variables,
    super.jwt,
  }) : super(path: _path);

  factory SendBuiltInEmailRequest.fromJson(Map<String, dynamic> json) {
    return SendBuiltInEmailRequest._(
      id: json['id'] as String,
      builtIn: BuiltInEmails.values.byName(json['builtIn'] as String),
      to: EmailAddress.fromJson(json['to'] as Map<String, dynamic>),
      variables: json['variables'] as Map<String, dynamic>?,
      object: json['object'] as Map<String, dynamic>?,
      table: json['table'] as String,
      jwt: Jwt.maybeFromJson(json['jwt']),
    );
  }
  static const _path = '${Request.prefix}.send_built_in_email';

  final BuiltInEmails builtIn;
  final EmailAddress to;
  final Map<String, dynamic>? variables;
  final String table;

  /// Properties to add to the new auth record when
  /// the user signs up
  final Map<String, dynamic>? object;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'builtIn': builtIn.name,
      'to': to.toJson(),
      'variables': jsonDecode(jsonEncode(variables)),
      'table': table,
      'object': jsonDecode(jsonEncode(object)),
    };
  }
}
