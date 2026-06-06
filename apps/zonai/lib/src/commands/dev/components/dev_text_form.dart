import 'package:nocterm/nocterm.dart';

import 'dev_theme.dart';

class DevTextForm extends StatefulComponent {
  const DevTextForm({
    required this.title,
    required this.label,
    required this.placeholder,
    required this.onCancel,
    required this.onSubmit,
    this.obscureText = false,
    super.key,
  });

  final String title;
  final String label;
  final String placeholder;
  final VoidCallback onCancel;
  final void Function(String value) onSubmit;
  final bool obscureText;

  @override
  State<DevTextForm> createState() => _DevTextFormState();
}

class _DevTextFormState extends State<DevTextForm> {
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
        title: component.title,
        onBackgroundTap: _blurInput,
        fields: [
          DevFormField(
            label: component.label,
            input: DevTextInput(
              controller: _controller,
              focused: _inputFocused,
              onFocus: () => setState(() => _inputFocused = true),
              obscureText: component.obscureText,
              placeholder: component.placeholder,
              onSubmitted: (value) {
                final trimmed = value.trim();
                if (trimmed.isEmpty) return;
                component.onSubmit(trimmed);
                _controller.clear();
              },
            ),
          ),
        ],
      ),
    );
  }
}
