import 'package:nocterm/nocterm.dart';

import '../actions/schema_scaffold.dart';
import 'dev_select_field.dart';
import 'dev_theme.dart';

enum _SchemaFormField {
  none,
  entityName,
  tableKind,
  authTypes,
  isAdmin,
  canEdit,
  runMigration,
}

class DevSchemaForm extends StatefulComponent {
  const DevSchemaForm({
    required this.onCancel,
    required this.onSubmit,
    super.key,
  });

  final VoidCallback onCancel;
  final bool Function(
    String entityName,
    SchemaTableKind tableKind,
    SchemaAuthConfig authConfig,
    bool runMigration,
  )
  onSubmit;

  @override
  State<DevSchemaForm> createState() => _DevSchemaFormState();
}

class _DevSchemaFormState extends State<DevSchemaForm> {
  static const _tableKinds = SchemaTableKind.values;
  static const _authTypeLabels = ['Password', 'OTP', 'Magic link'];

  final _entityNameController = TextEditingController(text: 'Product');
  int _tableKindIndex = 0;
  final _authTypeSelected = [true, false, false];
  var _isAdmin = false;
  var _canEdit = true;
  var _runMigration = false;
  int _focusedAuthChip = 0;
  _SchemaFormField _field = _SchemaFormField.entityName;

  SchemaTableKind get _tableKind => _tableKinds[_tableKindIndex];

  bool get _isAuthTable => _tableKind == SchemaTableKind.auth;

  SchemaAuthConfig get _authConfig => SchemaAuthConfig(
    password: _authTypeSelected[0],
    otp: _authTypeSelected[1],
    magicLink: _authTypeSelected[2],
    isAdmin: _isAdmin,
    canEdit: _canEdit,
  );

  List<_SchemaFormField> get _visibleFields => [
    _SchemaFormField.entityName,
    _SchemaFormField.tableKind,
    if (_isAuthTable) ...[
      _SchemaFormField.authTypes,
      _SchemaFormField.isAdmin,
      if (_isAdmin) _SchemaFormField.canEdit,
    ],
    _SchemaFormField.runMigration,
  ];

  int get _focusedFieldIndex {
    if (_field == _SchemaFormField.none) return 0;
    return _visibleFields.indexOf(_field).clamp(0, _visibleFields.length - 1);
  }

  void _blurField() {
    if (_field == _SchemaFormField.none) return;
    setState(() => _field = _SchemaFormField.none);
  }

  @override
  void dispose() {
    _entityNameController.dispose();
    super.dispose();
  }

  void _resetForm() {
    _entityNameController.text = 'Product';
    _authTypeSelected
      ..[0] = true
      ..[1] = false
      ..[2] = false;
    _isAdmin = false;
    _canEdit = true;
    _runMigration = false;
    _focusedAuthChip = 0;
    _tableKindIndex = 0;
    _field = _SchemaFormField.entityName;
  }

  void _cancel() {
    _resetForm();
    component.onCancel();
  }

  void _cycleTableKind({required bool forward}) {
    setState(() {
      _tableKindIndex = forward
          ? (_tableKindIndex + 1) % _tableKinds.length
          : (_tableKindIndex - 1 + _tableKinds.length) % _tableKinds.length;
      if (!_visibleFields.contains(_field)) {
        _field = _SchemaFormField.tableKind;
      }
    });
  }

  void _nextField() {
    if (_field == _SchemaFormField.authTypes &&
        _focusedAuthChip < _authTypeLabels.length - 1) {
      setState(() => _focusedAuthChip++);
      return;
    }

    final fields = _visibleFields;
    if (_field == _SchemaFormField.none) {
      setState(() => _field = fields.first);
      return;
    }

    final index = fields.indexOf(_field);
    setState(() {
      _field = index < 0 || index + 1 >= fields.length
          ? _SchemaFormField.none
          : fields[index + 1];
      if (_field == _SchemaFormField.authTypes) {
        _focusedAuthChip = 0;
      }
    });
  }

  void _previousField() {
    if (_field == _SchemaFormField.authTypes && _focusedAuthChip > 0) {
      setState(() => _focusedAuthChip--);
      return;
    }

    final fields = _visibleFields;
    if (_field == _SchemaFormField.none) {
      setState(() => _field = fields.last);
      return;
    }

    final index = fields.indexOf(_field);
    setState(() {
      _field = index <= 0 ? _SchemaFormField.none : fields[index - 1];
      if (_field == _SchemaFormField.authTypes) {
        _focusedAuthChip = _authTypeLabels.length - 1;
      }
    });
  }

  void _toggleBool({
    required bool Function() read,
    required void Function(bool) write,
  }) {
    setState(() => write(!read()));
  }

  void _selectAuthChip(int index) {
    setState(() => _authTypeSelected[index] = !_authTypeSelected[index]);
  }

  void _toggleFocusedAuthChip() {
    setState(() {
      _authTypeSelected[_focusedAuthChip] =
          !_authTypeSelected[_focusedAuthChip];
    });
  }

  void _moveAuthChip({required bool forward}) {
    setState(() {
      _focusedAuthChip = forward
          ? (_focusedAuthChip + 1) % _authTypeLabels.length
          : (_focusedAuthChip - 1 + _authTypeLabels.length) %
                _authTypeLabels.length;
      _field = _SchemaFormField.authTypes;
    });
  }

  void _submit() {
    final entityName = _entityNameController.text.trim();
    if (entityName.isEmpty) return;
    if (_isAuthTable && !_authConfig.hasAnyAuth) return;

    final ok = component.onSubmit(
      entityName,
      _tableKind,
      _authConfig,
      _runMigration,
    );
    if (!ok) return;

    _resetForm();
  }

  List<String> get _tableKindLabels => _tableKinds
      .map(
        (kind) => switch (kind) {
          SchemaTableKind.regular => 'Regular table',
          SchemaTableKind.auth => 'Auth table',
        },
      )
      .toList();

  List<Component> _buildFields() {
    final fields = <Component>[
      DevFormField(
        label: 'Entity name',
        input: DevTextInput(
          controller: _entityNameController,
          focused: _field == _SchemaFormField.entityName,
          onFocus: () => setState(() => _field = _SchemaFormField.entityName),
          placeholder: 'Product',
          onSubmitted: (_) => _submit(),
        ),
      ),
      DevSelectField(
        label: 'Table kind',
        options: _tableKindLabels,
        selectedIndex: _tableKindIndex,
        focused: _field == _SchemaFormField.tableKind,
        onTap: () => setState(() => _field = _SchemaFormField.tableKind),
      ),
    ];

    if (_isAuthTable) {
      fields.addAll([
        DevChipGroup(
          label: 'Auth methods',
          options: _authTypeLabels,
          selected: _authTypeSelected,
          focused: _field == _SchemaFormField.authTypes,
          focusedChipIndex: _focusedAuthChip,
          onChipTap: _selectAuthChip,
          footer: Text(
            'You can add or remove auth methods later in the schema file.',
            style: TextStyle(color: DevTheme.textDim),
            softWrap: true,
          ),
        ),
        DevBoolField(
          label: 'Admin table (isAdmin)',
          value: _isAdmin,
          focused: _field == _SchemaFormField.isAdmin,
          onTap: () => setState(() {
            _isAdmin = !_isAdmin;
            if (!_isAdmin) _canEdit = true;
            _field = _SchemaFormField.isAdmin;
          }),
        ),
        if (_isAdmin)
          DevBoolField(
            label: 'Can edit as admin',
            value: _canEdit,
            focused: _field == _SchemaFormField.canEdit,
            onTap: () => setState(() {
              _canEdit = !_canEdit;
              _field = _SchemaFormField.canEdit;
            }),
          ),
      ]);
    }

    fields.add(
      DevBoolField(
        label: 'Generate migration after create',
        value: _runMigration,
        focused: _field == _SchemaFormField.runMigration,
        onTap: () => setState(() {
          _runMigration = !_runMigration;
          _field = _SchemaFormField.runMigration;
        }),
      ),
    );

    return fields;
  }

  @override
  Component build(BuildContext context) {
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

        if (_field == _SchemaFormField.tableKind) {
          if (event.logicalKey == LogicalKey.arrowDown) {
            _cycleTableKind(forward: true);
            return true;
          }
          if (event.logicalKey == LogicalKey.arrowUp) {
            _cycleTableKind(forward: false);
            return true;
          }
        }

        if (_field == _SchemaFormField.authTypes) {
          if (event.logicalKey == LogicalKey.arrowRight ||
              event.logicalKey == LogicalKey.arrowDown) {
            _moveAuthChip(forward: true);
            return true;
          }
          if (event.logicalKey == LogicalKey.arrowLeft ||
              event.logicalKey == LogicalKey.arrowUp) {
            _moveAuthChip(forward: false);
            return true;
          }
          if (event.logicalKey == LogicalKey.space ||
              event.logicalKey == LogicalKey.enter) {
            _toggleFocusedAuthChip();
            return true;
          }
        }

        if (_field == _SchemaFormField.isAdmin &&
            (event.logicalKey == LogicalKey.space ||
                event.logicalKey == LogicalKey.enter)) {
          _toggleBool(
            read: () => _isAdmin,
            write: (value) {
              _isAdmin = value;
              if (!value) _canEdit = true;
            },
          );
          return true;
        }

        if (_field == _SchemaFormField.canEdit &&
            (event.logicalKey == LogicalKey.space ||
                event.logicalKey == LogicalKey.enter)) {
          _toggleBool(read: () => _canEdit, write: (value) => _canEdit = value);
          return true;
        }

        if (_field == _SchemaFormField.runMigration &&
            (event.logicalKey == LogicalKey.space ||
                event.logicalKey == LogicalKey.enter)) {
          _toggleBool(
            read: () => _runMigration,
            write: (value) => _runMigration = value,
          );
          return true;
        }

        if (_field == _SchemaFormField.entityName &&
            event.logicalKey == LogicalKey.enter) {
          _submit();
          return true;
        }

        return false;
      },
      child: DevFormCard(
        title: 'Create Schema',
        subtitle:
            'Scaffolds a new schema file and ID type. Regular tables include id, name, and timestamps.',
        focusedFieldIndex: _focusedFieldIndex,
        onBackgroundTap: _blurField,
        fields: _buildFields(),
      ),
    );
  }
}
