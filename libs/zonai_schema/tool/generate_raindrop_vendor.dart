// Vendors the `raindrop`/`raindrop_sqlite` packages' source (from the
// `libs/raindrop` submodule) directly into this package under `lib/gen/`,
// rewriting their `package:raindrop(_sqlite)/` imports to the new vendored
// location so this package no longer needs an external path/git dependency
// on them. Baked in with explicit permission from raindrop's original
// author (see apps/zonai/tool/generate_raindrop_bundle.dart, which embeds
// the same source for a different purpose).
//
// The three files backing raindrop_sqlite's `ResqliteDelegate` (reactive
// streaming support) are deliberately excluded -- they need `package:resqlite`,
// a git dependency that would defeat the point of vendoring. Zonai's own
// runtime (apps/zonai) ports those three files separately, importing the
// vendored `SQLiteDelegate`/`RaindropDelegate` from here instead.
//
// Run from libs/zonai_schema:
//   dart run tool/generate_raindrop_vendor.dart

import 'dart:io';

const _submoduleRelative = '../raindrop/packages';
const _outputRelative = 'lib/gen/raindrop';

const _packages = ['raindrop', 'raindrop_sqlite'];

/// Files backing `ResqliteDelegate`'s reactive streaming -- these need
/// `package:resqlite` (a git dependency) and are ported separately into
/// apps/zonai instead of vendored here. See module comment above.
const _excludedFiles = {
  'raindrop_sqlite/lib/src/resqlite_delegate.dart',
  'raindrop_sqlite/lib/src/hybrid_stream_engine.dart',
  'raindrop_sqlite/lib/src/sql_read_dependencies.dart',
};

const _header = '''
// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

''';

void main() {
  final packageRoot = Directory.current.absolute;
  final submoduleDir = Directory('${packageRoot.path}/$_submoduleRelative');
  final outputDir = Directory('${packageRoot.path}/$_outputRelative');

  for (final package in _packages) {
    final libDir = Directory('${submoduleDir.path}/$package/lib');
    if (!libDir.existsSync()) {
      stderr.writeln(
        'Missing ${libDir.path}.\n'
        'Ensure the raindrop submodule is checked out (run from libs/zonai_schema).',
      );
      exit(1);
    }
  }

  if (outputDir.existsSync()) {
    outputDir.deleteSync(recursive: true);
  }
  outputDir.createSync(recursive: true);

  var fileCount = 0;
  for (final package in _packages) {
    final libDir = Directory('${submoduleDir.path}/$package/lib');

    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }

      final relative = _relativePosixPath(libDir.path, entity.path);
      final key = '$package/lib/$relative';
      if (_excludedFiles.contains(key)) {
        continue;
      }

      var content = entity.readAsStringSync();
      content = _rewriteImports(content);
      content = _stripInternalAnnotations(content);
      content = _renameTableClass(content);
      if (package == 'raindrop_sqlite' && relative == 'raindrop_sqlite.dart') {
        content = _dropResqliteDelegateExport(content);
      }

      final outFile = File('${outputDir.path}/$package/$relative');
      outFile.parent.createSync(recursive: true);
      outFile.writeAsStringSync('$_header$content');
      fileCount++;
    }
  }

  stdout.writeln('Vendored $fileCount files into ${outputDir.path}');
}

/// Rewrites cross-package import/export URIs to point at the vendored
/// location. Order matters: `raindrop_sqlite/` is checked first since
/// `package:raindrop/` is also a prefix-match candidate for it (though the
/// required trailing `/` after `raindrop` means it never actually collides
/// -- kept in this order for clarity, not correctness).
String _rewriteImports(String content) {
  return content
      .replaceAll(
        "'package:raindrop_sqlite/",
        "'package:zonai_schema/gen/raindrop/raindrop_sqlite/",
      )
      .replaceAll(
        "'package:raindrop/",
        "'package:zonai_schema/gen/raindrop/raindrop/",
      );
}

/// Renames raindrop's own `Table` (a reflection/metadata class,
/// `Table.getFor`/`Table.get`) to `TableMeta` so it doesn't collide with
/// zonai_schema's existing developer-facing `Table<T>` DSL class once both
/// live in the same package, and doesn't read as a vendored-from-elsewhere
/// type -- this is vendored source, not a re-exported dependency. Word-
/// boundary matched so it never touches identifiers like `TableSnapshot`,
/// `AlterTable`, SQL's uppercase `TABLE`, or the lowercase `table()`
/// function.
///
/// Applied to EVERY vendored package, not just `raindrop`. It was once
/// scoped to `raindrop` alone, on the assumption that only that package
/// names the type; raindrop_sqlite's `LimitedWriteClause` broke that by
/// declaring a `Table<Schema<dynamic>, dynamic>` field, and the vendored
/// copy then referenced a class no file in the tree declares -- caught only
/// at AOT compile, well past `dart analyze`.
String _renameTableClass(String content) {
  return content.replaceAllMapped(RegExp(r'\bTable\b'), (match) => 'TableMeta');
}

/// Every meta annotation this strips off can be dropped safely; the set is
/// explicit so that one it does not know about breaks the import removal
/// below loudly (a missing import fails `dart analyze lib/gen/raindrop`, the
/// check that owns this file) rather than silently.
const _metaAnnotations = {
  'alwaysThrows',
  'awaitNotRequired',
  'doNotStore',
  'doNotSubmit',
  'experimental',
  'factory',
  'immutable',
  'internal',
  'isTest',
  'isTestGroup',
  'literal',
  'mustBeConst',
  'mustBeOverridden',
  'mustCallSuper',
  'nonVirtual',
  'optionalTypeArgs',
  'protected',
  'redeclare',
  'reopen',
  'sealed',
  'useResult',
  'virtual',
  'visibleForOverriding',
  'visibleForTesting',
};

/// Drops `@internal`, which cannot survive the move into another package.
///
/// It means "private to package raindrop", and this is not package raindrop.
/// It also lands under `lib/gen/` rather than `lib/src/`, so as far as the
/// analyzer is concerned every vendored declaration is part of zonai_schema's
/// public API -- which makes the annotation itself an error
/// (`invalid_internal_annotation`), and makes the barrel re-exporting those
/// declarations another one (`invalid_export_of_internal_element`). Upstream
/// is right to mark them; the mark just does not travel. Nothing is lost by
/// dropping it: what zonai_schema actually offers callers is decided by the
/// `show`/`hide` clauses in `lib/zonai_schema.dart`, not by an annotation
/// inside the vendored tree.
///
/// The `package:meta` import goes with it when no other meta annotation is
/// left in the file, since an unused import is its own analyzer complaint.
String _stripInternalAnnotations(String content) {
  if (!content.contains('@internal')) return content;

  var lines = content
      .split('\n')
      .where((line) => line.trim() != '@internal')
      .toList();

  final stillUsesMeta = _metaAnnotations.any(
    (annotation) => RegExp('@$annotation\\b').hasMatch(lines.join('\n')),
  );
  if (!stillUsesMeta) {
    lines = lines
        .where((line) => line.trim() != "import 'package:meta/meta.dart';")
        .toList();
  }

  return lines.join('\n');
}

/// The vendored barrel can't export the excluded `resqlite_delegate.dart`.
String _dropResqliteDelegateExport(String content) {
  return content
      .split('\n')
      .where((line) => line.trim() != "export 'src/resqlite_delegate.dart';")
      .join('\n');
}

String _relativePosixPath(String from, String to) {
  final relative = to.substring(from.length + 1);
  return Platform.pathSeparator == '/'
      ? relative
      : relative.replaceAll(r'\', '/');
}
