import 'package:nocterm/nocterm.dart';
import 'package:zonai_schema/payloads.dart';

import '../../../utils/admin_create_shape.dart';
import 'dev_theme.dart';

class DevAdminForm extends StatefulComponent {
  const DevAdminForm({
    required this.extraFields,
    required this.onCancel,
    required this.onSubmit,
    this.loadError,
    super.key,
  });

  final List<ColumnShape> extraFields;
  final String? loadError;
  final VoidCallback onCancel;
  final void Function(
    String email,
    String password,
    Map<String, String> extraFields,
  )
  onSubmit;

  @override
  State<DevAdminForm> createState() => _DevAdminFormState();
}

class _DevAdminFormState extends State<DevAdminForm> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _extraControllers = <String, TextEditingController>{};

  int _fieldIndex = 0;

  List<ColumnShape> get _extraFields => component.extraFields;

  int get _fieldCount => 2 + _extraFields.length;

  bool get _textFieldFocused => _fieldIndex >= 0;

  int get _focusedFieldIndex => _textFieldFocused ? _fieldIndex : 0;

  void _blurField() {
    if (!_textFieldFocused) return;
    setState(() => _fieldIndex = -1);
  }

  @override
  void initState() {
    super.initState();
    for (final shape in _extraFields) {
      _extraControllers[shape.name] = TextEditingController();
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    for (final controller in _extraControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _cancel() {
    _emailController.clear();
    _passwordController.clear();
    for (final controller in _extraControllers.values) {
      controller.clear();
    }
    setState(() => _fieldIndex = 0);
    component.onCancel();
  }

  void _nextField() {
    if (_fieldCount <= 1) return;
    setState(() {
      _fieldIndex = _fieldIndex < 0 ? 0 : (_fieldIndex + 1) % _fieldCount;
    });
  }

  void _previousField() {
    if (_fieldCount <= 1) return;
    setState(() {
      _fieldIndex = _fieldIndex < 0
          ? _fieldCount - 1
          : (_fieldIndex - 1 + _fieldCount) % _fieldCount;
    });
  }

  void _submit() {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) return;

    final extraValues = <String, String>{
      for (final shape in _extraFields)
        shape.name: _extraControllers[shape.name]?.text.trim() ?? '',
    };

    final missing = missingAdminExtraFieldLabels(
      extraFields: _extraFields,
      values: extraValues,
    );
    if (missing.isNotEmpty) return;

    component.onSubmit(email, password, extraValues);
    _emailController.clear();
    _passwordController.clear();
    for (final controller in _extraControllers.values) {
      controller.clear();
    }
    setState(() => _fieldIndex = 0);
  }

  bool _isFieldFocused(int index) => _fieldIndex == index;

  void _focusField(int index) => setState(() => _fieldIndex = index);

  List<Component> _buildFields() {
    final fields = <Component>[
      DevFormField(
        label: 'Email',
        input: DevTextInput(
          controller: _emailController,
          focused: _isFieldFocused(0),
          onFocus: () => _focusField(0),
          placeholder: 'admin@example.com',
          onSubmitted: (_) => _nextField(),
        ),
      ),
      DevFormField(
        label: 'Password',
        input: DevTextInput(
          controller: _passwordController,
          focused: _isFieldFocused(1),
          onFocus: () => _focusField(1),
          obscureText: true,
          placeholder: '••••••••',
          onSubmitted: (_) {
            if (_extraFields.isEmpty) {
              _submit();
            } else {
              _nextField();
            }
          },
        ),
      ),
    ];

    for (var i = 0; i < _extraFields.length; i++) {
      final shape = _extraFields[i];
      fields.add(
        DevFormField(
          label: columnShapeHeaderLabel(shape),
          required: isAdminExtraFieldRequired(shape),
          input: DevTextInput(
            controller: _extraControllers[shape.name]!,
            focused: _isFieldFocused(2 + i),
            onFocus: () => _focusField(2 + i),
            onSubmitted: (_) {
              if (i == _extraFields.length - 1) {
                _submit();
              } else {
                _nextField();
              }
            },
          ),
        ),
      );
    }

    return fields;
  }

  @override
  Component build(BuildContext context) {
    if (component.loadError != null) {
      return DevFormCard(
        title: 'Create Admin',
        accentColor: DevTheme.error,
        fields: [
          Text(
            'Failed to load admin schema: ${component.loadError}',
            style: TextStyle(color: DevTheme.error),
          ),
        ],
      );
    }

    return Focusable(
      focused: true,
      onKeyEvent: (event) {
        if (event.logicalKey == LogicalKey.escape) {
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
        return false;
      },
      child: DevFormCard(
        title: 'Create Admin',
        subtitle:
            'Creates an admin user stored in your local database. Use any email and password — this is for dev testing only.',
        focusedFieldIndex: _focusedFieldIndex,
        onBackgroundTap: _blurField,
        fields: _buildFields(),
      ),
    );
  }
}
