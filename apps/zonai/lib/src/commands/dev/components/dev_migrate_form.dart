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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
          _controller.clear();
          component.onCancel();
          return true;
        }
        if (event.logicalKey == LogicalKey.tab && !event.isShiftPressed) {
          setState(() => _inputFocused = true);
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
              onSubmitted: (name) {
                final trimmed = name.trim();
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
