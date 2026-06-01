part of zonai_db;

extension EffectsX on ZonaiDb {
  /// Commits queued worker [MutationRequest]s through rules, operations, and
  /// extensions (same pipeline as HTTP mutations).
  Future<void> commitEffects(List<MutationRequest> pending) async {
    return await _run(() async {
      mutations.addAll(pending);
      await _executeEffects();
    });
  }
}
