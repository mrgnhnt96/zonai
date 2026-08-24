import 'package:file/memory.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/gen/version.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/domain/ai_docs.dart';

/// The stamp is what turns "is my CLAUDE.md current?" into a question with an
/// answer. Every way it can be missing or misread ends with a project keeping
/// prose from an older release, so each one gets a case here.
void main() {
  group('readAiDocVersion', () {
    test('reads back the version stampAiDoc wrote', () {
      expect(
        readAiDocVersion(stampAiDoc('# Zonai', version: '1.2.3')),
        '1.2.3',
      );
    });

    test('defaults to the running CLI version', () {
      expect(readAiDocVersion(stampAiDoc('# Zonai')), kVersion);
    });

    test('is null for a file written before stamping existed', () {
      // The pre-existing case, and the whole reason an absent stamp reads as
      // out of date: every sheet installed by an older CLI looks like this.
      expect(readAiDocVersion('# Zonai\n\nno marker anywhere\n'), isNull);
    });

    test('survives notes appended under the stamp', () {
      final contents =
          '${stampAiDoc('# Zonai', version: '0.9.0')}\n'
          'Team note: keep the section on rules.\n';

      expect(readAiDocVersion(contents), '0.9.0');
    });

    test('takes the last marker, so prose quoting one cannot outrank it', () {
      final contents = stampAiDoc(
        '# Zonai\n\nFiles carry ${aiDocStamp('0.0.1')} at the end.',
        version: '2.0.0',
      );

      expect(readAiDocVersion(contents), '2.0.0');
    });
  });

  group('stampAiDoc', () {
    test('appends an HTML comment, not a dart fence', () {
      // doc_snippets_test.dart lifts ```dart fences out of ai_templates.dart
      // and hands them to the analyzer. A stamp shaped like a fence would be
      // compiled as Dart on every build.
      final stamped = stampAiDoc('# Zonai');

      expect(stamped, endsWith('<!-- zonai:ai v$kVersion -->\n'));
      expect(stamped, isNot(contains('```')));
    });

    test('leaves YAML front matter untouched', () {
      // The .mdc files open with `---`; a stamp written at the top would land
      // inside the front matter and change what Cursor reads as metadata.
      final stamped = stampAiDoc('---\ndescription: zonai\n---\n\n# Rules');

      expect(stamped, startsWith('---\ndescription: zonai\n---\n'));
    });

    test('does not accumulate blank lines when re-stamping trimmed input', () {
      expect(
        stampAiDoc('# Zonai\n\n\n'),
        '# Zonai\n\n${aiDocStamp(kVersion)}\n',
      );
    });
  });

  group('installedAiDocs', () {
    test('finds only the files that exist, and names their writer', () {
      final fs = MemoryFileSystem();
      fs.file('CLAUDE.md').writeAsStringSync(stampAiDoc('a', version: '0.7.0'));
      fs.file('.clinerules').writeAsStringSync('unstamped');

      final docs = _run(fs, installedAiDocs);

      expect(docs.map((d) => d.path), ['CLAUDE.md', '.clinerules']);
      expect(docs.first.writtenBy, '0.7.0');
      expect(docs.first.describeWriter, 'written by v0.7.0');
      expect(docs.last.writtenBy, isNull);
      expect(docs.last.describeWriter, 'no version stamp');
    });

    test('is empty in a project that never ran zonai ai', () {
      expect(_run(MemoryFileSystem(), installedAiDocs), isEmpty);
    });
  });

  group('staleAiDocs', () {
    test('ignores a file already stamped with the version asked about', () {
      final fs = MemoryFileSystem();
      fs.file('CLAUDE.md').writeAsStringSync(stampAiDoc('a', version: '0.9.0'));

      expect(_run(fs, () => staleAiDocs(version: '0.9.0')), isEmpty);
    });

    test('reports a file written by another release', () {
      final fs = MemoryFileSystem();
      fs.file('CLAUDE.md').writeAsStringSync(stampAiDoc('a', version: '0.7.0'));

      final stale = _run(fs, () => staleAiDocs(version: '0.9.0'));

      expect(stale.single.path, 'CLAUDE.md');
      expect(stale.single.writtenBy, '0.7.0');
    });

    test('reports an unstamped file rather than assuming it is current', () {
      final fs = MemoryFileSystem();
      fs.file('.windsurfrules').writeAsStringSync('# Zonai\n');

      expect(
        _run(fs, () => staleAiDocs(version: '0.9.0')).single.path,
        '.windsurfrules',
      );
    });

    test('reports a newer stamp too -- a downgrade is a mismatch', () {
      // `assertVersion` downloads the version a project pins, which can be
      // older than the CLI that was running. Sheets from the newer release
      // describe a framework this project is not on.
      final fs = MemoryFileSystem();
      fs.file('CLAUDE.md').writeAsStringSync(stampAiDoc('a', version: '1.0.0'));

      expect(_run(fs, () => staleAiDocs(version: '0.9.0')), hasLength(1));
    });

    test('scans every path any tool installs', () {
      final fs = MemoryFileSystem();
      for (final path in allAiDocPaths) {
        fs.file(path)
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('unstamped');
      }

      expect(
        _run(fs, () => staleAiDocs(version: kVersion)).map((d) => d.path),
        containsAll(allAiDocPaths),
      );
    });
  });
}

T _run<T>(MemoryFileSystem fs, T Function() body) =>
    runScoped(body, values: {fsProvider.overrideWith(() => fs)});
