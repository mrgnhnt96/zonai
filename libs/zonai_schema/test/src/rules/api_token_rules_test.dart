import 'package:test/test.dart';
import 'package:zonai_schema/src/handlers/rules/rule_request.dart'
    show TableOperation;
import 'package:zonai_schema/src/internal/rules/api_token_row_rules.dart';
import 'package:zonai_schema/src/internal/rules/api_token_table_rules.dart';
import 'package:zonai_schema/src/internal/tables/api_token_table.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// Who may reach `_api_tokens` through `/db`.
///
/// The row *is* the credential's authority, so this table is where a scope
/// stops meaning anything if it is got wrong: a token that can read it sees
/// every other integration's row, and a token that can write it mints itself
/// a wider one. Both are denied here, and again by the central gate in
/// `ZonaiDb` that refuses an API token on every internal table -- said twice
/// on purpose, at the table where the cost of a single miss is highest.
void main() {
  /// A caller with the given admin claims, built through `Jwt.fromJson` --
  /// the same door a real request arrives by.
  Jwt jwt({required bool isAdmin, bool? canEdit}) => Jwt.fromJson({
    'userId': 'u1',
    'table': 'admins',
    'user': <String, dynamic>{},
    'jwtId': 'j1',
    'expiresAt':
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
        1000,
    'claims': <String, dynamic>{},
    'admin': {'isAdmin': isAdmin, 'canEdit': canEdit},
  });

  /// The most powerful API token that can exist: every table, every
  /// operation, admin, editing. It still gets nothing here.
  ApiTokenJwt apiToken() => ApiTokenJwt(
    tokenId: ApiTokenId('abcdef123456789_pat'),
    name: 'over-privileged',
    scope: const ApiTokenScope(
      tables: {ApiTokenScope.wildcard},
      operations: {
        TableOperation.view,
        TableOperation.list,
        TableOperation.create,
        TableOperation.update,
        TableOperation.delete,
      },
      admin: true,
      canEdit: true,
    ),
  );

  final row = ApiTokenEntry.create(
    name: 'nightly-backup',
    tokenHash: 'hash_1',
    tokenPrefix: 'zonai_pat_abcd1234',
    scope: const ApiTokenScope(tables: {'orders'}, operations: {}),
    createdBy: '__cli__',
  );

  final table = ApiTokenTableRules();
  final rows = ApiTokenRowRules();

  group('an API token gets nothing, at any level', () {
    test('not reads', () async {
      final token = apiToken();

      expect(await table.canView(token), isFalse);
      expect(await table.canList(token), isFalse);
      expect(await rows.canView(token, row), isFalse);
    });

    test('not writes', () async {
      final token = apiToken();

      expect(await table.canCreate(token), isFalse);
      expect(await table.canUpdate(token), isFalse);
      expect(await table.canDelete(token), isFalse);
      expect(await rows.canCreate(token, row), isFalse);
      expect(await rows.canUpdate(token, row, row), isFalse);
      expect(await rows.canDelete(token, row), isFalse);
    });

    test('its admin claim is genuinely the strongest one there is', () {
      // Guards the test above from passing vacuously: if the fixture stopped
      // claiming admin, every denial would be the inherited default rather
      // than the API-token check this file exists for.
      expect(apiToken().admin, (isAdmin: true, canEdit: true));
    });
  });

  group('nobody creates or updates a token row through /db', () {
    // A row written this way carries whatever `token_hash` the caller
    // supplied, or the empty placeholder `safeCreate` fills in for a secret
    // column -- so it is either an unusable credential or one the caller
    // chose. Minting has its own path.
    test('not even an editing admin', () async {
      final admin = jwt(isAdmin: true, canEdit: true);

      expect(await table.canCreate(admin), isFalse);
      expect(await table.canUpdate(admin), isFalse);
      expect(await rows.canCreate(admin, row), isFalse);
      expect(await rows.canUpdate(admin, row, row), isFalse);
    });
  });

  group('an admin may see the registry and delete from it', () {
    test('read needs isAdmin', () async {
      expect(await table.canList(null), isFalse);
      expect(await table.canView(null), isFalse);
      expect(await table.canList(jwt(isAdmin: false)), isFalse);
      expect(await table.canList(jwt(isAdmin: true)), isTrue);
      expect(await table.canView(jwt(isAdmin: true)), isTrue);
      expect(await rows.canView(jwt(isAdmin: true), row), isTrue);
    });

    test('hard revoke needs canEdit', () async {
      expect(await table.canDelete(jwt(isAdmin: true)), isFalse);
      expect(await rows.canDelete(jwt(isAdmin: true), row), isFalse);
      expect(await table.canDelete(jwt(isAdmin: true, canEdit: true)), isTrue);
      expect(
        await rows.canDelete(jwt(isAdmin: true, canEdit: true), row),
        isTrue,
      );
    });
  });
}
