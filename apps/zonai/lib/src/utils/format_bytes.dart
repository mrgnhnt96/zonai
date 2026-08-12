const _units = ['B', 'KB', 'MB', 'GB', 'TB'];

/// Formats a byte count for human consumption, e.g. `852.8 MB`.
///
/// Uses decimal units (1 KB = 1000 B) to match what macOS Finder and `ls -lh`
/// report, so a size printed here lines up with what an operator sees when
/// they go and look at the file themselves.
String formatBytes(int bytes) {
  if (bytes < 0) return '-${formatBytes(-bytes)}';
  if (bytes < 1000) return '$bytes B';

  var value = bytes.toDouble();
  var unit = 0;

  while (value >= 1000 && unit < _units.length - 1) {
    value /= 1000;
    unit++;
  }

  return '${value.toStringAsFixed(1)} ${_units[unit]}';
}
