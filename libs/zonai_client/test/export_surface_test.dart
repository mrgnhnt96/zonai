// dart format width=100
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
// `hide Literal`: the analyzer's AST declares its own `Literal`, which collides
// with the `UpdateValue` variant the barrel exports. Only this file hits it --
// it is the one place that imports both -- and the sweep below needs just the
// three *Declaration nodes.
import 'package:analyzer/dart/ast/ast.dart' hide Literal;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
// The historical incident (see project memory `project-zonai-client-storage-export`):
// a web-safety refactor deleted `export 'src/utils/zonai_storage.dart'` from this
// barrel and took `ZonaiStorage.memory()`/`.none()` with it for two months. Nothing
// inside this workspace imports the barrel the way a real consumer does, so nothing
// noticed. Importing it here, the same way a consumer would, means a repeat of that
// specific regression fails this file to even compile.
import 'package:zonai_client/zonai_client.dart';

void main() {
  // ---------------------------------------------------------------------
  // Group 1: anchor symbols, checked the way a real consumer checks them --
  // by importing the barrel and using the symbol. If any of these vanish
  // from the export list, this file fails to *compile*, not just to pass.
  // ---------------------------------------------------------------------
  group('anchor symbols resolve through the public barrel (compile-time)', () {
    test('ZonaiClient, Auth and the ZonaiStorage family are usable', () async {
      final storage = ZonaiStorage.memory();
      expect(storage, isA<ZonaiMemoryStorage>());
      expect(ZonaiStorage.none(), isA<ZonaiNoStorage>());

      final client = ZonaiClient(storage: storage);
      expect(client.auth, isA<Auth>());

      // ZonaiClient.instance / instance= round-trips through the public API.
      final previous = ZonaiClient.instance;
      ZonaiClient.instance = client;
      expect(ZonaiClient.instance, same(client));
      ZonaiClient.instance = previous;
    });

    // OAuth types are re-exported from `package:zonai_schema/payloads.dart`
    // via an explicit `show` list, the same shape that let a storage export
    // go missing for two months (see the comment atop this file). Nothing
    // else in this workspace imports the barrel the way a real consumer
    // does, so an omission here fails only this compile.
    test('OAuthProviderPublic and OAuthProviderKind are usable', () async {
      final provider = OAuthProviderPublic.fromJson({
        'id': 'google',
        'displayName': 'Google',
        'table': 'users',
        'kind': 'google',
        'iconUrl': null,
        'iconSvg': null,
        'background': null,
        'foreground': null,
        'startPath': '/auth/oauth/start/google?table=users',
      });
      expect(provider.kind, OAuthProviderKind.google);
      expect(provider.toJson(), containsPair('id', 'google'));
    });

    // The group-2 sweep below only walks zonai_client's OWN lib/src, so it is
    // blind to the `show` list on the `package:zonai_schema/payloads.dart`
    // re-export: a name dropped from there breaks every consumer and fails
    // nothing here. That is the exact failure shape described atop this file.
    // These tests therefore *use* each symbol, so an omission fails the
    // compile rather than an assertion.
    //
    // A generated typed client (docs/typed-client-design.md §5.4) returns and
    // consumes this whole vocabulary, which is why it has to be nameable.
    test('every Where variant is constructible through the barrel', () {
      // `Null` / `NotNull` are deliberately NOT exported -- they would shadow
      // dart:core's `Null` in every consumer library. The redirecting factories
      // are what keep those two clauses reachable anyway; that they appear here
      // and the class names do not is the whole point.
      final List<Where> clauses = [
        const Eq('a', 1),
        const Gt('a', 1),
        const Gte('a', 1),
        const Lt('a', 1),
        const Lte('a', 1),
        const In('a', <Object>['x']),
        const NotIn('a', <Object>['x']),
        const And(<Where>[Eq('a', 1)]),
        const Or(<Where>[Eq('a', 1)]),
        const Contains('a', 'x'),
        const NotContains('a', 'x'),
        const StartsWith('a', 'x'),
        const EndsWith('a', 'x'),
        const Where.isNull('a'),
        const Where.isNotNull('a'),
      ];

      expect(clauses.map((c) => c.toJson()['type']).toList(), [
        'eq',
        'gt',
        'gte',
        'lt',
        'lte',
        'in',
        'not_in',
        'and',
        'or',
        'contains',
        'not_contains',
        'starts_with',
        'ends_with',
        'is_null',
        'not_null',
      ]);

      // Every clause survives the wire, reached only through the barrel.
      for (final clause in clauses) {
        expect(Where.fromJson(clause.toJson()).toJson(), clause.toJson());
      }
    });

    test('OrderByTerm and both SortDirections are usable', () {
      const OrderByTerm ascending = OrderByTerm(column: 'created_at', direction: SortDirection.asc);
      const OrderByTerm descending = OrderByTerm(
        column: 'created_at',
        direction: SortDirection.desc,
      );

      // `asc` is the default, so it is omitted from the wire form.
      expect(ascending.toJson(), {'column': 'created_at'});
      expect(descending.toJson(), {'column': 'created_at', 'direction': 'desc'});
    });

    test('Update and every UpdateValue variant are constructible', () {
      final List<UpdateValue> values = [
        const Literal(5),
        const Increment(),
        const Decrement(),
        const Add('x'),
        const Remove('x'),
        const AddAll(<Object?>['x']),
        const RemoveAll(<Object?>['x']),
      ];

      expect(values.map((v) => v.toJson()['type']).toList(), [
        'literal',
        'increment',
        'decrement',
        'add',
        'remove',
        'add_all',
        'remove_all',
      ]);

      // Each one wrapped the way a generated client would wrap it.
      for (final value in values) {
        final Update update = Update.column('count', value);
        expect(update, isA<ColumnUpdate>());
        expect(update.toJson(), {'type': 'column', 'column': 'count', 'value': value.toJson()});
      }

      final Update object = Update.object({'title': 'hello'});
      expect(object, isA<ObjectUpdate>());
      expect(object.toJson(), {
        'type': 'object',
        'object': {'title': 'hello'},
      });
    });

    test('the five client types reachable from ZonaiClient are nameable', () {
      // Memory storage, not `ZonaiStorage.none()`: constructing a client writes
      // through to storage, and the no-op one asserts on save.
      final client = ZonaiClient(storage: ZonaiStorage.memory());

      // The point of this test is the *type annotations*, not the values: each
      // one is a name a generated `PostsApi` must be able to write down. Before
      // these were exported, every line here needed an implementation import
      // (package:zonai_client/src/db.dart) that no consumer should ever write.
      final Db db = client.db;
      final DbListen listen = db.listen;
      final Emails emails = client.email;
      final Photos photos = client.photos;
      final AdminAuth admin = client.auth.admin;

      expect(db, isNotNull);
      expect(listen, isNotNull);
      expect(emails, isNotNull);
      expect(photos, isNotNull);
      expect(admin, isNotNull);
    });
  });

  // ---------------------------------------------------------------------
  // Group 2: derived sweep. Rather than hand-listing every symbol the
  // barrel is expected to export (a list that silently rots the day a new
  // export is added, same failure shape verify.yaml already flags in
  // help_test.dart), this walks lib/src/**.dart with the analyzer and
  // computes, from source, every top-level public class/mixin/enum the
  // package actually declares. Each one must either:
  //   (a) be reachable from `import 'package:zonai_client/zonai_client.dart'`, or
  //   (b) appear in _exclusions below with a cited reason.
  // A NEW file/class added under lib/src is picked up automatically the
  // next time this test runs -- nothing here needs editing for that case.
  // Only _exclusions needs a human decision, and only when something is
  // deliberately kept off the barrel.
  // ---------------------------------------------------------------------
  group('every public declaration under lib/src is reachable or explicitly excluded', () {
    test('sweep', () async {
      final packageRoot = _packageRoot();
      final libDir = Directory(p.join(packageRoot, 'lib'));
      final srcDir = Directory(p.join(packageRoot, 'lib', 'src'));
      final barrelPath = p.join(packageRoot, 'lib', 'zonai_client.dart');

      final collection = AnalysisContextCollection(includedPaths: [libDir.path]);

      final barrelContext = collection.contextFor(barrelPath);
      final barrelResolved = await barrelContext.currentSession.getResolvedLibrary(barrelPath);
      if (barrelResolved is! ResolvedLibraryResult) {
        fail('Could not resolve lib/zonai_client.dart as a library: $barrelResolved');
      }
      final exportedNames = barrelResolved.element.exportNamespace.definedNames2.keys.toSet();

      final missing = <String>[];
      for (final file in srcDir.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        final filePath = p.absolute(file.path);

        final context = collection.contextFor(filePath);
        final resolved = await context.currentSession.getResolvedUnit(filePath);
        if (resolved is! ResolvedUnitResult) {
          fail('Could not resolve $filePath: $resolved');
        }

        for (final declaration in resolved.unit.declarations) {
          final name = switch (declaration) {
            ClassDeclaration(:final namePart) => namePart.typeName.lexeme,
            MixinDeclaration(:final name) => name.lexeme,
            EnumDeclaration(:final namePart) => namePart.typeName.lexeme,
            _ => null,
          };
          if (name == null || name.startsWith('_')) continue;

          final relativePath = p.relative(filePath, from: packageRoot);
          if (exportedNames.contains(name)) continue;
          if (_exclusions.containsKey(name)) continue;

          missing.add('$name (declared in $relativePath)');
        }
      }

      expect(
        missing,
        isEmpty,
        reason:
            'The following public declarations under lib/src are not reachable from '
            "package:zonai_client/zonai_client.dart and are not in this test's "
            '_exclusions map. Either export them from the barrel, or add a justified '
            'entry to _exclusions:\n${missing.join('\n')}',
      );
    });
  });
}

/// Declarations that are deliberately not reachable from
/// `package:zonai_client/zonai_client.dart`, each with the evidence for why.
///
/// This is a short, negative list of infrastructure -- not a positive list of
/// the public API surface. Adding a new *internal* file requires a line here;
/// adding a new *exported* one requires nothing, since the sweep above reads
/// lib/src directly.
const _exclusions = <String, String>{
  // Exported from lib/storage.dart instead, on purpose: lib/storage.dart's own
  // doc comment says this split exists so web apps depending on zonai_client
  // don't pull package:file (via ZonaiFileStorage -> LocalFileSystem) into the
  // browser build. Verified separately in test/web_safety_split_test.dart.
  'ZonaiFileStorage': 'exported from lib/storage.dart, not lib/zonai_client.dart',

  // Constructed only inside ZonaiClient's factory (lib/src/zonai_client.dart)
  // to wire the X-Auth interceptor chain. No public getter ever hands a
  // consumer an Interceptor instance, so there is nothing for a consumer to
  // need a type name for.
  'Interceptor': 'internal HttpInterceptor wiring, never handed to a consumer',
};

/// Walks up from this test file looking for the package root (identified by
/// pubspec.yaml declaring `name: zonai_client`).
String _packageRoot() {
  var dir = File.fromUri(Platform.script).parent;
  if (!dir.existsSync()) {
    dir = Directory.current;
  }
  for (var i = 0; i < 8; i++) {
    final pubspec = File(p.join(dir.path, 'pubspec.yaml'));
    if (pubspec.existsSync() && pubspec.readAsStringSync().contains('name: zonai_client')) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  // `dart test` runs with cwd already at the package root.
  return Directory.current.path;
}
