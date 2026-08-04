import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// Result of [mergePathOverrides]: which packages got a `path:` override
/// written or refreshed, and which were left alone because something other
/// than [RaindropSync] already owns that key.
class OverrideMergeResult {
  const OverrideMergeResult({
    required this.content,
    required this.changed,
    required this.applied,
    required this.skipped,
  });

  /// The full, possibly-updated `pubspec_overrides.yaml` text.
  final String content;

  /// Whether [content] differs from the input.
  final bool changed;

  /// Packages whose `dependency_overrides.<name>.path` is now [content]'s.
  final Map<String, String> applied;

  /// Packages left untouched because a human (or another tool) already owns
  /// that override key with a value we didn't write.
  final Map<String, String> skipped;
}

/// Surgically merges `dependency_overrides: <name>: {path: <path>}` entries
/// for [desired] into [existingContent] (a `pubspec_overrides.yaml`'s
/// current text, or `''`/whitespace if the file doesn't exist yet).
///
/// Never clobbers an override this function didn't itself write last time
/// (tracked via [previouslyOwned], typically the prior sync stamp) --
/// hand-authored or otherwise-sourced overrides for the same package name
/// are left alone and reported in [OverrideMergeResult.skipped].
OverrideMergeResult mergePathOverrides(
  String existingContent, {
  required Map<String, String> desired,
  required Map<String, String> previouslyOwned,
}) {
  final isEmpty = existingContent.trim().isEmpty;
  final parsed = isEmpty ? null : loadYaml(existingContent);

  if (parsed != null && parsed is! Map) {
    // Root isn't a map at all -- a malformed pubspec_overrides.yaml. Don't
    // guess at a rewrite; leave it untouched.
    return OverrideMergeResult(
      content: existingContent,
      changed: false,
      applied: const {},
      skipped: Map.of(desired),
    );
  }

  final editor = YamlEditor(existingContent);
  final currentOverrides = (parsed is Map && parsed['dependency_overrides'] is Map)
      ? parsed['dependency_overrides'] as Map
      : null;

  final applied = <String, String>{};
  final skipped = <String, String>{};
  var changed = false;

  if (currentOverrides == null) {
    final wholeSection = {
      for (final entry in desired.entries) entry.key: {'path': entry.value},
    };

    if (parsed == null) {
      // Empty/whitespace-only file -- nothing to preserve, write fresh.
      editor.update([], {'dependency_overrides': wholeSection});
    } else {
      // Non-empty document; `dependency_overrides` is absent, null, or not
      // a map. Either way, safe to set as a brand-new top-level key.
      editor.update(['dependency_overrides'], wholeSection);
    }

    applied.addAll(desired);
    changed = true;
  } else {
    for (final entry in desired.entries) {
      final package = entry.key;
      final path = entry.value;
      final current = currentOverrides[package];

      final isOurs =
          current == null ||
          (current is Map &&
              current.keys.length == 1 &&
              current.containsKey('path') &&
              current['path'] == previouslyOwned[package]);

      if (!isOurs) {
        skipped[package] = path;
        continue;
      }

      final alreadyCorrect =
          current is Map &&
          current.keys.length == 1 &&
          current.containsKey('path') &&
          current['path'] == path;

      if (!alreadyCorrect) {
        editor.update(['dependency_overrides', package], {'path': path});
        changed = true;
      }
      applied[package] = path;
    }
  }

  return OverrideMergeResult(
    content: editor.toString(),
    changed: changed,
    applied: applied,
    skipped: skipped,
  );
}
