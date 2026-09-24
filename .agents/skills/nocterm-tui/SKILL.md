---
name: nocterm-tui
description: Build terminal UIs with nocterm in this project. Use when writing or modifying the `zonai dev` TUI, or any other nocterm-based component. Covers component model, layout, keyboard input, text fields, scrolling, and exit — with version-specific notes for 0.1.0.
metadata:
  nocterm_version: 0.1.0
---

## Overview

nocterm is a Flutter-inspired TUI framework for Dart. The component model, layout primitives, and state management are directly analogous to Flutter. If you know Flutter, you know nocterm.

**Package**: `nocterm: ^0.1.0` (currently pinned to 0.1.0 in this project)
**Import**: `import 'package:nocterm/nocterm.dart';`

---

## App Lifecycle

```dart
// Entry point — awaiting runApp blocks until the TUI exits
await runApp(const MyApp());
```

`runApp` opens an alternate screen buffer, sets up the event loop, and returns when the app shuts down. Do NOT call `exit()` directly — use the shutdown method below.

### Exiting the app (0.1.0 only)

`shutdownApp()` does **not** exist in 0.1.0. Use:

```dart
TerminalBinding.instance.shutdown();
```

This cleanly exits the event loop so `runApp()` returns (instead of `exit()` bypassing cleanup).

---

## Component Model

```dart
// Stateless
class MyWidget extends StatelessComponent {
  const MyWidget({super.key});

  @override
  Component build(BuildContext context) => Text('hello');
}

// Stateful
class Counter extends StatefulComponent {
  const Counter({super.key});

  @override
  State<Counter> createState() => _CounterState();
}

class _CounterState extends State<Counter> {
  int _count = 0;

  @override
  void initState() { super.initState(); }

  @override
  void dispose() { /* clean up controllers etc */ super.dispose(); }

  @override
  Component build(BuildContext context) {
    return Text('Count: $_count');
  }
}
```

Use `setState(() { ... })` to trigger a rebuild. Use `mounted` to guard async callbacks.

---

## Layout Primitives

All sizing uses **terminal cell units** (1 = 1 character cell). Fractional values (e.g. `0.5`) are valid for padding.

```dart
Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [...],
)

Row(
  mainAxisAlignment: MainAxisAlignment.spaceBetween,
  children: [...],
)

Expanded(flex: 1, child: ...)   // fills remaining space
SizedBox(width: 20, height: 3)  // fixed size
Padding(padding: EdgeInsets.all(1), child: ...)
```

### EdgeInsets
```dart
EdgeInsets.all(2)
EdgeInsets.symmetric(horizontal: 2, vertical: 1)
EdgeInsets.only(left: 1, top: 0.5)
EdgeInsets.zero
```

---

## Container & Decoration

```dart
Container(
  width: 22,              // optional fixed width
  padding: EdgeInsets.all(1),
  decoration: BoxDecoration(
    color: Color(0xFF1F2937),
    border: BoxBorder.all(color: Colors.cyan),
  ),
  child: ...,
)
```

### Borders
```dart
// All sides equal
BoxBorder.all(color: Colors.gray)
BoxBorder.all(color: Colors.cyan, style: BoxBorderStyle.dotted)

// Individual sides
BoxBorder(
  top: BorderSide(color: Color(0xFF374151), width: 1),
  bottom: BorderSide(color: Color(0xFF374151), width: 1),
)
```

---

## Text & Styles

```dart
Text('Hello', style: TextStyle(
  color: Colors.cyan,
  fontWeight: FontWeight.bold,
))

Text('truncated', overflow: TextOverflow.ellipsis)
```

### Named Colors (`Colors.*`)
`black`, `white`, `gray`/`grey`, `red`, `green`, `blue`, `cyan`, `yellow`, `magenta`,
`brightRed`, `brightGreen`, `brightBlue`, `brightCyan`, `brightYellow`, `brightMagenta`, `brightWhite`, `brightBlack`

Also semantic: `Colors.error`, `Colors.success`, `Colors.primary`, `Colors.surface`, `Colors.onSurface`

### Hex Colors
```dart
Color(0xFFRRGGBB)   // alpha is ignored in terminal rendering
```

---

## Keyboard Input

Wrap any subtree in `Focusable` to receive key events. Return `true` to consume the event (stop propagation), `false` to let it continue.

```dart
Focusable(
  focused: true,
  onKeyEvent: (KeyboardEvent event) {
    if (event.logicalKey == LogicalKey.keyQ) {
      TerminalBinding.instance.shutdown();
      return true;
    }
    return false;
  },
  child: ...,
)
```

### LogicalKey constants
Letters: `LogicalKey.keyA` … `LogicalKey.keyZ` (lowercase keyId, but matched case-insensitively in most setups)
Digits: `LogicalKey.digit0` … `LogicalKey.digit9`
Special: `LogicalKey.space`, `LogicalKey.enter`, `LogicalKey.escape`, `LogicalKey.tab`,
`LogicalKey.arrowUp`, `LogicalKey.arrowDown`, `LogicalKey.arrowLeft`, `LogicalKey.arrowRight`,
`LogicalKey.backspace`, `LogicalKey.delete`, `LogicalKey.home`, `LogicalKey.end`

### Modifier detection
```dart
event.isShiftPressed
event.isControlPressed
event.isAltPressed
event.isMetaPressed
```

### Shift+Tab example
```dart
if (event.logicalKey == LogicalKey.tab && event.isShiftPressed) { ... }
```

---

## Text Fields

```dart
final _controller = TextEditingController();

// In dispose:
_controller.dispose();

// In build:
Container(
  decoration: BoxDecoration(
    border: BoxBorder.all(color: focused ? Colors.cyan : Colors.gray),
  ),
  child: TextField(
    controller: _controller,
    focused: _isFocused,
    width: 40,
    height: 1,
    placeholder: 'Enter value...',
    obscureText: false,        // set true for passwords
    maxLength: 100,
    onSubmitted: (String value) {
      // fired on Enter; value == _controller.text
    },
  ),
)
```

`TextField` is a `StatefulComponent` — focus it by passing `focused: true`. Only one TextField in the tree should be focused at a time. Tab navigation is handled manually via `setState`.

---

## Scrollable Lists

```dart
final _scroll = ScrollController();

// In dispose:
_scroll.dispose();

// In build:
ListView(
  controller: _scroll,
  children: lines.map((l) => Text(l)).toList(),
)

// Scroll to bottom after setState:
_scroll.scrollToEnd();
```

`ListView` also supports `ListView.builder` for lazy rendering and `ListView.separated`.

---

## Common Patterns

### Auto-scroll output panel
```dart
void _addOutput(String line) {
  setState(() {
    _outputLines.add(line);
    if (_outputLines.length > 500) {
      _outputLines.removeRange(0, _outputLines.length - 500);
    }
  });
  _scrollController.scrollToEnd();
}
```

### Async action from event handler
`onKeyEvent` and `onSubmitted` are synchronous callbacks. For async work, use an immediately-invoked async closure:

```dart
onSubmitted: (value) {
  setState(() => _busy = true);
  () async {
    await doSomethingAsync(value);
    if (mounted) setState(() => _busy = false);
  }();
},
```

### Multi-step form (email → password)
Use an enum to track which field is focused and pass it to each `TextField(focused: ...)`.

```dart
enum _Step { email, password }
_Step _step = _Step.email;

// In onSubmitted for email:
setState(() => _step = _Step.password);

// In onSubmitted for password:
// execute action
```

### Running a zonai subcommand
See `lib/src/commands/dev/actions/subprocess_runner.dart`. Resolve the executable from `Platform.resolvedExecutable` / `Platform.script` and pipe stdout/stderr to an `OutputSink` callback.

---

## Known 0.1.0 Quirks

| Feature | 0.1.0 behaviour |
|---------|-----------------|
| `shutdownApp()` | **Does not exist.** Use `TerminalBinding.instance.shutdown()` instead. |
| `runApp` logs | Writes all `print()` output to `log.txt` in the working directory (via zone override). |
| `Colors.error/success/primary` | Available as semantic aliases. |
| `BorderSide.width` | Defaults to 1 if omitted. |
| Hot reload | Enabled by default in debug mode; disable with `runApp(app, enableHotReload: false)`. |
