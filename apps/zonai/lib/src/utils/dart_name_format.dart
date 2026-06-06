/// Formats user input into a valid Dart class name (PascalCase).
String formatDartClassName(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return trimmed;

  final expanded = trimmed.replaceAllMapped(
    RegExp(r'([a-z0-9])([A-Z])'),
    (match) => '${match[1]} ${match[2]}',
  );

  return expanded
      .split(RegExp(r'[^a-zA-Z0-9]+'))
      .where((part) => part.isNotEmpty)
      .map(
        (part) => '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
      )
      .join();
}

/// Converts PascalCase to snake_case (e.g. `UserOperations` → `user_operations`).
String pascalToSnake(String input) {
  return input
      .replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (match) => '${match[1]}_${match[2]}',
      )
      .replaceAllMapped(
        RegExp(r'([A-Z]+)([A-Z][a-z])'),
        (match) => '${match[1]}_${match[2]}',
      )
      .toLowerCase();
}

/// Derives a cron job name from a class name (e.g. `CleanupUsersCron` → `cleanup_users`).
String cronNameFromClassName(String className) {
  var name = className;
  if (name.endsWith('Cron')) {
    name = name.substring(0, name.length - 4);
  }
  return pascalToSnake(name);
}
