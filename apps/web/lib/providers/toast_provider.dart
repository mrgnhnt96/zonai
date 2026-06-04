import 'dart:async';

import 'package:jaspr_riverpod/jaspr_riverpod.dart';

enum ToastVariant { error, success }

final class ToastMessage {
  const ToastMessage({
    required this.id,
    required this.text,
    this.variant = ToastVariant.error,
  });

  final int id;
  final String text;
  final ToastVariant variant;
}

final toastProvider = NotifierProvider<ToastNotifier, ToastMessage?>(ToastNotifier.new);

class ToastNotifier extends Notifier<ToastMessage?> {
  Timer? _dismissTimer;
  var _nextId = 0;

  @override
  ToastMessage? build() {
    ref.onDispose(() => _dismissTimer?.cancel());
    return null;
  }

  void showError(String text) => _show(ToastVariant.error, text);

  void showSuccess(String text) => _show(ToastVariant.success, text);

  void _show(ToastVariant variant, String text) {
    _dismissTimer?.cancel();
    final message = ToastMessage(id: ++_nextId, text: text, variant: variant);
    state = message;
    _dismissTimer = Timer(const Duration(seconds: 5), () {
      if (state?.id == message.id) {
        state = null;
      }
    });
  }

  void dismiss() {
    _dismissTimer?.cancel();
    state = null;
  }
}
