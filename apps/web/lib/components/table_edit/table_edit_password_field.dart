import 'dart:math';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import '../../constants/button_sizes.dart';
import '../app_tooltip_overlay.dart';
import '../theme/ui_styles.dart';
import '../theme/zonai_icon_button.dart';

const _passwordChars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#\$%^&*';
const _passwordLength = 15;

String _generatePassword() {
  final random = Random.secure();
  return List.generate(_passwordLength, (_) => _passwordChars[random.nextInt(_passwordChars.length)]).join();
}

class TableEditPasswordField extends StatelessComponent {
  const TableEditPasswordField({
    super.key,
    required this.id,
    required this.value,
    required this.onChanged,
    this.labelId,
    this.placeholder,
    this.disabled = false,
    this.inputClass,
    this.isReplaceMode,
    this.onEnableReplace,
  });

  final String id;
  final String value;
  final void Function(String value) onChanged;
  final String? labelId;
  final String? placeholder;
  final bool disabled;
  final String? inputClass;

  /// When non-null, the field is in edit-row mode.
  /// [false] shows a locked placeholder; [true] shows the text input.
  /// [null] (create mode) always shows the text input.
  final bool? isReplaceMode;
  final VoidCallback? onEnableReplace;

  @override
  Component build(BuildContext context) {
    if (isReplaceMode == false) {
      return div(classes: 'table-edit-password-field', [
        input<String>(
          id: id,
          type: .text,
          classes: inputClass ?? ZonaiClasses.input,
          attributes: {
            if (labelId != null) 'aria-labelledby': labelId!,
            'placeholder': '••••••••',
            'autocomplete': 'off',
          },
          value: '',
          disabled: true,
          onInput: (_) {},
        ),
        ZonaiIconButton(
          size: ZonaiIconButtonSize.sm,
          variant: ZonaiIconButtonVariant.ghost,
          disabled: disabled,
          attributes: {'aria-label': 'Replace password'},
          events: disabled ? null : appTooltipEvents(context, text: 'Replace password'),
          onClick: disabled ? null : onEnableReplace,
          child: _refreshIcon(),
        ),
      ]);
    }

    return div(classes: 'table-edit-password-field', [
      input<String>(
        id: id,
        type: .text,
        classes: inputClass ?? ZonaiClasses.input,
        attributes: {
          if (labelId != null) 'aria-labelledby': labelId!,
          if (placeholder != null) 'placeholder': placeholder!,
          'autocomplete': 'off',
        },
        value: value,
        disabled: disabled,
        onInput: onChanged,
      ),
      ZonaiIconButton(
        size: ZonaiIconButtonSize.sm,
        variant: ZonaiIconButtonVariant.ghost,
        disabled: disabled,
        attributes: {'aria-label': 'Generate password'},
        events: disabled ? null : appTooltipEvents(context, text: 'Generate password'),
        onClick: () => onChanged(_generatePassword()),
        child: _wandIcon(),
      ),
    ]);
  }
}

Component _refreshIcon() {
  return svg(
    viewBox: '0 0 24 24',
    attributes: {
      'aria-hidden': 'true',
      'fill': 'none',
      'stroke': 'currentColor',
      'stroke-width': '2',
      'stroke-linecap': 'round',
      'stroke-linejoin': 'round',
    },
    classes: 'table-edit-password-field__icon',
    [
      path(d: 'M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8', []),
      path(d: 'M21 3v5h-5', []),
      path(d: 'M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16', []),
      path(d: 'M8 16H3v5', []),
    ],
  );
}

Component _wandIcon() {
  return svg(
    viewBox: '0 0 24 24',
    attributes: {
      'aria-hidden': 'true',
      'fill': 'none',
      'stroke': 'currentColor',
      'stroke-width': '2',
      'stroke-linecap': 'round',
      'stroke-linejoin': 'round',
    },
    classes: 'table-edit-password-field__icon',
    [
      path(d: 'M15 4V2', []),
      path(d: 'M15 16v-2', []),
      path(d: 'M8 9h2', []),
      path(d: 'M20 9h2', []),
      path(d: 'M17.8 11.8 19 13', []),
      path(d: 'M15 9h.01', []),
      path(d: 'M17.8 6.2 19 5', []),
      path(d: 'M3 21 12.9 11.1', []),
      path(d: 'M11 5 12.2 6.2', []),
    ],
  );
}
