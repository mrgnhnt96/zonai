/// Default sample values for common Mustache variables in email templates.
Map<String, String> defaultEmailTemplateVariables() {
  return {
    'name': 'Test User',
    'email': 'user@example.com',
    'verificationUrl': 'https://example.com/verify',
    'magicLinkUrl': 'https://example.com/magic',
    'passwordResetUrl': 'https://example.com/reset',
    'confirmChangeEmailUrl': 'https://example.com/confirm-email',
    'inviteUrl': 'https://example.com/admin/invite',
    'invitedByEmail': 'admin@example.com',
    'otp': '123456',
    'expiresIn': '1 hour',
    'currentEmail': 'user@example.com',
    'newEmail': 'new-user@example.com',
    'signedInAt': DateTime.now().toIso8601String(),
    'location': 'San Francisco, CA',
    'ipAddress': '192.168.1.1',
    'device': 'Chrome on macOS',
    'secureAccountUrl': 'https://example.com/security',
    'preheader': samplePreheader,
  };
}

/// Stand-in inbox preview line for previews and test sends.
///
/// Real sends get theirs from [Email.preheader]; this is only so the hidden
/// block renders with something in it while you are looking at a template.
const samplePreheader = 'This is the preview line shown next to the subject.';

final _mustacheVarPattern = RegExp(r'\{\{[\^#>]?\s*([a-zA-Z_][\w.]*)');

/// Variables the renderer supplies itself, so a template author never fills
/// them in: `appName` comes from the config and `preheader` from the [Email].
const _injectedVariables = {'appName', 'preheader'};

/// Extracts editable Mustache variable names from a template source.
///
/// Variables in [_injectedVariables] are supplied at render time and excluded.
List<String> extractMustacheVariables(String source) {
  final vars = <String>{};
  for (final match in _mustacheVarPattern.allMatches(source)) {
    final name = match.group(1)!;
    if (!_injectedVariables.contains(name)) vars.add(name);
  }
  return vars.toList()..sort();
}

/// Builds default values for the variables used by [templateSource].
Map<String, String> defaultVariablesForTemplate(String templateSource) {
  final defaults = defaultEmailTemplateVariables();
  return {
    for (final name in extractMustacheVariables(templateSource))
      name: defaults[name] ?? '',
  };
}

/// Serializes variables as `key=value` lines for compact editing.
String formatVariableLines(Map<String, String> variables) {
  final entries = variables.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  return entries.map((entry) => '${entry.key}=${entry.value}').join('\n');
}

/// Returns required template variable names that are absent or empty in [values].
List<String> missingTemplateVariableKeys(
  List<String> required,
  Map<String, String> values,
) {
  return [
    for (final name in required)
      if (!values.containsKey(name) || values[name]!.trim().isEmpty) name,
  ];
}

/// Parses `key=value` lines. Unknown keys are kept so custom template vars work.
Map<String, String> parseVariableLines(String input) {
  final result = <String, String>{};
  for (final line in input.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

    final separator = trimmed.indexOf('=');
    if (separator <= 0) continue;

    final key = trimmed.substring(0, separator).trim();
    if (key.isEmpty) continue;

    result[key] = trimmed.substring(separator + 1).trim();
  }
  return result;
}
