import 'package:file/memory.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/message_contract_hash.dart';
import 'package:zonai/src/domain/message_contract_hash.dart';
import 'package:zonai/src/domain/message_contract_stamp.dart';

/// Stands in for a real source walk so these tests are about the sidecar, not
/// about resolving a package graph.
class _FixedContractHash extends MessageContractHash {
  _FixedContractHash(this._hash);

  final String? _hash;

  @override
  String? compute() => _hash;
}

void main() {
  late MemoryFileSystem memoryFs;

  Set<ScopedRef<dynamic>> overrides({String? hash = 'abc123'}) => {
    fsProvider.overrideWith(() => memoryFs),
    messageContractHashProvider.overrideWith(() => _FixedContractHash(hash)),
  };

  setUp(() {
    memoryFs = MemoryFileSystem();
  });

  group('stamp', () {
    test('appends .contract to the executable, extension and all', () {
      runScoped(() {
        expect(
          messageContractStampPathFor('/exes/db_rate_limit.exe'),
          '/exes/db_rate_limit.exe.contract',
        );
      }, values: overrides());
    });

    test('read round-trips what write wrote', () {
      runScoped(() {
        writeMessageContractStamp('/exes/db_rate_limit.exe');
        expect(readMessageContractStamp('/exes/db_rate_limit.exe'), 'abc123');
      }, values: overrides());
    });

    test('write creates parent directories as needed', () {
      runScoped(() {
        writeMessageContractStamp('/nested/deep/db_rate_limit.exe');
        expect(
          fs.file('/nested/deep/db_rate_limit.exe.contract').existsSync(),
          isTrue,
        );
      }, values: overrides());
    });

    test('read returns null when no stamp exists', () {
      runScoped(() {
        expect(readMessageContractStamp('/exes/db_rate_limit.exe'), isNull);
      }, values: overrides());
    });

    test('read returns null for an empty stamp', () {
      runScoped(() {
        fs.file('/exes/db_rate_limit.exe.contract')
          ..createSync(recursive: true)
          ..writeAsStringSync('   \n');
        expect(readMessageContractStamp('/exes/db_rate_limit.exe'), isNull);
      }, values: overrides());
    });

    // Leaving the old one would have the next spawn compare a fresh
    // executable against the contract of the build before it.
    test('write clears a stale stamp when the hash is unknown', () {
      runScoped(() {
        fs.file('/exes/db_rate_limit.exe.contract')
          ..createSync(recursive: true)
          ..writeAsStringSync('from-an-earlier-build');

        writeMessageContractStamp('/exes/db_rate_limit.exe');

        expect(
          fs.file('/exes/db_rate_limit.exe.contract').existsSync(),
          isFalse,
        );
      }, values: overrides(hash: null));
    });

    // An `.exe` and the `.aot` snapshot beside it are separate compiles that
    // have diverged before, so they cannot share one sidecar.
    test('an executable and its sibling snapshot get separate stamps', () {
      runScoped(() {
        expect(
          messageContractStampPathFor('/exes/db_operations.exe'),
          isNot(messageContractStampPathFor('/exes/db_operations.aot')),
        );

        writeMessageContractStamp('/exes/db_operations.exe');

        expect(readMessageContractStamp('/exes/db_operations.exe'), 'abc123');
        expect(readMessageContractStamp('/exes/db_operations.aot'), isNull);
      }, values: overrides());
    });
  });

  group('isMessageContractStale', () {
    test('false when the host contract is unknown', () {
      runScoped(() {
        fs.file('/exes/db_rate_limit.exe').createSync(recursive: true);
        writeMessageContractStamp('/exes/db_rate_limit.exe');

        expect(
          isMessageContractStale('/exes/db_rate_limit.exe', hostHash: null),
          isFalse,
        );
      }, values: overrides());
    });

    test('false when the executable does not exist', () {
      runScoped(() {
        expect(
          isMessageContractStale('/exes/db_rate_limit.exe', hostHash: 'abc123'),
          isFalse,
        );
      }, values: overrides());
    });

    test('false when the executable exists but carries no stamp', () {
      runScoped(() {
        fs.file('/exes/db_rate_limit.exe').createSync(recursive: true);
        expect(
          isMessageContractStale('/exes/db_rate_limit.exe', hostHash: 'abc123'),
          isFalse,
        );
      }, values: overrides());
    });

    test('false when the stamp matches', () {
      runScoped(() {
        fs.file('/exes/db_rate_limit.exe').createSync(recursive: true);
        writeMessageContractStamp('/exes/db_rate_limit.exe');

        expect(
          isMessageContractStale('/exes/db_rate_limit.exe', hostHash: 'abc123'),
          isFalse,
        );
      }, values: overrides());
    });

    test('true when the stamp disagrees', () {
      runScoped(() {
        fs.file('/exes/db_rate_limit.exe').createSync(recursive: true);
        writeMessageContractStamp('/exes/db_rate_limit.exe');

        expect(
          isMessageContractStale('/exes/db_rate_limit.exe', hostHash: 'def456'),
          isTrue,
        );
      }, values: overrides());
    });
  });

  group('hostMessageContractHash', () {
    // `kIsCompiled` is false under `dart test`, which is the JIT branch: the
    // host is the sources on disk, so hashing them now is exact.
    test('hashes the sources when this host is not a compiled binary', () {
      runScoped(() {
        expect(hostMessageContractHash(), 'abc123');
      }, values: overrides());
    });
  });

  group('hostContractUnknownReason', () {
    test('silent when the sources hash (the JIT host)', () {
      runScoped(() {
        expect(hostContractUnknownReason(), isNull);
      }, values: overrides());
    });

    test('names pub get when zonai_schema does not resolve', () {
      runScoped(() {
        expect(hostContractUnknownReason(), contains('dart pub get'));
      }, values: overrides(hash: null));
    });

    // The case the whole thing exists for, and the one `kIsCompiled` puts out
    // of reach of a test unless it is injected: a released `zonai` serving a
    // project directly. Nothing stamps that binary, so every spawn compares
    // against an unknown host and waves the worker through.
    test('explains an unstamped compiled host', () {
      runScoped(() {
        final reason = hostContractUnknownReason(
          isCompiled: true,
          readStamp: (_) => null,
        );

        expect(reason, isNotNull);
        expect(reason, contains('no contract stamp'));
      }, values: overrides());
    });

    test('silent when a compiled host is stamped', () {
      runScoped(() {
        expect(
          hostContractUnknownReason(
            isCompiled: true,
            readStamp: (_) => 'abc123',
          ),
          isNull,
        );
      }, values: overrides());
    });

    // A compiled host answers from its own stamp and never from the sources on
    // disk -- they have moved on independently and say nothing about what it
    // was compiled against. Asserting it here keeps this in lockstep with
    // [hostMessageContractHash], which the message would otherwise contradict.
    test('a stamped compiled host does not consult the sources', () {
      runScoped(() {
        expect(
          hostContractUnknownReason(
            isCompiled: true,
            readStamp: (_) => 'abc123',
          ),
          isNull,
        );
      }, values: overrides(hash: null));
    });
  });
}
