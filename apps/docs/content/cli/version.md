---
title: zonai version
description: Check and update the Zonai CLI version.
---

## zonai version

Print the currently installed version:

```sh
zonai version
# zonai 0.1.0
```

## version check

Check whether a newer version is available:

```sh
zonai version check
```

Prints the current version and the latest available version. Does not install anything.

## version update

Download and install the latest version of the CLI in place:

```sh
zonai version update
```

After updating, confirm the new version with `zonai version`.

## After Updating

Recompile your workers after a CLI update — new versions may update the worker API:

```sh
zonai compile
```
