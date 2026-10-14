import 'package:test/test.dart';
import 'package:zonai_schema/src/exceptions/hook_refused_exception.dart';
import 'package:zonai_schema/src/handlers/extensions/db_extensions.dart';
import 'package:zonai_schema/src/handlers/extensions/extension_request.dart';
import 'package:zonai_schema/zonai_schema.dart';

void main() {
  test('extensionsByTable registers each extension by table name', () {
    final users = table('users', _UserTable.new);
    final items = table('items', _ItemTable.new);

    final dbExtensions = DbExtensions(
      extensions: [_UsersExtension(users), _ItemsExtension(items)],
    );

    expect(
      dbExtensions.extensionsByTable.keys,
      containsAll(['users', 'items']),
    );
    expect(dbExtensions.extensionsByTable['users'], isA<_UsersExtension>());
    expect(dbExtensions.extensionsByTable['items'], isA<_ItemsExtension>());
  });

  group('a before* hook that throws', () {
    late _RefusingExtension extension;
    late DbExtensions dbExtensions;
    final items = table('items', _ItemTable.new);

    setUp(() {
      extension = _RefusingExtension(items);
      dbExtensions = DbExtensions(extensions: [extension]);
    });

    final steps = <String, ExtensionRequest Function()>{
      'beforeCreate': () => CreateExtensionRequest.before(
        table: 'items',
        object: {'id': 'a'},
        jwt: null,
      ),
      'beforeUpdate': () => BeforeUpdateExtensionRequest(
        table: 'items',
        objects: [
          {'id': 'a'},
        ],
        jwt: null,
      ),
      'beforeDelete': () => DeleteExtensionRequest.before(
        table: 'items',
        objects: [
          {'id': 'a'},
        ],
        jwt: null,
      ),
    };

    for (final MapEntry(key: hook, value: request) in steps.entries) {
      test('$hook: a 4xx HttpError is marked as a refusal', () async {
        extension.toThrow = const HttpError.forbidden(
          code: 'nope',
          message: 'Not yours',
        );

        await expectLater(
          dbExtensions.dispatch(request()),
          throwsA(
            isA<HookRefusedException>()
                .having((e) => e.error.statusCode, 'statusCode', 403)
                .having((e) => e.error.code, 'code', 'nope'),
          ),
        );
      });

      test('$hook: a 5xx HttpError passes through unmarked', () async {
        extension.toThrow = const HttpError.internal(
          code: 'broke',
          message: 'Broke',
        );

        await expectLater(
          dbExtensions.dispatch(request()),
          throwsA(isA<HttpError>()),
        );
      });

      test('$hook: any other throw passes through unmarked', () async {
        extension.toThrow = StateError('crashed');

        await expectLater(
          dbExtensions.dispatch(request()),
          throwsA(isA<StateError>()),
        );
      });
    }

    test('an after* hook\'s 4xx HttpError is not marked', () async {
      // Only the hooks that run before the write can refuse it. After the
      // write there is nothing left to refuse.
      extension.toThrow = const HttpError.forbidden(code: 'x', message: 'y');

      await expectLater(
        dbExtensions.dispatch(
          CreateExtensionRequest.afterSuccess(
            table: 'items',
            object: {'id': 'a'},
            jwt: null,
          ),
        ),
        throwsA(isA<HttpError>()),
      );
    });
  });
}

final class _User {
  const _User({required this.id});

  final String id;
}

final class _UserTable extends Table<_User> {
  _UserTable(super.$) : id = $.text('id', (s) => s.id);

  @override
  _User fromRow(RowReader read) => _User(id: read(id));

  final TextColumn id;
}

final class _Item {
  const _Item({required this.id});

  final String id;
}

final class _ItemTable extends Table<_Item> {
  _ItemTable(super.$) : id = $.text('id', (s) => s.id);

  @override
  _Item fromRow(RowReader read) => _Item(id: read(id));

  final TextColumn id;
}

final class _UsersExtension extends Extension<_User> {
  _UsersExtension(super.schema);
}

final class _ItemsExtension extends Extension<_Item> {
  _ItemsExtension(super.schema);
}

final class _RefusingExtension extends Extension<_Item> {
  _RefusingExtension(super.schema);

  Object toThrow = StateError('unset');

  @override
  Future<void> beforeCreate(_Item object, Jwt? jwt) async => throw toThrow;

  @override
  Future<void> afterCreateSuccess(_Item row, Jwt? jwt) async => throw toThrow;

  @override
  Future<void> beforeUpdate(_Item row, Jwt? jwt) async => throw toThrow;

  @override
  Future<void> beforeDelete(_Item row, Jwt? jwt) async => throw toThrow;
}
