import 'dart:math' as math;

import 'package:nocterm/nocterm.dart';
import 'package:zonai_logger/zonai_logger.dart';

import '../../../utils/terminal_pointer.dart';

/// Shared palette and primitives for the `zonai dev` TUI.
abstract final class DevTheme {
  static const bg = Color(0xFF090C10);
  static const surface = Color(0xFF0F1419);
  static const surfaceRaised = Color(0xFF151B23);
  static const surfaceHover = Color(0xFF1A2330);
  static const border = Color(0xFF1C2736);
  static const borderSubtle = Color(0xFF141C26);
  static const borderFocus = Color(0xFF3D6FA8);
  static const accent = Color(0xFF5B9CF5);
  static const accentBright = Color(0xFF93C5FD);
  static const accentMuted = Color(0xFF162A42);
  static const violet = Color(0xFF8B7CF8);
  static const text = Color(0xFFE8EDF4);
  static const textMuted = Color(0xFF6B7A90);
  static const textDim = Color(0xFF3D4F66);
  static const textFaint = Color(0xFF253040);
  static const success = Color(0xFF34D399);
  static const successMuted = Color(0xFF0D2E22);
  static const successBorder = Color(0xFF166534);
  static const error = Color(0xFFF87171);
  static const errorSoft = Color(0xFFC07070);
  static const errorMuted = Color(0xFF2D1212);
  static const errorBorder = Color(0xFF991B1B);
  static const warning = Color(0xFFFBBF24);
  static const warningMuted = Color(0xFF2A2008);
  static const selection = Color(0xFF1A2D45);
}

class DevKeyCap extends StatelessComponent {
  const DevKeyCap({required this.label, this.highlighted = false, super.key});

  final String label;
  final bool highlighted;

  static const _horizontalPadding = 1.0;

  @override
  Component build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: highlighted ? DevTheme.accentMuted : DevTheme.surfaceRaised,
        border: BoxBorder.all(
          color: highlighted ? DevTheme.borderFocus : DevTheme.border,
        ),
      ),
      padding: EdgeInsets.symmetric(horizontal: _horizontalPadding),
      child: Text(
        label,
        style: TextStyle(
          color: highlighted ? DevTheme.accentBright : DevTheme.textMuted,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class DevFormButton extends StatefulComponent {
  const DevFormButton({
    required this.label,
    required this.focused,
    this.enabled = true,
    this.primary = false,
    this.destructive = false,
    this.onTap,
    this.onTapDown,
    this.onTapUp,
    this.onTapCancel,
    super.key,
  });

  final String label;
  final bool focused;
  final bool enabled;
  final bool primary;
  final bool destructive;
  final VoidCallback? onTap;
  final GestureTapDownCallback? onTapDown;
  final GestureTapUpCallback? onTapUp;
  final GestureTapCancelCallback? onTapCancel;

  @override
  State<DevFormButton> createState() => _DevFormButtonState();
}

class _DevFormButtonState extends State<DevFormButton> {
  var _hovered = false;

  @override
  Component build(BuildContext context) {
    final accent = component.destructive ? DevTheme.error : DevTheme.accent;
    final hoverAccent = component.destructive
        ? DevTheme.errorSoft
        : DevTheme.borderFocus;
    final active = component.enabled;
    final highlighted =
        active && (component.primary || component.focused || _hovered);
    final borderColor = !active
        ? DevTheme.border
        : highlighted
        ? (component.focused || component.primary ? accent : hoverAccent)
        : DevTheme.border;
    final textColor = !active
        ? DevTheme.textDim
        : highlighted
        ? (component.focused || component.primary ? accent : hoverAccent)
        : DevTheme.textDim;

    final button = Container(
      decoration: BoxDecoration(border: BoxBorder.all(color: borderColor)),
      child: SizedBox(
        height: 1,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            component.label,
            style: TextStyle(
              color: textColor,
              fontWeight: active && (component.primary || component.focused)
                  ? FontWeight.bold
                  : FontWeight.normal,
            ),
          ),
        ),
      ),
    );

    if (!active) return button;

    final hasGestures =
        component.onTap != null ||
        component.onTapDown != null ||
        component.onTapUp != null ||
        component.onTapCancel != null;
    if (!hasGestures) return button;

    return MouseRegion(
      onEnter: (_) {
        TerminalPointer.push(TerminalPointerShape.pointer);
        if (_hovered) return;
        setState(() => _hovered = true);
      },
      onExit: (_) {
        TerminalPointer.pop();
        if (!_hovered) return;
        setState(() => _hovered = false);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: component.onTap,
        onTapDown: component.onTapDown,
        onTapUp: component.onTapUp,
        onTapCancel: component.onTapCancel,
        child: button,
      ),
    );
  }
}

class DevSidebarTitle extends StatelessComponent {
  const DevSidebarTitle({super.key});

  @override
  Component build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 2),
      child: Row(
        children: [
          Text(
            'ACTIONS',
            style: TextStyle(
              color: DevTheme.textDim,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class DevContentHeader extends StatelessComponent {
  const DevContentHeader({
    required this.title,
    this.badge,
    this.subtitle,
    this.destructive = false,
    this.trailing,
    super.key,
  });

  final String title;
  final String? badge;
  final String? subtitle;
  final bool destructive;
  final Component? trailing;

  @override
  Component build(BuildContext context) {
    final badgeColor = destructive ? DevTheme.errorMuted : DevTheme.accentMuted;
    final badgeBorder = destructive
        ? DevTheme.errorBorder
        : DevTheme.borderFocus;
    final badgeText = destructive ? DevTheme.error : DevTheme.accentBright;

    return Container(
      decoration: BoxDecoration(
        color: DevTheme.surface,
        border: BoxBorder(bottom: BorderSide(color: DevTheme.border, width: 1)),
      ),
      padding: EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: DevTheme.textMuted,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (badge != null) ...[
                    SizedBox(width: 1),
                    Container(
                      decoration: BoxDecoration(
                        color: badgeColor,
                        border: BoxBorder.all(color: badgeBorder),
                      ),
                      padding: EdgeInsets.only(left: 1, right: 1),
                      child: Text(
                        badge!,
                        style: TextStyle(
                          color: badgeText,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (trailing != null) trailing!,
            ],
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              style: TextStyle(color: DevTheme.textDim),
              softWrap: true,
            ),
        ],
      ),
    );
  }
}

class DevFormField extends StatelessComponent {
  const DevFormField({
    required this.label,
    required this.input,
    this.required = false,
    super.key,
  });

  final String label;
  final Component input;
  final bool required;

  @override
  Component build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DevFieldLabel(label: label, required: required),
        input,
      ],
    );
  }
}

enum DevFormAction { cancel, submit }

/// Enter or Space — activates a focused [DevFormActionBar] button.
bool devFormActivateKey(KeyboardEvent event) {
  return event.logicalKey == LogicalKey.enter ||
      event.logicalKey == LogicalKey.space;
}

/// First action button focused when tabbing forward into [DevFormActionBar].
DevFormAction devFormFirstAction() => DevFormAction.cancel;

/// Last action button when tabbing backward from the first input.
DevFormAction devFormLastAction({required bool submitEnabled}) =>
    submitEnabled ? DevFormAction.submit : DevFormAction.cancel;

/// Next action when tabbing forward within the action bar.
///
/// Returns `null` when focus should wrap to the first input field.
DevFormAction? devFormTabNextAction({
  required DevFormAction current,
  required bool submitEnabled,
}) {
  return switch (current) {
    DevFormAction.cancel => submitEnabled ? DevFormAction.submit : null,
    DevFormAction.submit => null,
  };
}

/// Previous action when tabbing backward within the action bar.
///
/// Returns `null` when focus should wrap to the last input field.
DevFormAction? devFormTabPreviousAction({
  required DevFormAction current,
  required bool submitEnabled,
}) {
  return switch (current) {
    DevFormAction.submit => DevFormAction.cancel,
    DevFormAction.cancel => null,
  };
}

/// Keeps action focus off a disabled submit button.
DevFormAction devFormEffectiveAction({
  required DevFormAction action,
  required bool submitEnabled,
}) {
  if (action == DevFormAction.submit && !submitEnabled) {
    return DevFormAction.cancel;
  }
  return action;
}

class DevFormActionBar extends StatelessComponent {
  const DevFormActionBar({
    required this.submitLabel,
    required this.onSubmit,
    required this.onCancel,
    this.cancelLabel = 'Cancel',
    this.focusedAction,
    this.onFocusSubmit,
    this.onFocusCancel,
    this.submitEnabled = true,
    super.key,
  });

  final String submitLabel;
  final String cancelLabel;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;
  final DevFormAction? focusedAction;
  final VoidCallback? onFocusSubmit;
  final VoidCallback? onFocusCancel;
  final bool submitEnabled;

  @override
  Component build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        DevFormButton(
          label: cancelLabel,
          focused: focusedAction == DevFormAction.cancel,
          onTap: () {
            onFocusCancel?.call();
            onCancel();
          },
        ),
        SizedBox(width: 1),
        DevFormButton(
          label: submitLabel,
          primary: true,
          enabled: submitEnabled,
          focused: submitEnabled && focusedAction == DevFormAction.submit,
          onTap: () {
            onFocusSubmit?.call();
            if (submitEnabled) onSubmit();
          },
        ),
      ],
    );
  }
}

class DevFormCard extends StatefulComponent {
  const DevFormCard({
    required this.title,
    required this.fields,
    this.expandedField,
    this.footer,
    this.onBackgroundTap,
    this.subtitle,
    this.accentColor = DevTheme.accent,
    this.focusedFieldIndex = 0,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Color accentColor;

  /// Index of the focused row in the scrollable form body.
  ///
  /// Field indices are `0` through [fields.length - 1]. When a [footer] is
  /// present in the scrollable list, pass [fields.length] while action buttons
  /// are focused so the footer scrolls into view.
  final int focusedFieldIndex;
  final List<Component> fields;
  final Component? expandedField;
  final Component? footer;
  final VoidCallback? onBackgroundTap;

  @override
  State<DevFormCard> createState() => _DevFormCardState();
}

class _DevFormCardState extends State<DevFormCard> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scheduleScrollToFocused();
  }

  @override
  void didUpdateComponent(DevFormCard oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (component.focusedFieldIndex != oldComponent.focusedFieldIndex) {
      _scheduleScrollToFocused();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleScrollToFocused() {
    TerminalBinding.instance.addPostFrameCallback(_scrollToFocused);
  }

  void _scrollToFocused(Duration _) {
    if (!mounted) return;

    final footerInList =
        component.footer != null && component.expandedField == null;
    final maxIndex = footerInList
        ? component.fields.length
        : math.max(0, component.fields.length - 1);

    if (component.fields.isEmpty && !footerInList) return;

    final index = component.focusedFieldIndex.clamp(0, maxIndex);
    _scrollController.ensureIndexVisible(index: index);
  }

  Component _buildScrollableFields() {
    return ListView.separated(
      controller: _scrollController,
      itemCount: component.fields.length,
      separatorBuilder: (_, __) => const SizedBox(height: 1),
      itemBuilder: (context, index) => component.fields[index],
    );
  }

  Component _buildFormBody() {
    final expandedField = component.expandedField;
    final footer = component.footer;

    if (expandedField != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < component.fields.length; i++) ...[
            if (i > 0) const SizedBox(height: 1),
            component.fields[i],
          ],
          if (component.fields.isNotEmpty) SizedBox(height: 1),
          Expanded(child: expandedField),
          if (footer != null) ...[SizedBox(height: 1), footer],
        ],
      );
    }

    if (footer == null) return _buildScrollableFields();

    return ListView.separated(
      controller: _scrollController,
      itemCount: component.fields.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 1),
      itemBuilder: (context, index) {
        if (index < component.fields.length) {
          return component.fields[index];
        }
        return footer;
      },
    );
  }

  @override
  Component build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 0.5,
                child: Container(
                  decoration: BoxDecoration(color: component.accentColor),
                ),
              ),
              Padding(
                padding: EdgeInsets.only(left: 1.5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      component.title,
                      style: TextStyle(
                        color: DevTheme.text,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (component.subtitle != null) ...[
                      Text(
                        component.subtitle!,
                        style: TextStyle(color: DevTheme.textMuted),
                        softWrap: true,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 1),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: DevTheme.surfaceRaised,
                border: BoxBorder.all(color: DevTheme.border),
              ),
              padding: EdgeInsets.symmetric(horizontal: 2),
              child: DevFormScope(
                onBackgroundTap: component.onBackgroundTap,
                child: _wrapBackgroundTap(_buildFormBody()),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Component _wrapBackgroundTap(Component child) {
    final onBackgroundTap = component.onBackgroundTap;
    if (onBackgroundTap == null) return child;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onBackgroundTap,
          ),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}

class DevFormScope extends InheritedComponent {
  const DevFormScope({
    required this.onBackgroundTap,
    required super.child,
    super.key,
  });

  final VoidCallback? onBackgroundTap;

  static DevFormScope? of(BuildContext context) {
    return context.dependOnInheritedComponentOfExactType<DevFormScope>();
  }

  @override
  bool updateShouldNotify(covariant DevFormScope oldComponent) {
    return onBackgroundTap != oldComponent.onBackgroundTap;
  }
}

class DevFieldLabel extends StatelessComponent {
  const DevFieldLabel({required this.label, this.required = false, super.key});

  final String label;
  final bool required;

  @override
  Component build(BuildContext context) {
    final text = Text(
      required ? '$label *' : label,
      style: TextStyle(color: DevTheme.textMuted),
    );

    final onBackgroundTap = DevFormScope.of(context)?.onBackgroundTap;
    if (onBackgroundTap == null) return text;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: onBackgroundTap,
      child: text,
    );
  }
}

class DevInputBox extends StatelessComponent {
  const DevInputBox({
    required this.focused,
    required this.child,
    this.width = 42,
    this.height = 1,
    this.onTap,
    super.key,
  });

  final bool focused;
  final double width;
  final double height;
  final Component child;
  final VoidCallback? onTap;

  @override
  Component build(BuildContext context) {
    final box = Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: DevTheme.bg,
        border: BoxBorder.all(
          color: focused ? DevTheme.borderFocus : DevTheme.border,
        ),
      ),
      child: SizedBox(width: width, height: height, child: child),
    );

    if (onTap == null) return box;

    return MouseRegion(
      onEnter: (_) => TerminalPointer.push(TerminalPointerShape.text),
      onExit: (_) => TerminalPointer.pop(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: box,
      ),
    );
  }
}

int devTextAreaContentWidth(String text, int minWidth) {
  var maxLine = 0;
  for (final line in text.split('\n')) {
    maxLine = math.max(maxLine, line.length);
  }
  return math.max(minWidth, maxLine + 1);
}

/// Terminal rows for a [DevTextArea], including its top and bottom border cells.
int devTextAreaTotalHeight(int minLines) => minLines + 2;

class DevTextArea extends StatefulComponent {
  const DevTextArea({
    required this.controller,
    required this.focused,
    required this.onFocus,
    this.hasError = false,
    this.minLines = 1,
    this.placeholder,
    this.onSubmitted,
    this.onKeyEvent,
    super.key,
  });

  final TextEditingController controller;
  final bool focused;
  final VoidCallback onFocus;
  final bool hasError;
  final int minLines;
  final String? placeholder;
  final ValueChanged<String>? onSubmitted;
  final KeyEventHandler? onKeyEvent;

  @override
  State<DevTextArea> createState() => _DevTextAreaState();
}

class _DevTextAreaState extends State<DevTextArea> {
  final _verticalScroll = ScrollController();
  final _horizontalScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    component.controller.addListener(_onControllerChanged);
    _scheduleScrollToCursor();
  }

  @override
  void didUpdateComponent(DevTextArea oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.controller != component.controller) {
      oldComponent.controller.removeListener(_onControllerChanged);
      component.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    component.controller.removeListener(_onControllerChanged);
    _verticalScroll.dispose();
    _horizontalScroll.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    _scrollToCursor();
    setState(() {});
    _scheduleScrollToCursor();
  }

  void _scheduleScrollToCursor() {
    TerminalBinding.instance.addPostFrameCallback((_) => _scrollToCursor());
  }

  void _scrollToCursor() {
    if (!mounted) return;

    final controller = component.controller;
    final text = controller.text;
    if (text.isEmpty) return;

    final offset = controller.selection.extentOffset.clamp(0, text.length);
    final lineStart = offset == 0 ? 0 : text.lastIndexOf('\n', offset - 1) + 1;
    final visualLine = lineStart == 0
        ? 0
        : '\n'.allMatches(text.substring(0, lineStart)).length;
    final column = (offset - lineStart).toDouble();

    _verticalScroll.ensureVisible(
      itemOffset: visualLine.toDouble(),
      itemExtent: 1,
    );
    _horizontalScroll.ensureVisible(itemOffset: column, itemExtent: 1);
  }

  bool _handleKeyEvent(KeyboardEvent event) {
    if (component.onKeyEvent?.call(event) ?? false) return true;
    if (event.logicalKey == LogicalKey.enter &&
        (event.isControlPressed || event.isMetaPressed)) {
      component.onSubmitted?.call(component.controller.text);
      return true;
    }
    if (event.logicalKey == LogicalKey.enter &&
        !event.isShiftPressed &&
        !event.isControlPressed &&
        !event.isMetaPressed &&
        !event.isAltPressed) {
      _insertNewline();
      return true;
    }
    return false;
  }

  void _insertNewline() {
    final controller = component.controller;
    final text = controller.text;
    final offset = controller.selection.extentOffset.clamp(0, text.length);
    final newText = '${text.substring(0, offset)}\n${text.substring(offset)}';
    final newSelection = TextSelection.collapsed(offset: offset + 1);

    controller.removeListener(_onControllerChanged);
    controller.text = newText;
    controller.selection = newSelection;
    controller.addListener(_onControllerChanged);
    _scrollToCursor();
    setState(() {});
  }

  @override
  Component build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const borderCells = 2.0;
        const horizontalBorderCells = 2.0;
        final innerWidth = math.max(
          1.0,
          constraints.maxWidth - horizontalBorderCells,
        );
        final contentHeight = math.max(
          component.minLines.toDouble(),
          constraints.maxHeight - borderCells,
        );
        final contentWidth = devTextAreaContentWidth(
          component.controller.text,
          innerWidth.floor(),
        );

        final field = SizedBox(
          width: contentWidth.toDouble(),
          height: contentHeight,
          child: TextField(
            controller: component.controller,
            focused: component.focused,
            onFocusChange: (next) {
              if (next) component.onFocus();
            },
            onKeyEvent: _handleKeyEvent,
            width: contentWidth.toDouble(),
            minLines: component.minLines,
            maxLines: null,
            placeholder: component.placeholder,
          ),
        );

        final borderColor = component.hasError
            ? DevTheme.error
            : (component.focused ? DevTheme.borderFocus : DevTheme.border);

        final box = Container(
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: DevTheme.bg,
            border: BoxBorder.all(color: borderColor),
          ),
          child: SizedBox(
            width: innerWidth,
            height: contentHeight,
            child: SingleChildScrollView(
              controller: _verticalScroll,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                controller: _horizontalScroll,
                child: field,
              ),
            ),
          ),
        );

        return MouseRegion(
          onEnter: (_) => TerminalPointer.push(TerminalPointerShape.text),
          onExit: (_) => TerminalPointer.pop(),
          child: box,
        );
      },
    );
  }
}

class DevTextInput extends StatelessComponent {
  const DevTextInput({
    required this.controller,
    required this.focused,
    required this.onFocus,
    this.width = 40,
    this.height = 1,
    this.placeholder,
    this.obscureText = false,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;
  final bool focused;
  final VoidCallback onFocus;
  final double width;
  final double height;
  final String? placeholder;
  final bool obscureText;
  final ValueChanged<String>? onSubmitted;

  @override
  Component build(BuildContext context) {
    return DevInputBox(
      focused: focused,
      width: width,
      height: height,
      onTap: onFocus,
      child: TextField(
        controller: controller,
        focused: focused,
        onFocusChange: (next) {
          if (next) onFocus();
        },
        width: width,
        height: height,
        placeholder: placeholder,
        obscureText: obscureText,
        onSubmitted: onSubmitted,
      ),
    );
  }
}

class DevBoolField extends StatefulComponent {
  const DevBoolField({
    required this.label,
    required this.value,
    required this.focused,
    required this.onTap,
    this.enabled = true,
    super.key,
  });

  final String label;
  final bool value;
  final bool focused;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<DevBoolField> createState() => _DevBoolFieldState();
}

class _DevBoolFieldState extends State<DevBoolField> {
  var _hovered = false;

  @override
  Component build(BuildContext context) {
    final enabled = component.enabled;
    final focused = enabled && component.focused;
    final hovered = enabled && _hovered && !focused;
    final marker = component.value ? '[x]' : '[ ]';
    final textColor = !enabled
        ? DevTheme.textDim
        : (focused
              ? DevTheme.accentBright
              : (hovered ? DevTheme.accentBright : DevTheme.text));
    final markerColor = !enabled
        ? DevTheme.textDim
        : (focused
              ? DevTheme.accent
              : (hovered ? DevTheme.accent : DevTheme.textMuted));

    final decoration = (enabled && _hovered) || (focused && !component.value)
        ? TextDecoration.underline
        : TextDecoration.none;
    final row = SizedBox(
      height: 1,
      child: RichText(
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        text: TextSpan(
          children: [
            TextSpan(
              text: marker,
              style: TextStyle(
                color: markerColor,
                fontWeight: FontWeight.bold,
                decoration: decoration,
              ),
            ),
            const TextSpan(text: ' '),
            TextSpan(
              text: component.label,
              style: TextStyle(color: textColor, decoration: decoration),
            ),
          ],
        ),
      ),
    );

    if (!enabled) return row;

    return MouseRegion(
      onEnter: (_) {
        TerminalPointer.push(TerminalPointerShape.pointer);
        if (_hovered) return;
        setState(() => _hovered = true);
      },
      onExit: (_) {
        TerminalPointer.pop();
        if (!_hovered) return;
        setState(() => _hovered = false);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: component.onTap,
        child: row,
      ),
    );
  }
}

class DevChipGroup extends StatelessComponent {
  const DevChipGroup({
    required this.label,
    required this.options,
    required this.selected,
    required this.focused,
    required this.focusedChipIndex,
    required this.onChipTap,
    this.footer,
    super.key,
  });

  final String label;
  final List<String> options;
  final List<bool> selected;
  final bool focused;
  final int focusedChipIndex;
  final ValueChanged<int> onChipTap;
  final Component? footer;

  @override
  Component build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DevFieldLabel(label: label),
        Row(
          children: [
            for (var i = 0; i < options.length; i++) ...[
              if (i > 0) SizedBox(width: 1),
              DevChip(
                label: options[i],
                selected: selected[i],
                focused: focused && focusedChipIndex == i,
                onTap: () => onChipTap(i),
              ),
            ],
          ],
        ),
        if (footer != null) footer!,
      ],
    );
  }
}

class DevChip extends StatefulComponent {
  const DevChip({
    required this.label,
    required this.selected,
    required this.focused,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final bool focused;
  final VoidCallback onTap;

  @override
  State<DevChip> createState() => _DevChipState();
}

class _DevChipState extends State<DevChip> {
  var _hovered = false;

  @override
  Component build(BuildContext context) {
    final selected = component.selected;
    final focused = component.focused;
    final bgColor = selected ? DevTheme.accentMuted : DevTheme.bg;
    final borderColor = focused
        ? DevTheme.borderFocus
        : (selected ? DevTheme.accent : DevTheme.border);
    final textColor = focused
        ? DevTheme.accentBright
        : (selected
              ? DevTheme.accentBright
              : (_hovered ? DevTheme.text : DevTheme.textMuted));

    return MouseRegion(
      onEnter: (_) {
        TerminalPointer.push(TerminalPointerShape.pointer);
        if (_hovered) return;
        setState(() => _hovered = true);
      },
      onExit: (_) {
        TerminalPointer.pop();
        if (!_hovered) return;
        setState(() => _hovered = false);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: component.onTap,
        child: Container(
          decoration: BoxDecoration(
            color: bgColor,
            border: BoxBorder.all(color: borderColor),
          ),
          child: SizedBox(
            height: 1,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 1),
              child: Text(
                component.label,
                style: TextStyle(
                  color: textColor,
                  fontWeight: selected || focused
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DevEmptyState extends StatelessComponent {
  const DevEmptyState({required this.title, required this.message, super.key});

  final String title;
  final String message;

  @override
  Component build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('◇', style: TextStyle(color: DevTheme.accent)),
          SizedBox(height: 0.5),
          Text(
            title,
            style: TextStyle(color: DevTheme.text, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 0.5),
          Text(message, style: TextStyle(color: DevTheme.textMuted)),
        ],
      ),
    );
  }
}

class DevToast extends StatelessComponent {
  const DevToast({required this.message, required this.isError, super.key});

  final String message;
  final bool isError;

  @override
  Component build(BuildContext context) {
    final borderColor = isError ? DevTheme.errorBorder : DevTheme.successBorder;
    final bgColor = isError ? DevTheme.errorMuted : DevTheme.successMuted;
    final textColor = isError ? DevTheme.error : DevTheme.success;
    final label = '${isError ? '✕' : '✓'} $message';
    final isSingleLine = !label.contains('\n');

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        border: BoxBorder.all(color: borderColor),
      ),
      padding: isSingleLine
          ? EdgeInsets.symmetric(horizontal: 1)
          : EdgeInsets.symmetric(horizontal: 1, vertical: 0.5),
      child: Text(
        label,
        style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class DevHintBar extends StatelessComponent {
  const DevHintBar({required this.hints, super.key});

  final List<(String key, String action)> hints;

  @override
  Component build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: DevTheme.surface,
        border: BoxBorder(top: BorderSide(color: DevTheme.border, width: 1)),
      ),
      padding: EdgeInsets.symmetric(horizontal: 2, vertical: 0.5),
      child: Row(
        children: [
          for (var i = 0; i < hints.length; i++) ...[
            if (i > 0) SizedBox(width: 2),
            DevKeyCap(label: hints[i].$1),
            SizedBox(width: 1),
            Text(hints[i].$2, style: TextStyle(color: DevTheme.textDim)),
          ],
        ],
      ),
    );
  }
}

typedef DevOutputLine = ({String text, Level? level});

TextStyle devOutputLineStyle(DevOutputLine line) {
  if (line.level != null) {
    return devLogLevelStyle(line.level!);
  }

  final text = line.text;
  if (text.startsWith('[error]') || text.startsWith('[err]')) {
    return TextStyle(color: DevTheme.error);
  }
  if (text.startsWith('>')) {
    return TextStyle(color: DevTheme.textDim);
  }
  if (text.startsWith('---')) {
    return TextStyle(color: DevTheme.accentBright, fontWeight: FontWeight.bold);
  }
  return TextStyle(color: DevTheme.text);
}

TextStyle devLogLevelStyle(Level level) {
  return switch (level) {
    Level.verbose ||
    Level.trace ||
    Level.request ||
    Level.debug => TextStyle(color: DevTheme.textMuted),
    Level.info => TextStyle(color: DevTheme.text),
    Level.warning => TextStyle(color: DevTheme.warning),
    Level.error => TextStyle(color: DevTheme.error),
  };
}
