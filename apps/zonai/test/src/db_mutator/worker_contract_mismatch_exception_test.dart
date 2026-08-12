import 'package:file/memory.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/db_mutator/worker_contract_mismatch_exception.dart';
import 'package:zonai/src/deps/fs.dart';

void main() {
  group('WorkerContractMismatchException.forStamp', () {
    late MemoryFileSystem memoryFs;

    Set<ScopedRef<dynamic>> overrides() => {
      fsProvider.overrideWith(() => memoryFs),
    };

    setUp(() {
      memoryFs = MemoryFileSystem();
    });

    final hostHash = 'a' * 64;
    final workerHash = 'b' * 64;

    void stampWorker(String contract) {
      fs.file('/exes/db_rate_limit.exe.contract')
        ..createSync(recursive: true)
        ..writeAsStringSync(contract);
    }

    WorkerContractMismatchException? build({String? hostContract}) {
      return WorkerContractMismatchException.forStamp(
        workerName: 'RATE_LIMITS',
        executablePath: '/exes/db_rate_limit.exe',
        hostContract: hostContract ?? hostHash,
      );
    }

    test('null when the worker has no stamp', () {
      runScoped(() {
        expect(build(), isNull);
      }, values: overrides());
    });

    test('null when the host contract is unknown', () {
      runScoped(() {
        stampWorker(workerHash);
        expect(
          WorkerContractMismatchException.forStamp(
            workerName: 'RATE_LIMITS',
            executablePath: '/exes/db_rate_limit.exe',
            hostContract: null,
          ),
          isNull,
        );
      }, values: overrides());
    });

    test('null when the stamps agree', () {
      runScoped(() {
        stampWorker(hostHash);
        expect(build(), isNull);
      }, values: overrides());
    });

    // Every requirement on this guard is a requirement on what the text says,
    // so a test that only checked the exception type would leave the point of
    // it untested.
    group('when the stamps disagree, the message', () {
      late WorkerContractMismatchException error;

      setUp(() {
        runScoped(() {
          stampWorker(workerHash);
          error = build()!;
        }, values: overrides());
      });

      test('names the worker and its path on disk', () {
        expect(error.message, contains('RATE_LIMITS'));
        expect(error.message, contains('/exes/db_rate_limit.exe'));
      });

      test('shows both sides', () {
        expect(error.message, contains('b' * 12));
        expect(error.message, contains('a' * 12));
        expect(error.workerContract, workerHash);
        expect(error.hostContract, hostHash);
      });

      test('says why it happened in terms of something the reader did', () {
        expect(error.message, contains('zonai_schema'));
        expect(error.message, contains('newer CLI'));
        expect(error.message, contains('older build directory'));
      });

      test(
        'gives the command, and distinguishes dev from a deployed bundle',
        () {
          expect(error.message, contains('zonai compile'));
          expect(error.message, contains('zonai build'));
          expect(error.message, contains('redeploy'));
        },
      );

      test('links the upgrade docs', () {
        expect(error.message, contains('https://docs.zonai.dev/cli/upgrading'));
      });

      // The framing check would have passed this worker, and the reader needs
      // to know that is not a contradiction.
      test('says the framing is not what changed', () {
        expect(error.message, contains('wire format still matches'));
      });

      test('is what toString gives, so an uncaught throw still reads', () {
        expect('$error', error.message);
      });
    });
  });
}
