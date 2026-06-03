import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import 'ui_styles.dart';

/// Label + input field with shared theme styling.
class ZonaiTextField extends StatelessComponent {
  const ZonaiTextField({
    super.key,
    required this.id,
    required this.fieldLabel,
    required this.value,
    required this.onInput,
    this.type = InputType.text,
    this.name,
    this.placeholder,
    this.autocomplete,
    this.disabled = false,
    this.attributes = const {},
  });

  final String id;
  final String fieldLabel;
  final String value;
  final void Function(String value) onInput;
  final InputType type;
  final String? name;
  final String? placeholder;
  final String? autocomplete;
  final bool disabled;
  final Map<String, String> attributes;

  @override
  Component build(BuildContext context) {
    final attrs = <String, String>{
      if (autocomplete != null) 'autocomplete': autocomplete!,
      if (placeholder != null) 'placeholder': placeholder!,
      ...attributes,
    };

    return div(classes: ZonaiClasses.field, [
      label(htmlFor: id, classes: ZonaiClasses.label, [.text(fieldLabel)]),
      input<String>(
        id: id,
        type: type,
        name: name ?? id,
        classes: ZonaiClasses.input,
        attributes: attrs,
        value: value,
        disabled: disabled,
        onInput: onInput,
      ),
    ]);
  }
}
