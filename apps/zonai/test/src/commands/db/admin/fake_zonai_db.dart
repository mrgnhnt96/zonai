import 'package:file/local.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/gen/version.dart';
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai/src/deps/clean_up.dart';
import 'package:zonai/src/deps/executable_stop.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai/src/domain/settings.dart';

/// Minimal settings [ZonaiDb]'s constructor needs to exist (it eagerly builds
/// a `MailmanPool` per worker kind, each of which reads a compiled-executable
/// path off `settings` at construction time) -- never actually read since
/// [FakeZonaiDb] overrides every method that would dispatch to a worker.
final fakeSettings = Settings(
  path: 'zonai.yaml',
  migrationsPath: '.zonai/migrations',
  dataPath: '.zonai/data',
  schemasPath: 'lib/src/schemas',
  extensionsPath: 'lib/src/extensions',
  rulesPath: 'lib/src/rules',
  operationsPath: 'lib/src/operations',
  configPath: 'lib/src/config',
  emailTemplatesPath: 'lib/src/email_templates',
  rateLimitPath: 'lib/src/rate_limit',
  cronsPath: 'lib/src/crons',
  imagesPath: '.zonai/data/images',
  buildSettings: BuildSettings.current(),
  version: kVersion,
);

/// Constructs a [FakeZonaiDb]. `ZonaiDb`'s constructor (which a subclass
/// can't skip) eagerly builds a `MailmanPool` per worker kind, each of which
/// reaches for `settings`/`fs`/`cleanUp` at construction time -- so even a
/// fake needs a scope providing the same set `bootstrap.dart` registers
/// before constructing a real one, just for the moment of construction.
/// `runScoped` is synchronous, so this can be a plain top-level function
/// rather than something every test has to wrap itself.
FakeZonaiDb newFakeZonaiDb() => runScoped(
  FakeZonaiDb.new,
  values: {
    settingsProvider.overrideWith(() => fakeSettings),
    fsProvider.overrideWith(LocalFileSystem.new),
    cleanUpProvider,
    executableStopProvider,
  },
);

/// A [ZonaiDb] that never touches a real database -- overrides just the
/// admin methods these CLI-layer tests exercise, so `zonai db admin`
/// subcommands can be tested without the full compiled-worker/migration
/// harness the DB layer itself would otherwise require. Construct via
/// [newFakeZonaiDb], not the constructor directly.
class FakeZonaiDb extends ZonaiDb {
  Object? resetAdminPasswordError;
  Map<String, Object?> resetAdminPasswordResult = const {};

  Object? removeAdminError;
  Map<String, Object?> removeAdminResult = const {};

  Object? listAdminsError;
  List<Map<String, Object?>> listAdminsResult = const [];

  ({String email, String newPassword})? resetAdminPasswordCall;
  String? removeAdminCall;
  var listAdminsCalled = false;

  @override
  Future<Map<String, Object?>> resetAdminPassword({
    required String email,
    required String newPassword,
  }) async {
    resetAdminPasswordCall = (email: email, newPassword: newPassword);
    if (resetAdminPasswordError case final error?) throw error;
    return resetAdminPasswordResult;
  }

  @override
  Future<Map<String, Object?>> removeAdmin({required String email}) async {
    removeAdminCall = email;
    if (removeAdminError case final error?) throw error;
    return removeAdminResult;
  }

  @override
  Future<List<Map<String, Object?>>> listAdmins() async {
    listAdminsCalled = true;
    if (listAdminsError case final error?) throw error;
    return listAdminsResult;
  }

  Object? clearLogsError;
  int clearLogsResult = 0;

  /// Set once [clearLogs] runs. The outer option distinguishes "never called"
  /// from "called with no cutoff", which is the difference between
  /// `--older-than` being ignored and it being absent.
  ({DateTime? before})? clearLogsCall;
  var vacuumCalled = false;

  /// One entry per `vacuum` call, in order -- `null` for `main`, a schema
  /// name for an attached database. `_log` lives in its own file now, so
  /// "was a vacuum run" is no longer the same question as "was the right
  /// file rewritten".
  final vacuumedSchemas = <String?>[];

  /// Lets a test stand in for the side effect the real VACUUM has -- shrinking
  /// the file on disk -- so the reclaimed-bytes arithmetic can be asserted.
  void Function()? onVacuum;

  @override
  Future<int> clearLogs({DateTime? before}) async {
    clearLogsCall = (before: before);
    if (clearLogsError case final error?) throw error;
    return clearLogsResult;
  }

  @override
  Future<void> vacuum({String? schema}) async {
    vacuumCalled = true;
    vacuumedSchemas.add(schema);
    onVacuum?.call();
  }
}
