part of zonai_db;

extension _RunWebhookX on ZonaiDb {
  /// Runs the webhook called [name] on one delivery.
  ///
  /// Not gated on a caller: the route is unauthenticated by design, and the
  /// handler is what checks the sender. Its writes are held until it answers,
  /// then committed on the write chain -- never held across the handler
  /// itself, which may wait on the network for as long as it likes.
  Future<HandleWebhookResponse> _runWebhook({
    required String name,
    required Uint8List body,
    required Map<String, String> headers,
    required String ip,
  }) async {
    final mailman = WebhookMailman();
    final HandleWebhookResponse response;
    try {
      response = await mailman.send<HandleWebhookResponse>(
        HandleWebhookRequest(name: name, body: body, headers: headers, ip: ip),
      );
    } finally {
      await mailman.kill(failPending: false);
    }

    final pending = mutations.extract;
    if (pending.isNotEmpty) {
      await _runWrite(() async {
        mutations.addAll(pending);
        await _executeEffects();
      });
    }

    return response;
  }
}
