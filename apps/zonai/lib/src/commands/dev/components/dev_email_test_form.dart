import 'package:nocterm/nocterm.dart';

import 'dev_select_field.dart';
import 'dev_theme.dart';

enum _EmailTestField { none, to, template }

class DevEmailTestForm extends StatefulComponent {
  const DevEmailTestForm({
    required this.emailTemplates,
    required this.onCancel,
    required this.onSubmit,
    super.key,
  });

  final List<String> emailTemplates;
  final VoidCallback onCancel;
  final void Function(String to, String template) onSubmit;

  @override
  State<DevEmailTestForm> createState() => _DevEmailTestFormState();
}

class _DevEmailTestFormState extends State<DevEmailTestForm> {
  final _toController = TextEditingController();
  int _templateIndex = 0;
  _EmailTestField _field = _EmailTestField.to;

  List<String> get _templates => component.emailTemplates;

  int get _focusedFieldIndex => switch (_field) {
    _EmailTestField.none => 0,
    _EmailTestField.to => 0,
    _EmailTestField.template => 1,
  };

  void _blurField() {
    if (_field == _EmailTestField.none) return;
    setState(() => _field = _EmailTestField.none);
  }

  @override
  void dispose() {
    _toController.dispose();
    super.dispose();
  }

  void _cancel() {
    _toController.clear();
    setState(() {
      _templateIndex = 0;
      _field = _EmailTestField.to;
    });
    component.onCancel();
  }

  void _cycleTemplate({required bool forward}) {
    if (_templates.isEmpty) return;
    setState(() {
      _templateIndex = forward
          ? (_templateIndex + 1) % _templates.length
          : (_templateIndex - 1 + _templates.length) % _templates.length;
    });
  }

  void _nextField() {
    setState(() {
      _field = switch (_field) {
        _EmailTestField.none => _EmailTestField.to,
        _EmailTestField.to => _EmailTestField.template,
        _EmailTestField.template => _EmailTestField.none,
      };
    });
  }

  void _previousField() {
    setState(() {
      _field = switch (_field) {
        _EmailTestField.none => _EmailTestField.template,
        _EmailTestField.to => _EmailTestField.none,
        _EmailTestField.template => _EmailTestField.to,
      };
    });
  }

  void _submit() {
    final to = _toController.text.trim();
    if (to.isEmpty || _templates.isEmpty) return;
    component.onSubmit(to, _templates[_templateIndex]);
    _toController.clear();
    setState(() {
      _templateIndex = 0;
      _field = _EmailTestField.to;
    });
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
        if (_field == _EmailTestField.template) {
          if (event.logicalKey == LogicalKey.arrowDown) {
            _cycleTemplate(forward: true);
            return true;
          }
          if (event.logicalKey == LogicalKey.arrowUp) {
            _cycleTemplate(forward: false);
            return true;
          }
          if (event.logicalKey == LogicalKey.enter) {
            _submit();
            return true;
          }
        }
        return false;
      },
      child: DevFormCard(
        title: 'Send Test Email',
        subtitle:
            'Renders the chosen template and sends it to a real inbox. Use this to catch layout issues before going to production.',
        focusedFieldIndex: _focusedFieldIndex,
        onBackgroundTap: _blurField,
        fields: [
          DevFormField(
            label: 'Recipient',
            input: DevTextInput(
              controller: _toController,
              focused: _field == _EmailTestField.to,
              onFocus: () => setState(() => _field = _EmailTestField.to),
              placeholder: 'user@example.com',
              onSubmitted: (_) {
                setState(() => _field = _EmailTestField.template);
              },
            ),
          ),
          DevSelectField(
            label: 'Template',
            options: _templates,
            selectedIndex: _templateIndex,
            focused: _field == _EmailTestField.template,
            onTap: () => setState(() => _field = _EmailTestField.template),
          ),
        ],
      ),
    );
  }
}
