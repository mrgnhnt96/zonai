import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:universal_web/js_interop.dart';
import 'package:universal_web/web.dart' as web;

import '../../constants/theme.dart';
import '../../utils/table_cell_edit.dart';

/// Date + time picker for filter/edit datetime values (stores UTC ms wire text).
class TableEditDatetimeField extends StatefulComponent {
  const TableEditDatetimeField({
    super.key,
    required this.id,
    required this.valueText,
    required this.onValueTextChanged,
    this.labelId,
    this.placeholder = 'Choose date and time',
    this.compact = false,
    this.useUtc = false,
  });

  final String id;
  final String valueText;
  final void Function(String valueText) onValueTextChanged;
  final String? labelId;
  final String placeholder;
  /// Narrow trigger (e.g. filter panel with preset buttons above).
  final bool compact;

  /// When true, calendar and time controls edit UTC wall time (filter panel).
  final bool useUtc;

  @override
  State<TableEditDatetimeField> createState() => _TableEditDatetimeFieldState();
}

class _TableEditDatetimeFieldState extends State<TableEditDatetimeField> {
  var _open = false;
  var _viewYear = 0;
  var _viewMonth = 0;
  var _dismissListenersAttached = false;
  web.EventListener? _outsideListener;
  web.EventListener? _keyListener;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _viewYear = now.year;
    _viewMonth = now.month;
    if (context.binding.isClient) {
      _outsideListener = _onDocumentMouseDown.toJS;
      _keyListener = _onDocumentKeyDown.toJS;
    }
    _syncViewToValue();
  }

  @override
  void dispose() {
    _detachDismissListeners();
    super.dispose();
  }

  @override
  void didUpdateComponent(covariant TableEditDatetimeField oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.valueText != component.valueText || oldComponent.useUtc != component.useUtc) {
      _syncViewToValue();
    }
  }

  DateTime? get _selectedWall => filterDateTimeTextToWall(component.valueText, useUtc: component.useUtc);

  DateTime get _nowWall => component.useUtc ? DateTime.now().toUtc() : DateTime.now();

  void _syncViewToValue() {
    final selected = _selectedWall ?? _nowWall;
    _viewYear = selected.year;
    _viewMonth = selected.month;
  }

  void _setOpen(bool open) {
    if (_open == open) return;
    setState(() {
      _open = open;
      if (open) _syncViewToValue();
    });
    if (open) {
      _attachDismissListeners();
    } else {
      _detachDismissListeners();
    }
  }

  void _attachDismissListeners() {
    if (_dismissListenersAttached) return;
    final outside = _outsideListener;
    final key = _keyListener;
    if (outside == null || key == null) return;
    _dismissListenersAttached = true;
    web.document.addEventListener('mousedown', outside);
    web.document.addEventListener('keydown', key);
  }

  void _detachDismissListeners() {
    if (!_dismissListenersAttached) return;
    _dismissListenersAttached = false;
    final outside = _outsideListener;
    final key = _keyListener;
    if (outside != null) {
      web.document.removeEventListener('mousedown', outside);
    }
    if (key != null) {
      web.document.removeEventListener('keydown', key);
    }
  }

  void _onDocumentMouseDown(web.Event event) {
    if (!_open || !mounted) return;
    final root = web.document.getElementById(component.id);
    final target = event.target;
    if (root != null && target is web.Node && root.contains(target)) return;
    _setOpen(false);
  }

  void _onDocumentKeyDown(web.Event event) {
    if (!_open || !mounted) return;
    if (event is! web.KeyboardEvent) return;
    final key = event.key;
    if (key != 'Escape' && key != 'Enter') return;

    final root = web.document.getElementById(component.id);
    final target = event.target;
    final inside = root != null && target is web.Node && root.contains(target);

    if (key == 'Escape' || (key == 'Enter' && inside)) {
      _setOpen(false);
      event.stopPropagation();
      event.preventDefault();
    }
  }

  void _commitWall(DateTime? wall) {
    component.onValueTextChanged(
      wall == null ? '' : wallDateTimeToFilterText(wall, useUtc: component.useUtc),
    );
  }

  DateTime _mergeSelected({int? year, int? month, int? day, int? hour, int? minute}) {
    final base = _selectedWall ?? _nowWall;
    if (component.useUtc) {
      return DateTime.utc(
        year ?? base.year,
        month ?? base.month,
        day ?? base.day,
        hour ?? base.hour,
        minute ?? base.minute,
      );
    }
    return DateTime(
      year ?? base.year,
      month ?? base.month,
      day ?? base.day,
      hour ?? base.hour,
      minute ?? base.minute,
    );
  }

  void _selectDay(int day) {
    final next = _mergeSelected(year: _viewYear, month: _viewMonth, day: day);
    _commitWall(next);
    setState(() {
      _viewYear = next.year;
      _viewMonth = next.month;
    });
  }

  void _setTime({required int hour, required int minute}) {
    _commitWall(_mergeSelected(hour: hour, minute: minute));
  }

  void _shiftMonth(int delta) {
    var y = _viewYear;
    var m = _viewMonth + delta;
    while (m < 1) {
      m += 12;
      y -= 1;
    }
    while (m > 12) {
      m -= 12;
      y += 1;
    }
    setState(() {
      _viewYear = y;
      _viewMonth = m;
    });
  }

  void _selectToday() {
    final now = _nowWall;
    _commitWall(now);
    setState(() {
      _viewYear = now.year;
      _viewMonth = now.month;
    });
  }

  @override
  Component build(BuildContext context) {
    final selected = _selectedWall;
    final display = selected == null
        ? null
        : formatFilterDateTimeDisplay(selected, useUtc: component.useUtc);
    final hour24 = selected?.hour ?? 0;
    final minute = selected?.minute ?? 0;
    final (hour12, isPm) = hour24To12Parts(hour24);
    final today = _nowWall;
    final days = daysInMonth(_viewYear, _viewMonth);
    final leading = firstWeekdaySundayStart(_viewYear, _viewMonth);
    final cells = <_CalendarDay>[
      for (var i = 0; i < leading; i++) null,
      for (var d = 1; d <= days; d++) d,
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }

    return div(
      id: component.id,
      classes: [
        'table-edit-datetime',
        if (component.compact) 'table-edit-datetime--compact',
      ].join(' '),
      events: {'click': (event) => event.stopPropagation()},
      [
        div(classes: 'table-edit-datetime__combobox', [
          button(
            type: .button,
            classes: [
              'table-edit-datetime__trigger',
              if (_open) 'table-edit-datetime__trigger--open',
            ].join(' '),
            attributes: {
              if (component.labelId != null) 'aria-labelledby': component.labelId!,
              'aria-haspopup': 'dialog',
              'aria-expanded': _open ? 'true' : 'false',
            },
            events: {
              'click': (event) {
                event.stopPropagation();
                _setOpen(!_open);
              },
            },
            [
              span(
                classes: display == null
                    ? 'table-edit-datetime__trigger-placeholder'
                    : 'table-edit-datetime__trigger-value',
                [.text(display ?? component.placeholder)],
              ),
              _calendarIcon(),
            ],
          ),
          if (_open)
            div(
              classes: 'table-edit-datetime__popover',
              attributes: {'role': 'dialog', 'aria-label': 'Date and time'},
              [
                div(classes: 'table-edit-datetime__header', [
                  button(
                    type: .button,
                    classes: 'table-edit-datetime__nav',
                    attributes: {'aria-label': 'Previous month'},
                    events: {
                      'click': (event) {
                        event.stopPropagation();
                        _shiftMonth(-1);
                      },
                    },
                    [_chevronLeftIcon()],
                  ),
                  span(classes: 'table-edit-datetime__month-label', [
                    .text('${_monthAbbrev[_viewMonth - 1]} $_viewYear'),
                  ]),
                  button(
                    type: .button,
                    classes: 'table-edit-datetime__nav',
                    attributes: {'aria-label': 'Next month'},
                    events: {
                      'click': (event) {
                        event.stopPropagation();
                        _shiftMonth(1);
                      },
                    },
                    [_chevronRightIcon()],
                  ),
                ]),
                div(classes: 'table-edit-datetime__weekdays', [
                  for (final label in _weekdayLabels)
                    span(classes: 'table-edit-datetime__weekday', [.text(label)]),
                ]),
                div(classes: 'table-edit-datetime__grid', [
                  for (final day in cells)
                    if (day == null)
                      span(classes: 'table-edit-datetime__day table-edit-datetime__day--empty', [])
                    else
                      button(
                        type: .button,
                        classes: [
                          'table-edit-datetime__day',
                          if (selected != null &&
                              selected.year == _viewYear &&
                              selected.month == _viewMonth &&
                              selected.day == day)
                            'table-edit-datetime__day--selected',
                          if (today.year == _viewYear &&
                              today.month == _viewMonth &&
                              today.day == day)
                            'table-edit-datetime__day--today',
                        ].join(' '),
                        events: {
                          'click': (event) {
                            event.stopPropagation();
                            _selectDay(day);
                          },
                        },
                        [.text('$day')],
                      ),
                ]),
                div(classes: 'table-edit-datetime__time', [
                  span(classes: 'table-edit-datetime__time-label', [.text('Time')]),
                  div(classes: 'table-edit-datetime__time-inputs', [
                    _timeNumberInput(
                      id: '${component.id}-hour',
                      label: 'Hour',
                      value: '$hour12',
                      min: 1,
                      max: 12,
                      onChange: (h) => _setTime(
                        hour: hour12To24(h, isPm),
                        minute: minute,
                      ),
                    ),
                    span(classes: 'table-edit-datetime__time-sep', [.text(':')]),
                    _timeNumberInput(
                      id: '${component.id}-minute',
                      label: 'Minute',
                      value: minute.toString().padLeft(2, '0'),
                      min: 0,
                      max: 59,
                      onChange: (m) => _setTime(hour: hour24, minute: m),
                    ),
                    div(
                      classes: 'table-search-combine table-edit-datetime__ampm',
                      attributes: {'role': 'group', 'aria-label': 'AM or PM'},
                      [
                        _ampmSegment(
                          label: 'AM',
                          selected: !isPm,
                          onSelect: () => _setTime(
                            hour: hour12To24(hour12, false),
                            minute: minute,
                          ),
                        ),
                        _ampmSegment(
                          label: 'PM',
                          selected: isPm,
                          onSelect: () => _setTime(
                            hour: hour12To24(hour12, true),
                            minute: minute,
                          ),
                        ),
                      ],
                    ),
                  ]),
                ]),
                div(classes: 'table-edit-datetime__footer', [
                  button(
                    type: .button,
                    classes: 'table-edit-datetime__footer-btn',
                    events: {
                      'click': (event) {
                        event.stopPropagation();
                        _commitWall(null);
                        _setOpen(false);
                      },
                    },
                    [.text('Clear')],
                  ),
                  button(
                    type: .button,
                    classes: 'table-edit-datetime__footer-btn',
                    events: {
                      'click': (event) {
                        event.stopPropagation();
                        _selectToday();
                      },
                    },
                    [.text('Now')],
                  ),
                ]),
              ],
            ),
        ]),
      ],
    );
  }
}

const _monthAbbrev = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

const _weekdayLabels = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];

typedef _CalendarDay = int?;

Component _ampmSegment({
  required String label,
  required bool selected,
  required void Function() onSelect,
}) {
  return button(
    type: .button,
    classes: [
      'table-search-segment',
      if (selected) 'table-search-segment--active',
    ].join(' '),
    attributes: {'aria-pressed': selected ? 'true' : 'false'},
    events: {
      'click': (event) {
        event.stopPropagation();
        if (!selected) onSelect();
      },
    },
    [.text(label)],
  );
}

Component _timeNumberInput({
  required String id,
  required String label,
  required String value,
  required int min,
  required int max,
  required void Function(int value) onChange,
}) {
  return div(classes: 'table-edit-datetime__time-field', [
    input<String>(
      id: id,
      type: .text,
      classes: 'table-edit-datetime__time-native',
      attributes: {
        'aria-label': label,
        'inputmode': 'numeric',
        'autocomplete': 'off',
      },
      value: value,
      events: {
        'focus': _selectTimeInputContents,
        'click': _selectTimeInputContents,
      },
      onInput: (raw) {
        final trimmed = raw.trim();
        if (trimmed.isEmpty) return;
        final parsed = int.tryParse(trimmed);
        if (parsed == null) return;
        onChange(parsed.clamp(min, max));
      },
    ),
  ]);
}

void _selectTimeInputContents(web.Event event) {
  event.stopPropagation();
  final target = event.target;
  if (target is web.HTMLInputElement) {
    target.select();
  }
}

Component _calendarIcon() {
  return span(classes: 'table-edit-datetime__icon', [
    svg(
      viewBox: '0 0 16 16',
      width: 16.px,
      height: 16.px,
      attributes: {'aria-hidden': 'true', 'fill': 'none'},
      [
        path(
          stroke: const Color('currentColor'),
          strokeWidth: '1.5',
          d: 'M3 3h10v10H3z',
          attributes: const {'stroke-linejoin': 'round'},
          [],
        ),
        path(
          stroke: const Color('currentColor'),
          strokeWidth: '1.5',
          d: 'M3 6h10M6 3v2M10 3v2',
          attributes: const {'stroke-linecap': 'round'},
          [],
        ),
      ],
    ),
  ]);
}

Component _chevronLeftIcon() {
  return svg(
    viewBox: '0 0 16 16',
    width: 14.px,
    height: 14.px,
    attributes: {'aria-hidden': 'true', 'fill': 'none'},
    [
      path(
        stroke: const Color('currentColor'),
        strokeWidth: '1.5',
        d: 'M10 4l-4 4 4 4',
        attributes: const {'stroke-linecap': 'round', 'stroke-linejoin': 'round'},
        [],
      ),
    ],
  );
}

Component _chevronRightIcon() {
  return svg(
    viewBox: '0 0 16 16',
    width: 14.px,
    height: 14.px,
    attributes: {'aria-hidden': 'true', 'fill': 'none'},
    [
      path(
        stroke: const Color('currentColor'),
        strokeWidth: '1.5',
        d: 'M6 4l4 4-4 4',
        attributes: const {'stroke-linecap': 'round', 'stroke-linejoin': 'round'},
        [],
      ),
    ],
  );
}

/// Styles for [TableEditDatetimeField].
@css
List<StyleRule> tableEditDatetimeStyles = [
  css('.table-edit-datetime').styles(
    display: .block,
    position: Position.relative(),
    width: 100.percent,
    maxWidth: 320.px,
    minWidth: .zero,
  ),
  css('.table-edit-datetime--compact').styles(
    width: .auto,
    alignSelf: .start,
    maxWidth: 100.percent,
  ),
  css('.table-edit-datetime__combobox').styles(
    position: Position.relative(),
    display: .block,
    width: 100.percent,
  ),
  css('.table-edit-datetime--compact .table-edit-datetime__combobox').styles(
    width: .auto,
  ),
  css('.table-edit-datetime__trigger').styles(
    display: .flex,
    flexDirection: FlexDirection.row,
    alignItems: .center,
    justifyContent: .spaceBetween,
    gap: Gap.all(10.px),
    width: 100.percent,
    maxWidth: 320.px,
    boxSizing: BoxSizing.borderBox,
    padding: .symmetric(horizontal: 14.px, vertical: 11.px),
    radius: .all(Radius.circular(10.px)),
    border: .all(color: borderColor, width: 1.px, style: .solid),
    backgroundColor: bgColor,
    color: fgColor,
    fontSize: 0.9375.rem,
    cursor: .pointer,
    textAlign: TextAlign.left,
    raw: const {
      'font': 'inherit',
      'line-height': '1.4',
      'transition': 'border-color 0.15s ease, box-shadow 0.15s ease',
    },
  ),
  css('.table-edit-datetime--compact .table-edit-datetime__trigger').styles(
    width: 100.percent,
    maxWidth: 280.px,
  ),
  css('.table-edit-datetime__trigger:hover').styles(
    border: .all(color: mutedColor, width: 1.px, style: .solid),
  ),
  css('.table-edit-datetime__trigger--open, .table-edit-datetime__trigger:focus-visible').styles(
    border: .all(color: primaryColor, width: 1.px, style: .solid),
    raw: const {'box-shadow': '0 0 0 3px var(--zonai-focus-ring)'},
  ),
  css('.table-edit-datetime__trigger-placeholder').styles(color: mutedColor),
  css('.table-edit-datetime__trigger-value').styles(
    flex: Flex(grow: 1, shrink: 1),
    minWidth: .zero,
    overflow: Overflow.hidden,
    raw: const {'text-overflow': 'ellipsis', 'white-space': 'nowrap'},
  ),
  css('.table-edit-datetime__icon').styles(
    flex: Flex(grow: 0, shrink: 0),
    display: .flex,
    color: mutedColor,
  ),
  css('.table-edit-datetime__trigger--open .table-edit-datetime__icon').styles(color: fgColor),
  css('.table-edit-datetime__popover').styles(
    position: Position.absolute(top: 100.percent, left: 0.px, right: 0.px),
    margin: .only(top: 4.px),
    display: .flex,
    flexDirection: FlexDirection.column,
    gap: Gap.all(10.px),
    padding: .all(12.px),
    radius: .all(Radius.circular(10.px)),
    border: .all(color: borderColor, width: 1.px, style: .solid),
    backgroundColor: surfaceColor,
    minWidth: 280.px,
    raw: const {
      'z-index': '30',
      'box-shadow': '0 8px 20px rgb(15 23 42 / 0.12)',
    },
  ),
  css('.table-edit-datetime--compact .table-edit-datetime__popover').styles(
    position: Position.absolute(top: 100.percent, left: 0.px),
    width: .auto,
    maxWidth: 280.px,
    minWidth: 252.px,
    raw: const {'right': 'auto'},
  ),
  css('.table-edit-datetime--compact .table-edit-datetime__day').styles(height: 28.px),
  css('.table-edit-datetime__header').styles(
    display: .flex,
    flexDirection: FlexDirection.row,
    alignItems: .center,
    justifyContent: .spaceBetween,
    gap: Gap.all(8.px),
  ),
  css('.table-edit-datetime__month-label').styles(
    fontSize: 0.875.rem,
    fontWeight: .w600,
    color: fgColor,
  ),
  css('.table-edit-datetime__nav').styles(
    width: 32.px,
    height: 32.px,
    display: .flex,
    alignItems: .center,
    justifyContent: .center,
    padding: .zero,
    border: Border.none,
    backgroundColor: Colors.transparent,
    color: mutedColor,
    cursor: .pointer,
    radius: .all(Radius.circular(8.px)),
    raw: const {'font': 'inherit', 'line-height': '1'},
  ),
  css('.table-edit-datetime__nav:hover').styles(backgroundColor: hoverColor, color: fgColor),
  css('.table-edit-datetime__weekdays').styles(
    display: .grid,
    raw: const {'grid-template-columns': 'repeat(7, 1fr)'},
    gap: Gap.all(2.px),
  ),
  css('.table-edit-datetime__weekday').styles(
    fontSize: 0.6875.rem,
    fontWeight: .w600,
    color: mutedColor,
    textAlign: TextAlign.center,
    padding: .symmetric(vertical: 4.px),
  ),
  css('.table-edit-datetime__grid').styles(
    display: .grid,
    raw: const {'grid-template-columns': 'repeat(7, 1fr)'},
    gap: Gap.all(2.px),
  ),
  css('.table-edit-datetime__day').styles(
    display: .flex,
    alignItems: .center,
    justifyContent: .center,
    height: 32.px,
    padding: .zero,
    border: Border.none,
    backgroundColor: Colors.transparent,
    color: fgColor,
    fontSize: 0.8125.rem,
    cursor: .pointer,
    radius: .all(Radius.circular(8.px)),
    raw: const {'font': 'inherit'},
  ),
  css('.table-edit-datetime__day--empty').styles(raw: const {'cursor': 'default'}),
  css('.table-edit-datetime__day:not(.table-edit-datetime__day--empty):hover').styles(
    backgroundColor: hoverColor,
  ),
  css('.table-edit-datetime__day--today').styles(
    fontWeight: .w600,
    raw: const {'box-shadow': 'inset 0 0 0 1px var(--zonai-border)'},
  ),
  css('.table-edit-datetime__day--selected').styles(
    backgroundColor: primaryColor,
    color: onPrimaryColor,
    fontWeight: .w600,
  ),
  css('.table-edit-datetime__day--selected:hover').styles(backgroundColor: primaryHoverColor),
  css('.table-edit-datetime__time').styles(
    display: .flex,
    flexDirection: FlexDirection.row,
    alignItems: .center,
    gap: Gap.all(10.px),
    padding: .only(top: 4.px),
    border: .only(top: BorderSide.solid(color: borderColor, width: 1.px)),
  ),
  css('.table-edit-datetime__time-label').styles(
    fontSize: 0.75.rem,
    fontWeight: .w600,
    color: mutedColor,
    flex: Flex(grow: 0, shrink: 0),
  ),
  css('.table-edit-datetime__time-inputs').styles(
    display: .flex,
    flexDirection: FlexDirection.row,
    alignItems: .center,
    gap: Gap.all(6.px),
    flex: Flex(grow: 1, shrink: 1),
    minWidth: .zero,
  ),
  css('.table-edit-datetime__time-sep').styles(
    fontSize: 0.875.rem,
    fontWeight: .w600,
    color: mutedColor,
    flex: Flex(grow: 0, shrink: 0),
  ),
  css('.table-edit-datetime__time-field').styles(
    position: Position.relative(),
    flex: Flex(grow: 1, shrink: 1),
    minWidth: .zero,
    maxWidth: 52.px,
  ),
  css('.table-edit-datetime__time-native').styles(
    display: .block,
    width: 100.percent,
    padding: .symmetric(horizontal: 10.px, vertical: 8.px),
    radius: .all(Radius.circular(8.px)),
    border: .all(color: borderColor, width: 1.px, style: .solid),
    backgroundColor: bgColor,
    color: fgColor,
    fontSize: 0.875.rem,
    textAlign: TextAlign.center,
    outline: Outline(style: OutlineStyle.none),
    raw: const {
      'font': 'inherit',
      'line-height': '1.2',
      'appearance': 'none',
      '-webkit-appearance': 'none',
      'transition': 'border-color 0.15s ease, box-shadow 0.15s ease',
    },
  ),
  css('.table-edit-datetime__time-native:hover').styles(
    border: .all(color: mutedColor, width: 1.px, style: .solid),
  ),
  css('.table-edit-datetime__time-native:focus-visible').styles(
    border: .all(color: primaryColor, width: 1.px, style: .solid),
    raw: const {'box-shadow': '0 0 0 3px var(--zonai-focus-ring)'},
  ),
  css('.table-edit-datetime__footer').styles(
    display: .flex,
    flexDirection: FlexDirection.row,
    justifyContent: .spaceBetween,
    gap: Gap.all(8.px),
    padding: .only(top: 2.px),
  ),
  css('.table-edit-datetime__footer-btn').styles(
    padding: .symmetric(horizontal: 10.px, vertical: 6.px),
    fontSize: 0.75.rem,
    fontWeight: .w600,
    cursor: .pointer,
    radius: .all(Radius.circular(6.px)),
    border: .all(color: borderColor, width: 1.px, style: .solid),
    backgroundColor: bgColor,
    color: fgColor,
    raw: const {'font': 'inherit'},
  ),
  css('.table-edit-datetime__footer-btn:hover').styles(backgroundColor: hoverColor),
];
