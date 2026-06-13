import 'package:revali_client/revali_client.dart';

import 'zonai_file_storage.dart';
import 'zonai_storage_memory.dart';

Storage resolveZonaiStorage({String? storageDirectory, Storage? storage}) {
  if (storage != null) {
    return storage;
  }

  if (storageDirectory != null && storageDirectory.isNotEmpty) {
    return ZonaiFileStorage(directory: storageDirectory);
  }

  return ZonaiStorage.memory();
}
