import 'package:revali_client/revali_client.dart';

import 'zonai_storage_memory.dart';

Storage resolveZonaiStorage({String? storageDirectory, Storage? storage}) {
  if (storage != null) {
    return storage;
  }

  if (storageDirectory != null && storageDirectory.isNotEmpty) {
    throw UnsupportedError(
      'File-backed storage is not available on this platform. Pass an explicit '
      'Storage via the storage: parameter (e.g. ZonaiCookieStorage in the web '
      'app, or ZonaiFileStorage from package:zonai_client/storage.dart on VM).',
    );
  }

  return ZonaiStorage.memory();
}
