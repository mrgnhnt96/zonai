part of '../message_handler.dart';

typedef _RequestNativeLibrary =
    Future<String?> Function(NativeLibraryKind library);

final _nativeLibraryRequestProvider = create<_NativeLibrary>(_NativeLibrary._);

/// Asks whatever spawned this worker to confirm/refresh its shared native
/// library install path (see [NativeLibraryRequest]).
///
/// Only registered with a real implementation for the lifetime of a
/// worker's [MessageHandler.listen] loop (mirrors how [get] is wired up
/// below). Reading it from the top-level `zonai` process -- which has no
/// spawner above it -- throws (no scope registers this provider there),
/// which callers use as the "nobody to ask, self-extract instead" signal.
_NativeLibrary get nativeLibraryHost => read(_nativeLibraryRequestProvider);

class _NativeLibrary {
  _NativeLibrary._() {
    request = (library) async => null;
  }

  _NativeLibrary(this.request);

  late final _RequestNativeLibrary request;
}
