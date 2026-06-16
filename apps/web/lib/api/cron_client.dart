import 'package:zonai_client/server.dart';

Future<List<String>> listCronJobs({required Server server}) async {
  final response = await server.cron.list();
  return response.names;
}

Future<void> runCronJob({required Server server, required String name}) {
  return server.cron.run(name: name);
}
