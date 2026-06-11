import 'package:nocterm/nocterm.dart';

import '../../../utils/schema_tables.dart';
import '../actions/part_scaffold.dart';
import 'dev_select_field.dart';
import 'dev_theme.dart';

enum _PartFormField { none, partType, table, className, actions }

class DevPartForm extends StatefulComponent {
  const DevPartForm({
    required this.schemaTables,
    required this.onCancel,
    required this.onSubmit,
    super.key,
  });

  final List<SchemaTableInfo> schemaTables;
  final VoidCallback onCancel;
  final bool Function(
    WorkerPartType partType,
    String className,
    SchemaTableInfo? table,
  )
  onSubmit;

  @override
  State<DevPartForm> createState() => _DevPartFormState();
}

class _DevPartFormState extends State<DevPartForm> {
  static const _partTypes = WorkerPartType.values;

  final _classNameController = TextEditingController();
  int _partTypeIndex = 0;
  int _tableIndex = 0;
  _PartFormField _field = _PartFormField.partType;
  DevFormAction _focusedAction = DevFormAction.submit;

  WorkerPartType get _partType => _partTypes[_partTypeIndex];

  List<SchemaTableInfo> get _tables => component.schemaTables;

  SchemaTableInfo? get _selectedTable => _tables.isEmpty
      ? null
      : _tables[_tableIndex.clamp(0, _tables.length - 1)];

  int get _focusedFieldIndex => switch (_field) {
    _PartFormField.none => 0,
    _PartFormField.partType => 0,
    _PartFormField.table => 1,
    _PartFormField.className => _partType.requiresTable ? 2 : 1,
    _PartFormField.actions => _partType.requiresTable ? 2 : 1,
  };

  void _blurField() {
    if (_field == _PartFormField.none) return;
    setState(() => _field = _PartFormField.none);
  }

  @override
  void initState() {
    super.initState();
    _syncDefaultClassName();
  }

  @override
  void dispose() {
    _classNameController.dispose();
    super.dispose();
  }

  void _syncDefaultClassName() {
    if (!_partType.requiresTable) {
      _classNameController.text = 'MyCron';
      return;
    }

    final table = _selectedTable;
    if (table == null) {
      _classNameController.clear();
      return;
    }

    _classNameController.text = defaultClassName(_partType, table);
  }

  void _cancel() {
    _classNameController.clear();
    setState(() {
      _partTypeIndex = 0;
      _tableIndex = 0;
      _field = _PartFormField.partType;
    });
    component.onCancel();
  }

  void _cyclePartType({required bool forward}) {
    setState(() {
      _partTypeIndex = forward
          ? (_partTypeIndex + 1) % _partTypes.length
          : (_partTypeIndex - 1 + _partTypes.length) % _partTypes.length;
      if (!_partType.requiresTable && _field == _PartFormField.table) {
        _field = _PartFormField.className;
      }
      _syncDefaultClassName();
    });
  }

  void _cycleTable({required bool forward}) {
    if (_tables.isEmpty || !_partType.requiresTable) return;
    setState(() {
      _tableIndex = forward
          ? (_tableIndex + 1) % _tables.length
          : (_tableIndex - 1 + _tables.length) % _tables.length;
      _syncDefaultClassName();
    });
  }

  void _nextField() {
    if (_field == _PartFormField.actions) {
      setState(() {
        _focusedAction = _focusedAction == DevFormAction.cancel
            ? DevFormAction.submit
            : DevFormAction.cancel;
      });
      return;
    }

    setState(() {
      _field = switch (_field) {
        _PartFormField.none => _PartFormField.partType,
        _PartFormField.partType =>
          _partType.requiresTable
              ? _PartFormField.table
              : _PartFormField.className,
        _PartFormField.table => _PartFormField.className,
        _PartFormField.className => _PartFormField.actions,
        _PartFormField.actions => _PartFormField.none,
      };
      if (_field == _PartFormField.actions) {
        _focusedAction = DevFormAction.cancel;
      }
    });
  }

  void _previousField() {
    if (_field == _PartFormField.actions) {
      setState(() {
        if (_focusedAction == DevFormAction.submit) {
          _focusedAction = DevFormAction.cancel;
        } else {
          _field = _PartFormField.className;
        }
      });
      return;
    }

    setState(() {
      _field = switch (_field) {
        _PartFormField.none => _PartFormField.actions,
        _PartFormField.partType => _PartFormField.none,
        _PartFormField.table => _PartFormField.partType,
        _PartFormField.className =>
          _partType.requiresTable
              ? _PartFormField.table
              : _PartFormField.partType,
        _PartFormField.actions => _PartFormField.className,
      };
      if (_field == _PartFormField.actions) {
        _focusedAction = DevFormAction.submit;
      }
    });
  }

  void _activateAction() {
    switch (_focusedAction) {
      case DevFormAction.cancel:
        _cancel();
      case DevFormAction.submit:
        _submit();
    }
  }

  bool get _canSubmit {
    final className = _classNameController.text.trim();
    if (className.isEmpty) return false;
    if (_partType.requiresTable && _selectedTable == null) return false;
    return true;
  }

  void _submit() {
    final className = _classNameController.text.trim();
    if (className.isEmpty) return;
    if (_partType.requiresTable && _selectedTable == null) return;

    final ok = component.onSubmit(
      _partType,
      className,
      _partType.requiresTable ? _selectedTable : null,
    );
    if (!ok) return;

    _classNameController.clear();
    setState(() {
      _partTypeIndex = 0;
      _tableIndex = 0;
      _field = _PartFormField.partType;
      _syncDefaultClassName();
    });
  }

  List<String> get _partTypeLabels =>
      _partTypes.map((type) => type.label).toList();

  List<String> get _tableLabels =>
      _tables.map((table) => table.tableName).toList();

  @override
  Component build(BuildContext context) {
    final fields = <Component>[
      DevSelectField(
        label: 'Part type',
        options: _partTypeLabels,
        selectedIndex: _partTypeIndex,
        focused: _field == _PartFormField.partType,
        onTap: () => setState(() => _field = _PartFormField.partType),
      ),
    ];

    if (_partType.requiresTable) {
      fields.add(
        DevSelectField(
          label: 'Table',
          options: _tableLabels,
          selectedIndex: _tableIndex,
          focused: _field == _PartFormField.table,
          onTap: () => setState(() => _field = _PartFormField.table),
        ),
      );
    }

    fields.add(
      DevFormField(
        label: 'Class name',
        input: DevTextInput(
          controller: _classNameController,
          focused: _field == _PartFormField.className,
          onFocus: () => setState(() => _field = _PartFormField.className),
          placeholder: 'UserOperations',
          onSubmitted: (_) => _submit(),
        ),
      ),
    );

    return Focusable(
      focused: true,
      onKeyEvent: (event) {
        if (event.logicalKey == LogicalKey.escape ||
            event.logicalKey == LogicalKey.keyQ) {
          _cancel();
          return true;
        }
        if (event.logicalKey == LogicalKey.tab && !event.isShiftPressed) {
          _nextField();
          return true;
        }
        if (event.logicalKey == LogicalKey.tab && event.isShiftPressed) {
          _previousField();
          return true;
        }

        if (_field == _PartFormField.partType) {
          if (event.logicalKey == LogicalKey.arrowDown) {
            _cyclePartType(forward: true);
            return true;
          }
          if (event.logicalKey == LogicalKey.arrowUp) {
            _cyclePartType(forward: false);
            return true;
          }
        }

        if (_field == _PartFormField.table && _partType.requiresTable) {
          if (event.logicalKey == LogicalKey.arrowDown) {
            _cycleTable(forward: true);
            return true;
          }
          if (event.logicalKey == LogicalKey.arrowUp) {
            _cycleTable(forward: false);
            return true;
          }
        }

        if (_field == _PartFormField.className &&
            event.logicalKey == LogicalKey.enter) {
          _submit();
          return true;
        }

        if (_field == _PartFormField.actions &&
            event.logicalKey == LogicalKey.enter) {
          _activateAction();
          return true;
        }

        return false;
      },
      child: DevFormCard(
        title: 'Create Worker Part',
        subtitle:
            'Pick a part type and enter a class name. The source file will be generated in the correct workers directory automatically.',
        focusedFieldIndex: _focusedFieldIndex,
        onBackgroundTap: _blurField,
        fields: fields,
        footer: DevFormActionBar(
          submitLabel: 'Create',
          focusedAction: _field == _PartFormField.actions ? _focusedAction : null,
          onFocusSubmit: () => setState(() {
            _field = _PartFormField.actions;
            _focusedAction = DevFormAction.submit;
          }),
          onFocusCancel: () => setState(() {
            _field = _PartFormField.actions;
            _focusedAction = DevFormAction.cancel;
          }),
          onSubmit: _submit,
          onCancel: _cancel,
          submitEnabled: _canSubmit,
        ),
      ),
    );
  }
}
