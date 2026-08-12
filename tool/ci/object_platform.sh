#!/usr/bin/env bash
# Reads the platform a shared library was built for out of its object-file
# header. Sourced by cross_target_build.sh and verify_cross_target_bundle.sh.
#
# Deliberately not `file`: it is absent from slim container images (the run half
# found this the hard way), and its wording differs between the macOS and Linux
# builds of it, so matching on the description couples the gate to which host
# happens to be running. The magic numbers do not move.
#
# This is the shell counterpart of apps/zonai/lib/src/domain/native_library_format.dart,
# which is what the guard itself uses. Two implementations of one table is a
# real cost; the alternative is a gate that can only run where a compiled zonai
# already works, which is the thing being tested.

# Echoes one of: linux/x64, linux/arm64, macos/arm64, macos/x64, windows/x64,
# windows/arm64, or unknown.
object_platform() {
  local path="$1"
  local head
  # 20 bytes covers ELF's e_machine at offset 18; Mach-O needs 8.
  head="$(od -An -tx1 -N20 "$path" 2>/dev/null | tr -d ' \n')"

  case "$head" in
    7f454c46*)
      # e_ident[EI_CLASS] must be 2 (64-bit); e_machine is bytes 18-19, LE.
      if [[ "${head:8:2}" != "02" ]]; then
        echo unknown
        return
      fi
      case "${head:36:4}" in
        3e00) echo linux/x64 ;;
        b700) echo linux/arm64 ;;
        *) echo unknown ;;
      esac
      ;;
    cffaedfe*)
      # 64-bit little-endian Mach-O; cputype is bytes 4-7, LE.
      case "${head:8:8}" in
        0c000001) echo macos/arm64 ;;
        07000001) echo macos/x64 ;;
        *) echo unknown ;;
      esac
      ;;
    4d5a*) echo windows/unknown ;;
    *) echo unknown ;;
  esac
}
