import 'package:nocterm/nocterm.dart';

import 'dev_theme.dart';

class DevMigrateForm extends StatefulComponent {
  const DevMigrateForm({
    required this.onCancel,
    required this.onSubmit,
    super.key,
  });

  final VoidCallback onCancel;
  final void Function(String name) onSubmit;

  @override
  State<DevMigrateForm> createState() => _DevMigrateFormState();
}

class _DevMigrateFormState extends State<DevMigrateForm> {
  final _controller = TextEditingController();
  var _inputFocused = true;
  DevFormAction _focusedAction = DevFormAction.submit;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _blurInput() {
    if (!_inputFocused) return;
    setState(() => _inputFocused = false);
  }

  void _focusActions() {
    setState(() {
      _inputFocused = false;
      _focusedAction = DevFormAction.submit;
    });
  }

  void _submit() {
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty) return;
    component.onSubmit(trimmed);
    _controller.clear();
  }

  void _cancel() {
    _controller.clear();
    component.onCancel();
  }

  void _activateAction() {
    switch (_focusedAction) {
      case DevFormAction.cancel:
        _cancel();
      case DevFormAction.submit:
        _submit();
    }
  }

  bool get _canSubmit => _controller.text.trim().isNotEmpty;

  @override
  Component build(BuildContext context) {
    return Focusable(
      focused: true,
      onKeyEvent: (event) {
        if (event.logicalKey == LogicalKey.escape) {
          _cancel();
          return true;
        }
        if (event.logicalKey == LogicalKey.tab && !event.isShiftPressed) {
          if (_inputFocused) {
            _focusActions();
          } else {
            setState(() {
              _focusedAction = _focusedAction == DevFormAction.cancel
                  ? DevFormAction.submit
                  : DevFormAction.cancel;
            });
          }
          return true;
        }
        if (event.logicalKey == LogicalKey.tab && event.isShiftPressed) {
          if (!_inputFocused) {
            setState(() => _inputFocused = true);
          } else {
            setState(() {
              _focusedAction = _focusedAction == DevFormAction.submit
                  ? DevFormAction.cancel
                  : DevFormAction.submit;
            });
          }
          return true;
        }
        if (!_inputFocused && devFormActivateKey(event)) {
          _activateAction();
          return true;
        }
        return false;
      },
      child: DevFormCard(
        title: 'Generate Migration',
        subtitle:
            'Compares your schema files to the last snapshot and writes a migration for any changes. Name it after what changed — it becomes part of the filename.',
        onBackgroundTap: _blurInput,
        fields: [
          DevFormField(
            label: 'Migration name',
            input: DevTextInput(
              controller: _controller,
              focused: _inputFocused,
              onFocus: () => setState(() => _inputFocused = true),
              placeholder: 'add_users_table',
              onSubmitted: (_) => _submit(),
            ),
          ),
        ],
        footer: DevFormActionBar(
          submitLabel: 'Generate',
          focusedAction: _inputFocused ? null : _focusedAction,
          onFocusSubmit: () => setState(() {
            _inputFocused = false;
            _focusedAction = DevFormAction.submit;
          }),
          onFocusCancel: () => setState(() {
            _inputFocused = false;
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
