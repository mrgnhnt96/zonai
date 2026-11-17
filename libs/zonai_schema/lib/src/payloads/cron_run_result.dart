/// What one `POST /crons/run` did.
///
/// [changes] counts the rows the run wrote, by table and then by action
/// (`create`, `update`, `delete`): every `mutate` the job queued, plus any
/// write a hook on those tables queued in turn. An update or delete that
/// matched no row is not counted. The writes are committed before this is
/// answered, so a caller can read the rows straight after.
///
/// A failed run still reports what it wrote before it failed: those writes
/// are committed too, exactly as a scheduled run's are.
class CronRunResult {
  const CronRunResult({
    required this.name,
    required this.ok,
    required this.ms,
    this.changes = const {},
    this.error,
  });

  factory CronRunResult.fromJson(Map<String, dynamic> json) {
    return CronRunResult(
      name: json['name'] as String,
      ok: json['ok'] as bool,
      ms: (json['ms'] as num).toInt(),
      changes: switch (json['changes']) {
        final Map<Object?, Object?> changes => {
          for (final MapEntry(:key, :value) in changes.entries)
            if (value is Map<Object?, Object?>)
              '$key': {
                for (final action in value.entries)
                  if (action.value case final num count)
                    '${action.key}': count.toInt(),
              },
        },
        _ => const {},
      },
      error: json['error'] as String?,
    );
  }

  final String name;

  /// False when the job threw, or there is no job called [name].
  final bool ok;

  /// How long the run took, in milliseconds, including committing its writes.
  final int ms;

  /// Rows written, as `{table: {action: count}}`.
  final Map<String, Map<String, int>> changes;

  /// Why the run failed, when [ok] is false.
  final String? error;

  Map<String, dynamic> toJson() => {
    'name': name,
    'ok': ok,
    'ms': ms,
    'changes': changes,
    if (error != null) 'error': error,
  };
}
