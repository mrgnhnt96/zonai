import 'package:file/memory.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/domain/ipc_protocol_stamp.dart';
import 'package:zonai_schema/src/handlers/messages/ipc_codec.dart';

void main() {
  group('protocol stamp', () {
    late MemoryFileSystem memoryFs;

    Set<ScopedRef<dynamic>> overrides() => {fsProvider.overrideWith(() => memoryFs)};

    setUp(() {
      memoryFs = MemoryFileSystem();
    });

    test('stamp path sits next to the executable, same name, .protocol extension', () {
      runScoped(() {
        expect(
          protocolStampPathFor('/exes/db_config.exe'),
          '/exes/db_config.protocol',
        );
      }, values: overrides());
    });

    test('readProtocolStamp round-trips whatever writeProtocolStamp wrote', () {
      runScoped(() {
        writeProtocolStamp('/exes/db_config.exe');
        expect(readProtocolStamp('/exes/db_config.exe'), IpcCodec.version);
      }, values: overrides());
    });

    test('readProtocolStamp returns null when no stamp exists', () {
      runScoped(() {
        expect(readProtocolStamp('/exes/db_config.exe'), isNull);
      }, values: overrides());
    });

    test('readProtocolStamp returns null for unparseable stamp content', () {
      runScoped(() {
        fs.file('/exes/db_config.protocol')
          ..createSync(recursive: true)
          ..writeAsStringSync('not-a-number');
        expect(readProtocolStamp('/exes/db_config.exe'), isNull);
      }, values: overrides());
    });

    test('writeProtocolStamp creates parent directories as needed', () {
      runScoped(() {
        writeProtocolStamp('/nested/deep/db_config.exe');
        expect(fs.file('/nested/deep/db_config.protocol').existsSync(), isTrue);
      }, values: overrides());
    });
  });

  group('isProtocolStale', () {
    late MemoryFileSystem memoryFs;

    Set<ScopedRef<dynamic>> overrides() => {fsProvider.overrideWith(() => memoryFs)};

    setUp(() {
      memoryFs = MemoryFileSystem();
    });

    test('false when the executable does not exist', () {
      runScoped(() {
        expect(
          isProtocolStale('/exes/db_config.exe', hostVersion: IpcCodec.version),
          isFalse,
        );
      }, values: overrides());
    });

    test('false when the executable exists but has no stamp', () {
      runScoped(() {
        fs.file('/exes/db_config.exe').createSync(recursive: true);
        expect(
          isProtocolStale('/exes/db_config.exe', hostVersion: IpcCodec.version),
          isFalse,
        );
      }, values: overrides());
    });

    test('false when the stamp matches hostVersion', () {
      runScoped(() {
        fs.file('/exes/db_config.exe').createSync(recursive: true);
        writeProtocolStamp('/exes/db_config.exe');
        expect(
          isProtocolStale('/exes/db_config.exe', hostVersion: IpcCodec.version),
          isFalse,
        );
      }, values: overrides());
    });

    test('true when the stamp disagrees with hostVersion', () {
      runScoped(() {
        fs.file('/exes/db_config.exe').createSync(recursive: true);
        fs.file('/exes/db_config.protocol')
          ..createSync(recursive: true)
          ..writeAsStringSync('${IpcCodec.version + 1}');
        expect(
          isProtocolStale('/exes/db_config.exe', hostVersion: IpcCodec.version),
          isTrue,
        );
      }, values: overrides());
    });
  });
}
