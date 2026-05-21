import 'package:zonai/src/deps/zonai_db.dart';
import 'package:zonai_schema/zonai_schema.dart';

class EmailHandler {
  const EmailHandler();

  Future<void> send(Email email) async {
    await zonaiDB.sendEmail(email);
  }
}
