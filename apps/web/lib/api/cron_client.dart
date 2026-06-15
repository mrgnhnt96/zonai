import 'package:zonai_client/server.dart';

Future<void> runCronJob({required Server server, required String name}) {
  return server.cron.run(name: name);
}
