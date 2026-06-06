import 'package:mustache_template/mustache_template.dart';

import '../deps/fs.dart';
import '../deps/settings.dart';

/// Renders an email template with Mustache using the same rules as [Courier].
String renderEmailTemplate({
  required String templateName,
  required Map<String, dynamic> variables,
  required String appName,
  String? emailTemplatesPath,
}) {
  final file = fs.file(
    fs.path.join(
      emailTemplatesPath ?? settings.emailTemplatesPath,
      '$templateName.html',
    ),
  );

  if (!file.existsSync()) {
    throw Exception(
      'Email template not found: ${file.path} (cwd: ${fs.currentDirectory.path})',
    );
  }

  final source = file.readAsStringSync();
  return Template(
    source,
    name: templateName,
    lenient: true,
  ).renderString({...variables, 'appName': appName});
}
