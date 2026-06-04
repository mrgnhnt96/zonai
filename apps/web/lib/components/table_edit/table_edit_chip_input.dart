import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:universal_web/web.dart' as web;

import '../../utils/table_cell_edit.dart';
import '../theme/ui_styles.dart';
import '../theme/zonai_button.dart';

/// Chip list editor for comma-separated filter values (in / not in) on non-enum columns.
class TableEditChipInput extends StatefulComponent {
  const TableEditChipInput({
    super.key,
    required this.id,
    required this.valueText,
    required this.onValueTextChanged,
    this.placeholder = 'Add value…',
    this.labelId,
    this.disabled = false,
  });

  final String id;
  final String valueText;
  final void Function(String valueText) onValueTextChanged;
  final String placeholder;
  final String? labelId;
  final bool disabled;

  @override
  State<TableEditChipInput> createState() => _TableEditChipInputState();
}

class _TableEditChipInputState extends State<TableEditChipInput> {
  var _draft = '';

  @override
  void didUpdateComponent(covariant TableEditChipInput oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.valueText != component.valueText) {
      _draft = '';
    }
  }

  List<String> get _chips => parseCommaSeparatedList(component.valueText);

  void _setChips(List<String> chips) {
    component.onValueTextChanged(joinCommaSeparatedList(chips));
  }

  void _addChip(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return;
    final chips = [..._chips];
    if (!chips.contains(trimmed)) chips.add(trimmed);
    _setChips(chips);
    setState(() => _draft = '');
  }

  void _removeChip(String chip) {
    _setChips(_chips.where((c) => c != chip).toList());
  }

  @override
  Component build(BuildContext context) {
    final chips = _chips;
    final inputId = '${component.id}-add';

    return div(classes: 'table-edit-chip-input', [
      if (chips.isNotEmpty)
        div(classes: 'table-edit-chip-input__chips', [
          for (final chip in chips)
            span(classes: 'table-edit-chip-input__chip', [
              span(classes: 'table-edit-chip-input__chip-label', [.text(chip)]),
              button(
                type: .button,
                classes: 'table-edit-chip-input__chip-remove',
                attributes: {'aria-label': 'Remove $chip'},
                events: {
                  'click': (event) {
                    event.stopPropagation();
                    _removeChip(chip);
                  },
                },
                [_chipRemoveIcon()],
              ),
            ]),
        ]),
      div(classes: 'table-edit-chip-input__add-row', [
        input<String>(
          id: inputId,
          type: .text,
          classes: 'table-edit-chip-input__add-input ${ZonaiClasses.input}',
          attributes: {
            if (component.labelId != null) 'aria-labelledby': component.labelId!,
            'placeholder': component.placeholder,
            'autocomplete': 'off',
          },
          value: _draft,
          disabled: component.disabled,
          onInput: (v) => setState(() => _draft = v),
          events: {
            'keydown': (event) {
              if (event is! web.KeyboardEvent) return;
              if (event.key == 'Enter') {
                event.preventDefault();
                _addChip(_draft);
              }
            },
          },
        ),
        ZonaiButton(
          variant: ZonaiButtonVariant.ghost,
          disabled: component.disabled,
          events: {
            'click': (event) {
              event.preventDefault();
              event.stopPropagation();
              _addChip(_draft);
            },
          },
          child: .text('Add'),
        ),
      ]),
    ]);
  }
}

Component _chipRemoveIcon() {
  return svg(
    viewBox: '0 0 12 12',
    width: 10.px,
    height: 10.px,
    attributes: {'aria-hidden': 'true', 'fill': 'none'},
    [
      path(
        stroke: const Color('currentColor'),
        strokeWidth: '1.5',
        d: 'M3 3l6 6M9 3 3 9',
        attributes: const {'stroke-linecap': 'round'},
        [],
      ),
    ],
  );
}
