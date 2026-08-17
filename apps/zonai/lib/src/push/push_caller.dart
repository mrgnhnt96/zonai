/// Where an enqueue request came from.
///
/// `push` is authorized by **provenance, not identity**. The reachable surface
/// is exactly one thing: developer-authored Dart in an extension hook or a
/// cron job, arriving over the worker IPC. Nothing else can construct an
/// `EnqueuePushRequest`, and the `push` global throws outside those scopes.
///
/// So the question at the entry point is "did this come from the project's own
/// server code", never "is the end user an admin". Asking the second one was a
/// real bug: extension requests carry the *caller's* jwt, so `push` from the
/// `afterCreateSuccess` hook the docs prescribe threw
/// `TableAccessDeniedException` for every non-admin user — after the write had
/// already committed. It only worked from crons, which travel under `CronJwt`,
/// and on `AsAdmin` tables, which is how it stayed hidden.
///
/// **This type is a signpost, not a wall, and saying so is the point.** Dart's
/// only hard boundary is library privacy, and the one production call site
/// lives in a different library of this same package, so [serverCode] has to
/// be public and any future caller could pass it. What actually holds the
/// boundary is `push_entry_point_test.dart`, which fails when a call site
/// appears that is not on its list. Read that test before adding one.
final class PushCaller {
  const PushCaller._(this.label);

  /// An extension hook or a cron job, relayed by the host's IPC handler.
  static const serverCode = PushCaller._('server_code');

  final String label;

  @override
  String toString() => 'PushCaller.$label';
}
