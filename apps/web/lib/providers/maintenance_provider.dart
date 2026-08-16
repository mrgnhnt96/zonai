import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/api/api_client.dart';

import '../api/maintenance_client.dart';

/// Storage usage, loaded client-side.
///
/// Not polled: collection is expensive (a `df` spawn, a recursive walk of the
/// photos directory, two pragma round trips per database file), and disk usage
/// does not move on the timescale a poll would catch. It refreshes when an
/// operator asks it to.
final storageMetricsProvider = AsyncNotifierProvider<StorageMetricsNotifier, StorageMetrics?>(
  StorageMetricsNotifier.new,
);

class StorageMetricsNotifier extends AsyncNotifier<StorageMetrics?> {
  @override
  Future<StorageMetrics?> build() async {
    // SSR has no frames, so an async provider that completes after the server
    // render has nothing to notify (see the comment in dashboard_screen.dart).
    if (!ref.binding.isClient) return null;

    return await fetchStorageMetrics(server: ref.read(revaliServerProvider));
  }

  void refresh() => ref.invalidateSelf();
}

/// How a byte count renders when the number is not known.
///
/// `freeDiskBytes` returns `null` for *unknown* and never zero — an unparsed
/// `df` and a full disk are opposite situations. Rendering unknown as "0 B"
/// would report an emergency that is not happening, while hiding that the
/// value was never read, so unknown gets a word of its own.
const kUnknownSize = 'unknown';

/// [formatBytes] for a known count, [kUnknownSize] for `null`.
String formatOptionalBytes(int? bytes) => bytes == null ? kUnknownSize : formatBytes(bytes);
