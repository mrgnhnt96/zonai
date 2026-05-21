import 'dart:async';

import 'package:meta/meta.dart';

/// Parallel to [Zone] zoneValues, but **without** using [Zone.]'s `[]` lookup.
///
/// Dart's [Zone] inherits missing keys from the parent and **writes that
/// inherited value into the current zone's map**. A later child fork with an
/// override for the same key can then be skipped because the middle zone
/// incorrectly holds the parent's [ScopedRef]. [read] consults this table
/// first, walking [Zone.parent], so only **explicit** scoped-deps registrations
/// win.
final Expando<Map<Object?, ScopedRef<dynamic>>> _scopedDepsDirect =
    Expando<Map<Object?, ScopedRef<dynamic>>>('package:scoped_deps/direct');

void _registerDirect(Zone zone, Map<Object?, Object?> zoneValues) {
  if (zoneValues.isEmpty) return;
  final incoming = <Object?, ScopedRef<dynamic>>{};
  for (final e in zoneValues.entries) {
    if (e.value is ScopedRef) {
      incoming[e.key] = e.value as ScopedRef<dynamic>;
    }
  }
  if (incoming.isEmpty) return;
  final prior = _scopedDepsDirect[zone];
  _scopedDepsDirect[zone] = prior == null ? incoming : {...prior, ...incoming};
}

bool _chainDefinesRefKey(Object? key) {
  Zone? z = Zone.current;
  while (z != null) {
    final m = _scopedDepsDirect[z];
    if (m != null && m.containsKey(key)) return true;
    z = z.parent;
  }
  return false;
}

ScopedRef<T>? _lookupRef<T>(ScopedRef<T> ref) {
  Zone? z = Zone.current;
  while (z != null) {
    final m = _scopedDepsDirect[z];
    if (m != null && m.containsKey(ref._key)) {
      return m[ref._key]! as ScopedRef<T>;
    }
    z = z.parent;
  }
  return null;
}

/// {@template scoped_ref}
/// A reference to a scoped value.
/// {@endtemplate}
@immutable
class ScopedRef<T> {
  /// {@macro scoped_ref}
  ScopedRef(this._create) : _key = Object();

  ScopedRef._(T Function() create, Object key) : _create = create, _key = key;

  final T Function() _create;
  final Object _key;
  late final T _value = _create();

  /// [Object] used as a [Zone] zoneValues key for this ref.
  ///
  /// Prefer [runScoped] / [runMergedScoped] / [runMergedScopedFuture] over
  /// manual [Zone.fork]: they also register bindings for [read] in a way that
  /// avoids mistaken inheritance of a parent's ref (see package implementation).
  Object get zoneKey => _key;

  /// Overrides the value of the current [ScopedRef]
  /// with the provided [create].
  ScopedRef<T> overrideWith(T Function() create) {
    return ScopedRef<T>._(create, _key);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (runtimeType != other.runtimeType) return false;
    if (other is ScopedRef<T>) return _key == other._key;
    return false;
  }

  @override
  int get hashCode => _key.hashCode;
}

/// Creates a [ScopedRef] which can later be used to access the
/// value, [T] returned by [create].
ScopedRef<T> create<T>(T Function() create) => ScopedRef<T>(create);

bool isRegistered(ScopedRef<dynamic> ref) {
  return Zone.current[ref._key] != null;
}

/// Attempts to retrieve the value for the [ref].
/// If [read] is called with a [ref] which is not available
/// in the current scope, a [StateError] will be thrown.
T read<T>(ScopedRef<T> ref, {T Function()? orElse}) {
  final direct = _lookupRef(ref);
  if (direct != null) {
    return direct._value;
  }
  final legacyRef = Zone.current[ref._key] as ScopedRef<T>?;
  if (legacyRef != null) {
    return legacyRef._value;
  }
  if (orElse != null) return orElse();
  throw StateError('''
read(ScopedRef<$T>) was called in a scope which does not contain a corresponding value for the provided ref.
Did you forget to call: runScoped(() {...}, values: {value})?''');
}

/// Runs [body] within a scope which has access to the set of refs in [values].
R runScoped<R>(R Function() body, {Set<ScopedRef<dynamic>> values = const {}}) {
  final zoneValues = {for (final value in values) value._key: value};
  return runZoned(() {
    _registerDirect(Zone.current, zoneValues);
    return body();
  }, zoneValues: zoneValues);
}

/// Runs [body] in a scope that merges with the enclosing zone.
///
/// Implementation uses [Zone.current.fork]: the child zone inherits every stored
/// value from the current zone; only keys produced from [override] and
/// [includeIfAbsent] are added or replaced (same semantics as [runZoned]).
///
/// [override] binds each ref's key to that ref, replacing any value from an
/// outer scope for the same key.
///
/// [includeIfAbsent] binds refs whose keys are not already present in the
/// current zone (including outer scopes). Keys listed in [override] are not
/// considered absent for this purpose.
///
/// **Async:** If [body] returns a [Future] immediately (for example
/// `() => doWork()` where `doWork` is `async`), this call still ends as soon as
/// that future is *returned*—the merged zone does not wrap `await`s inside it.
/// Use [runMergedScopedFuture] when the scoped values must remain current for an
/// entire async computation.
Map<Object?, Object?> _mergedZoneValues({
  Set<ScopedRef<dynamic>> override = const {},
  Set<ScopedRef<dynamic>> includeIfAbsent = const {},
}) {
  final overrideKeys = {for (final r in override) r._key};
  final zoneValues = <Object?, Object?>{};
  for (final ref in includeIfAbsent) {
    if (overrideKeys.contains(ref._key)) continue;
    if (_chainDefinesRefKey(ref._key)) continue;
    zoneValues[ref._key] = ref;
  }
  for (final ref in override) {
    zoneValues[ref._key] = ref;
  }
  return zoneValues;
}

R runMergedScoped<R>(
  R Function() body, {
  Set<ScopedRef<dynamic>> override = const {},
  Set<ScopedRef<dynamic>> includeIfAbsent = const {},
}) {
  final zoneValues = _mergedZoneValues(
    override: override,
    includeIfAbsent: includeIfAbsent,
  );
  return Zone.current.fork(zoneValues: zoneValues).run<R>(() {
    _registerDirect(Zone.current, zoneValues);
    return body();
  });
}

/// Like [runMergedScoped], but keeps the merged zone active for every `await`
/// inside [body].
///
/// Implementation runs `() async => await body()` inside the fork so async
/// continuations (listeners, timers, futures, etc.) still see [override] /
/// [includeIfAbsent].
Future<R> runMergedScopedFuture<R>(
  Future<R> Function() body, {
  Set<ScopedRef<dynamic>> override = const {},
  Set<ScopedRef<dynamic>> includeIfAbsent = const {},
}) {
  final zoneValues = _mergedZoneValues(
    override: override,
    includeIfAbsent: includeIfAbsent,
  );
  return Zone.current.fork(zoneValues: zoneValues).run<Future<R>>(() async {
    _registerDirect(Zone.current, zoneValues);
    return await body();
  });
}

/// Runs [body] within a scope which has access to the set of refs in [values].
R? runScopedGuarded<R>(
  R Function() body, {
  required void Function(Object error, StackTrace stack) onError,
  Set<ScopedRef<dynamic>> values = const {},
}) {
  final zoneValues = {for (final value in values) value._key: value};
  return runZonedGuarded(
    () {
      _registerDirect(Zone.current, zoneValues);
      return body();
    },
    onError,
    zoneValues: zoneValues,
  );
}
