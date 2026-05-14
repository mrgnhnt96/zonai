# Scoped Deps

A simple dependency injection library built on Zones.

`read` resolves bindings from an internal registration table that tracks each
[`Zone`] established by this library, so it is not fooled by [`Zone`]'s
inherited `[]` behavior (which can copy a parent's [ScopedRef] into a middle
zone and mask a child's override). For subprocess or other IO that may resume
outside that zone, combine with [`Zone.bindUnaryCallback`] (or related APIs)
when registering native callbacks.

## Quick Start

```dart
import 'package:scoped_deps/scoped_deps.dart';

final value = create(() => 42);

void main() {
  runScoped(scopeA, values: {value});
}

void scopeA() {
  print(read(value)); // 42
  runScoped(scopeB, values: {value.overrideWith(() => 0)});
}

void scopeB() {
  print(read(value)); // 0
}
```
