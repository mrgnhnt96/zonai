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
          setState(() => _inputFocused = true);
          return true;
        }
        return false;
      },
      child: DevFormCard(
        title: 'Table Rules',
        onBackgroundTap: _blurInput,
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
        footer: Text(
          'Leave empty to evaluate rules with no caller. Press enter to list permissions.',
          style: TextStyle(color: DevTheme.textMuted),
        ),
      ),
    );
  }
}
