/// VM-only file-backed [Storage] for [ZonaiClient].
///
/// Not exported from `package:zonai_client/zonai_client.dart` so web apps can
/// depend on `zonai_client` without pulling `package:file` into the browser build.
library;

export 'src/utils/zonai_file_storage.dart';
