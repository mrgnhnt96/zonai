import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/api/api_client.dart';

import '../api/push_client.dart' as api;
import '../utils/push_test_targets.dart';
import '../utils/user_facing_error.dart';

/// The test-send form, and what the last send reported.
final pushTestProvider = NotifierProvider<PushTestNotifier, PushTestState>(PushTestNotifier.new);

/// What one finished send is shown as.
///
/// [result] is kept whole rather than reduced to a sentence at the moment of
/// arrival, so the panel can style a rejection differently from an acceptance
/// and still render the provider's words. [error] is the separate case where
/// the request itself failed — a refused gate, a dead server — and never
/// carries a per-recipient meaning.
final class PushTestState {
  const PushTestState({
    this.targetId,
    this.token = '',
    this.title = 'Test notification',
    this.body = 'Sent from the Zonai dashboard.',
    this.platform,
    this.isSending = false,
    this.result,
    this.error,
  });

  /// [PushTestTarget.id] of the selected target, or null for "the first one".
  final String? targetId;

  final String token;
  final String title;
  final String body;

  /// Null means FCM, which is what a fan-out with no platform column does.
  final DevicePlatform? platform;

  final bool isSending;

  /// The last send's outcome, kept until another send starts.
  final PushTestSendResult? result;

  /// The last send's *transport-level* failure — the request never produced an
  /// outcome. Distinct from a [result] whose status is `failed`, which is an
  /// answer about the send rather than about the request.
  final String? error;

  bool get canSend => !isSending && token.trim().isNotEmpty && title.trim().isNotEmpty;

  PushTestState copyWith({
    String? targetId,
    String? token,
    String? title,
    String? body,
    DevicePlatform? platform,
    bool clearPlatform = false,
    bool? isSending,
    PushTestSendResult? result,
    String? error,
    bool clearOutcome = false,
  }) {
    return PushTestState(
      targetId: targetId ?? this.targetId,
      token: token ?? this.token,
      title: title ?? this.title,
      body: body ?? this.body,
      platform: clearPlatform ? null : (platform ?? this.platform),
      isSending: isSending ?? this.isSending,
      result: clearOutcome ? null : (result ?? this.result),
      error: clearOutcome ? null : (error ?? this.error),
    );
  }
}

class PushTestNotifier extends Notifier<PushTestState> {
  @override
  PushTestState build() => const PushTestState();

  void selectTarget(String id) => state = state.copyWith(targetId: id, clearOutcome: true);

  void setToken(String value) => state = state.copyWith(token: value);

  void setTitle(String value) => state = state.copyWith(title: value);

  void setBody(String value) => state = state.copyWith(body: value);

  /// Null selects FCM, matching a fan-out with no platform column.
  void setPlatform(DevicePlatform? value) {
    state = value == null
        ? state.copyWith(clearPlatform: true, clearOutcome: true)
        : state.copyWith(platform: value, clearOutcome: true);
  }

  Future<void> send(PushTestTarget target) async {
    if (!state.canSend) return;

    // The previous outcome is cleared before the request rather than
    // overwritten after it. Leaving a green "accepted" on screen while the
    // next send is in flight invites reading it as the new answer.
    state = state.copyWith(isSending: true, clearOutcome: true);

    try {
      final result = await api.sendTestPush(
        server: ref.read(revaliServerProvider),
        target: (table: target.table, column: target.column),
        token: state.token.trim(),
        title: state.title.trim(),
        body: state.body.trim(),
        platform: state.platform,
      );

      state = state.copyWith(isSending: false, result: result);
    } catch (error) {
      state = state.copyWith(isSending: false, error: userFacingError(error));
    }
  }
}
