/// One line describing a standing forced-password-reset requirement.
///
/// A pure function, and separated from the panel for the reason
/// `admin_members.dart` is: these are DECISIONS about a wire payload — which
/// reason wording, what to say when the server sent a value this build has
/// never heard of, who to name as the setter — and they are testable without
/// pumping a 2000-line stateful component through an async fetch.
///
/// [requirement] is the `requirement` object from
/// `GET /admin/members/:email/require-password-reset`:
/// `{reason, createdAt, createdBy}`.
String passwordResetRequirementSummary(Map<String, Object?> requirement) {
  final reason = switch (requirement['reason']) {
    'temporaryPassword' => 'the current password was set by someone else',
    'compromised' => 'the password may be known to someone else',
    'passwordPolicy' => 'a password policy',
    'adminForced' => 'an administrator',
    // A newer server may send a reason this build has never heard of. Rendering
    // the raw identifier would leak an implementation name into the UI, and
    // guessing at wording would be worse — so the sentence stays true without
    // it.
    _ => null,
  };

  final by = switch (requirement['createdBy']) {
    // `'cli'` is what `zonai db admin` writes; every other value is an admin's
    // account id. Naming the CLI matters: it is the difference between "one of
    // us did this in the dashboard" and "someone was on the server box".
    'cli' => 'Set from the command line',
    final String id when id.isNotEmpty => 'Set by $id',
    // Null is not a placeholder for an unknown admin — nothing that sets a
    // requirement omits it, so a null here means a row written by a path that
    // forgot to say, and claiming an author would be a fabrication.
    _ => 'Set by an unrecorded caller',
  };

  final when = switch (requirement['createdAt']) {
    final String raw when DateTime.tryParse(raw) != null => ' on ${_day(DateTime.parse(raw).toLocal())}',
    _ => '',
  };

  return switch (reason) {
    null => '$by$when.',
    final r => '$by$when — $r.',
  };
}

String _day(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}
