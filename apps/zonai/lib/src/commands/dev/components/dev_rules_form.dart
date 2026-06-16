import 'package:nocterm/nocterm.dart';

import 'dev_theme.dart';

class DevRulesForm extends StatefulComponent {
  const DevRulesForm({
    required this.onCancel,
    required this.onSubmit,
    super.key,
  });

  final VoidCallback onCancel;
  final void Function(String? jwt) onSubmit;

  @override
  State<DevRulesForm> createState() => _DevRulesFormState();
}

class _DevRulesFormState extends State<DevRulesForm> {
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

  void _submit() {
    final trimmed = _controller.text.trim();
    component.onSubmit(trimmed.isEmpty ? null : trimmed);
    _controller.clear();
  }

  void _blurInput() {
    if (!_inputFocused) return;
    setState(() => _inputFocused = false);
  }

  void _activateAction() {
    switch (_effectiveFocusedAction) {
      case DevFormAction.cancel:
        _cancel();
      case DevFormAction.submit:
        _submit();
    }
  }

  DevFormAction get _effectiveFocusedAction => devFormEffectiveAction(
    action: _focusedAction,
    submitEnabled: true,
  );

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
              submitEnabled: true,
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
              _focusedAction = devFormLastAction(submitEnabled: true);
            });
          } else {
            final prev = devFormTabPreviousAction(
              current: _effectiveFocusedAction,
              submitEnabled: true,
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
        title: 'Table Rules',
        onBackgroundTap: _blurInput,
        focusedFieldIndex: _focusedFieldIndex,
        fields: [
          DevFormField(
            label: 'JWT (optional):',
            input: DevTextInput(
              controller: _controller,
              focused: _inputFocused,
              onFocus: () => setState(() => _inputFocused = true),
              width: 72,
              placeholder: 'Paste bearer token — leave empty for anonymous',
              onSubmitted: (_) => _submit(),
            ),
          ),
        ],
        footer: DevFormActionBar(
          submitLabel: 'List',
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
        ),
      ),
    );
  }
}
