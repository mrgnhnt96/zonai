part of '../../interfaces.dart';

abstract interface class PushDataSource {
  const PushDataSource();

  Future<PushTestSendResult> sendTest({
    required PushTestSendBody body,
    String? authorization,
  });
}
