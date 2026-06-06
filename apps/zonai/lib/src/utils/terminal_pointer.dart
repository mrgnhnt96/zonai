import 'package:nocterm/nocterm.dart';

/// OSC 22 mouse pointer shapes for terminal emulators that support them.
///
/// See https://sw.kovidgoyal.net/kitty/pointer-shapes/
abstract final class TerminalPointerShape {
  static const defaultShape = 'default';
  static const pointer = 'pointer';
  static const text = 'text';
}

/// Updates the OS mouse pointer while hovering interactive TUI regions.
///
/// Uses Kitty's OSC 22 stack (`>shape` on enter, `<` on exit) so nested
/// regions restore the previous shape instead of snapping to default.
abstract final class TerminalPointer {
  static void push(String shape) {
    _write('\x1b]22;>$shape\x1b\\');
  }

  static void pop() {
    _write('\x1b]22;<\x1b\\');
  }

  static void reset() {
    _write('\x1b]22;${TerminalPointerShape.defaultShape}\x1b\\');
  }

  static void _write(String sequence) {
    TerminalBinding.instance.terminal.backend.writeRaw(sequence);
  }
}
