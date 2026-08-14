import 'package:revali_client/revali_client.dart';

import 'zonai_storage_resolve_stub.dart'
    if (dart.library.io) 'zonai_storage_resolve_io.dart'
    as impl;

/// Resolves the [Storage] for [ZonaiClient] construction.
Storage resolveZonaiStorage({String? storageDirectory, Storage? storage}) =>
    impl.resolveZonaiStorage(
      storageDirectory: storageDirectory,
      storage: storage,
    );
