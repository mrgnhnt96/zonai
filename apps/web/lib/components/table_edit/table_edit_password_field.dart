import 'dart:math';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../../constants/button_sizes.dart';
import '../theme/ui_styles.dart';
import '../theme/zonai_icon_button.dart';

const _passwordChars =
    'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#\$%^&*';
const _passwordLength = 15;

String _generatePassword() {
  final random = Random.secure();
  return List.generate(
    _passwordLength,
    (_) => _passwordChars[random.nextInt(_passwordChars.length)],
  ).join();
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
  });

  final String id;
  final String value;
  final void Function(String value) onChanged;
  final String? labelId;
  final String? placeholder;
  final bool disabled;
  final String? inputClass;

  @override
  Component build(BuildContext context) {
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
        attributes: {'title': 'Generate password', 'aria-label': 'Generate password'},
        onClick: () => onChanged(_generatePassword()),
        child: _wandIcon(),
      ),
    ]);
  }
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
