// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'dart:async';

/// A future that is called once and then cached internally.
abstract mixin class CachedFuture<V> implements Future<V> {
  /// The future "creator".
  Future<V> toFuture();

  @override
  Stream<V> asStream() => _cache.asStream();

  @override
  Future<V> catchError(
    Function onError, {
    bool Function(Object error)? test,
  }) {
    return _cache.catchError(onError, test: test);
  }

  @override
  Future<R> then<R>(
    FutureOr<R> Function(V value) onValue, {
    Function? onError,
  }) {
    return _cache.then(onValue, onError: onError);
  }

  @override
  Future<V> timeout(
    Duration timeLimit, {
    FutureOr<V> Function()? onTimeout,
  }) {
    return _cache.timeout(timeLimit, onTimeout: onTimeout);
  }

  @override
  Future<V> whenComplete(FutureOr<void> Function() action) {
    return _cache.whenComplete(action);
  }

  late final Future<V> _cache = toFuture();
}
