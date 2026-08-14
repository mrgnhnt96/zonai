import 'package:file/memory.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/db_mutator/worker_protocol_mismatch_exception.dart';
import 'package:zonai/src/deps/fs.dart';

void main() {
  group('WorkerProtocolMismatchException.forStamp', () {
    late MemoryFileSystem memoryFs;

    Set<ScopedRef<dynamic>> overrides() => {
      fsProvider.overrideWith(() => memoryFs),
    };

    setUp(() {
      memoryFs = MemoryFileSystem();
    });

    test('null when the worker has no stamp', () {
      runScoped(() {
        final error = WorkerProtocolMismatchException.forStamp(
          workerName: 'CONFIG',
          executablePath: '/exes/db_config.exe',
          hostVersion: 1,
        );
        expect(error, isNull);
      }, values: overrides());
    });

    test('null when the worker stamp matches the host version', () {
      runScoped(() {
        fs.file('/exes/db_config.protocol')
          ..createSync(recursive: true)
          ..writeAsStringSync('1');

        final error = WorkerProtocolMismatchException.forStamp(
          workerName: 'CONFIG',
          executablePath: '/exes/db_config.exe',
          hostVersion: 1,
        );
        expect(error, isNull);
      }, values: overrides());
    });

    test('carries both versions and mentions the fix when stamps disagree', () {
      runScoped(() {
        fs.file('/exes/db_config.protocol')
          ..createSync(recursive: true)
          ..writeAsStringSync('2');

        final error = WorkerProtocolMismatchException.forStamp(
          workerName: 'CONFIG',
          executablePath: '/exes/db_config.exe',
          hostVersion: 1,
        );

        expect(error, isNotNull);
        expect(error!.workerName, 'CONFIG');
        expect(error.executablePath, '/exes/db_config.exe');
        expect(error.hostVersion, 1);
        expect(error.workerVersion, 2);
        expect(error.message, contains('CONFIG'));
        expect(error.message, contains('v2'));
        expect(error.message, contains('v1'));
        expect(error.message, contains('zonai compile'));
        expect(error.message, contains('zonai build'));
        expect(error.message, contains('https://docs.zonai.dev/cli/upgrading'));
      }, values: overrides());
    });
  });
}
