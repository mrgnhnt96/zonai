part of '../../interfaces.dart';

abstract interface class EmailDataSource {
  const EmailDataSource();

  Future<void> send({required Email body, String? authorization});
}
