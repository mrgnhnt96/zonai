import 'package:nocterm/nocterm.dart';

import 'dev_theme.dart';

class DevTextForm extends StatefulComponent {
  const DevTextForm({
    required this.title,
    required this.label,
    required this.placeholder,
    required this.onCancel,
    required this.onSubmit,
    this.submitLabel = 'Create',
    this.obscureText = false,
    super.key,
  });

  final String title;
  final String label;
  final String placeholder;
  final String submitLabel;
  final VoidCallback onCancel;
  final void Function(String value) onSubmit;
  final bool obscureText;

  @override
  State<DevTextForm> createState() => _DevTextFormState();
}

class _DevTextFormState extends State<DevTextForm> {
  final _controller = TextEditingController();
  var _inputFocused = true;
  DevFormAction _focusedAction = DevFormAction.submit;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _cancel() {
    _controller.clear();
    component.onCancel();
  }

  void _blurInput() {
    if (!_inputFocused) return;
    setState(() => _inputFocused = false);
  }

  void _submit() {
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty) return;
    component.onSubmit(trimmed);
    _controller.clear();
  }

  void _activateAction() {
    switch (_effectiveFocusedAction) {
      case DevFormAction.cancel:
        _cancel();
      case DevFormAction.submit:
        _submit();
    }
  }

  bool get _canSubmit => _controller.text.trim().isNotEmpty;

  DevFormAction get _effectiveFocusedAction =>
      devFormEffectiveAction(action: _focusedAction, submitEnabled: _canSubmit);

  int get _focusedFieldIndex => _inputFocused ? 0 : 1;

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
            setState(() {
              _inputFocused = false;
              _focusedAction = devFormFirstAction();
            });
          } else {
            final next = devFormTabNextAction(
              current: _effectiveFocusedAction,
              submitEnabled: _canSubmit,
            );
            setState(() {
              if (next == null) {
                _inputFocused = true;
              } else {
                _focusedAction = next;
              }
            });
          }
          return true;
        }
        if (event.logicalKey == LogicalKey.tab && event.isShiftPressed) {
          if (_inputFocused) {
            setState(() {
              _inputFocused = false;
              _focusedAction = devFormLastAction(submitEnabled: _canSubmit);
            });
          } else {
            final prev = devFormTabPreviousAction(
              current: _effectiveFocusedAction,
              submitEnabled: _canSubmit,
            );
            setState(() {
              if (prev == null) {
                _inputFocused = true;
              } else {
                _focusedAction = prev;
              }
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
        title: component.title,
        onBackgroundTap: _blurInput,
        focusedFieldIndex: _focusedFieldIndex,
        fields: [
          DevFormField(
            label: component.label,
            input: DevTextInput(
              controller: _controller,
              focused: _inputFocused,
              onFocus: () => setState(() => _inputFocused = true),
              obscureText: component.obscureText,
              placeholder: component.placeholder,
              onSubmitted: (_) => _submit(),
            ),
          ),
        ],
        footer: DevFormActionBar(
          submitLabel: component.submitLabel,
          focusedAction: _inputFocused ? null : _effectiveFocusedAction,
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
