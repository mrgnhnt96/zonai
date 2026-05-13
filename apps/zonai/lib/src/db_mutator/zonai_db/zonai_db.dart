library zonai_db;

import 'dart:async';

import 'package:file/file.dart';
import 'package:raindrop/raindrop.dart' as raindrop show migrate;
import 'package:raindrop/raindrop.dart' hide migrate;
import 'package:raindrop_sqlite/raindrop_sqlite.dart';
import 'package:zonai/src/domain/app_jwt.dart';
import 'package:zonai/src/internal_collections/jwt_collection.dart';
import 'package:zonai/src/utils/hash_password.dart';
import 'package:zonai/src/utils/jwt.dart';
import 'package:zonai_schema/src/handlers/extensions/extension_request.dart';
import 'package:zonai_schema/src/handlers/extensions/extension_response.dart';
import 'package:zonai_schema/src/handlers/operations/operation_request.dart';
import 'package:zonai_schema/src/handlers/operations/operation_response.dart';
import 'package:zonai_schema/src/handlers/rules/rule_request.dart';
import 'package:zonai_schema/src/handlers/rules/rule_response.dart';
import 'package:zonai_schema/zonai_schema.dart' hide logger;

import '../../deps/extensions.dart';
import '../../deps/fs.dart';
import '../../deps/logger.dart';
import '../../deps/migrate.dart';
import '../../deps/operations.dart';
import '../../deps/rules.dart';
import '../../deps/settings.dart';
import '../../utils/where_sql.dart';
import '../mailman.dart';
import '../operation_result.dart';
import '../payloads/payloads.dart';
import '../sqlite_internal_table_sync.dart';

part 'parts/__auth_utils.dart';
part 'parts/__utils.dart';
part 'parts/auth.dart';
part 'parts/create.dart';
part 'parts/delete.dart';
part 'parts/list.dart';
part 'parts/stream_list.dart';
part 'parts/stream_one.dart';
part 'parts/update.dart';
part 'parts/view.dart';

typedef _Result<T> = (Object? error, T? result);
typedef _CrudResult = _Result<Map<String, Object?>>;
typedef _CrudListResult = _Result<List<Map<String, Object?>>>;

const _prefix = '[ZONAI_DB]';

// TODO(mrgnhnt): Make this configurable
const _appPepper = 'app_pepper';

class ZonaiDb {
  ZonaiDb()
    : _extensions = Mailman(
        debugName: 'EXTENSIONS',
        executablePath: extensions.executablePath,
        fromJson: ExtensionResponse.fromJson,
      ),
      _rules = Mailman(
        debugName: 'RULES',
        executablePath: rules.executablePath,
        fromJson: RuleResponse.fromJson,
      ),
      _operations = Mailman(
        debugName: 'OPERATIONS',
        executablePath: operations.executablePath,
        fromJson: OperationResponse.fromJson,
      ),
      _jwt = Jwt(jwtPepper: _appPepper),
      _hashPassword = HashPassword(passwordPepper: _appPepper);

  Raindrop? db;
  final Mailman<ExtensionRequest, ExtensionResponse> _extensions;
  final Mailman<RuleRequest, RuleResponse> _rules;
  final Mailman<OperationRequest, OperationResponse> _operations;
  final Jwt _jwt;
  final HashPassword _hashPassword;

  File? __dbFile;

  Future<_Result<_AuthResult>> authenticate(
    String collection,
    AuthPayload payload,
  ) async {
    return await _authenticate(collection, payload);
  }

  Future<_Result<_AuthResult>> signIn(
    String collection,
    AuthPayload payload,
  ) async {
    return await _signIn(collection, payload);
  }

  Future<_Result<_AuthResult>> signUp(
    String collection,
    AuthPayload payload,
  ) async {
    return await _signUp(collection, payload);
  }

  Future<void> logout(String jwt) async {
    return await _logout(jwt);
  }

  Future<void> logoutAll(String jwt) async {
    return await _logoutAll(jwt);
  }

  Future<_CrudResult> create(String collection, CreatePayload payload) async {
    return await _create(collection, payload);
  }

  Future<_CrudListResult> update(
    String collection,
    UpdatePayload payload,
  ) async {
    return await _update(collection, payload);
  }

  Future<_Result<int>> delete(String collection, DeletePayload payload) async {
    return await _delete(collection, payload);
  }

  Future<_CrudResult> view(String collection, ViewPayload payload) async {
    return await _view(collection, payload);
  }

  Future<_CrudListResult> list(String collection, ListPayload payload) async {
    return await _list(collection, payload);
  }

  Stream<Map<String, Object?>> streamOne(
    String collection,
    ViewPayload payload,
  ) async* {
    yield* await _streamOne(collection, payload);
  }

  Stream<List<Map<String, Object?>>> streamList(
    String collection,
    ListPayload payload,
  ) async* {
    yield* await _streamList(collection, payload);
  }
}
