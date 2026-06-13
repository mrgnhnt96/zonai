import 'package:zonai_client/gen/interfaces.dart';
import 'package:zonai_schema/payloads.dart';

class Emails {
  const Emails({required this._email});

  final EmailDataSource _email;

  Future<void> send({required Email body}) async {
    await _email.send(body: body);
  }

  Future<void> sendOtp({required SendOtpEmail email}) async {
    await send(body: email);
  }

  Future<void> sendMagicLink({required SendMagicLinkEmail email}) async {
    await send(body: email);
  }

  Future<void> sendVerifyEmail({required SendVerifyEmailEmail email}) async {
    await send(body: email);
  }

  Future<void> sendPasswordReset({
    required SendResetPasswordEmail email,
  }) async {
    await send(body: email);
  }
}
