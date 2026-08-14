import 'package:nocterm/nocterm.dart';

import 'dev_select_field.dart';
import 'dev_theme.dart';

enum _EmailTestField { none, to, template, actions }

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
  DevFormAction _focusedAction = DevFormAction.submit;

  List<String> get _templates => component.emailTemplates;

  int get _focusedFieldIndex => switch (_field) {
    _EmailTestField.none => 0,
    _EmailTestField.to => 0,
    _EmailTestField.template => 1,
    _EmailTestField.actions => 2,
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
    if (_field == _EmailTestField.actions) {
      final next = devFormTabNextAction(
        current: _effectiveFocusedAction,
        submitEnabled: _canSubmit,
      );
      setState(() {
        if (next == null) {
          _field = _EmailTestField.to;
        } else {
          _focusedAction = next;
        }
      });
      return;
    }

    setState(() {
      _field = switch (_field) {
        _EmailTestField.none => _EmailTestField.to,
        _EmailTestField.to => _EmailTestField.template,
        _EmailTestField.template => _EmailTestField.actions,
        _EmailTestField.actions => _EmailTestField.none,
      };
      if (_field == _EmailTestField.actions) {
        _focusedAction = devFormFirstAction();
      }
    });
  }

  void _previousField() {
    if (_field == _EmailTestField.actions) {
      final prev = devFormTabPreviousAction(
        current: _effectiveFocusedAction,
        submitEnabled: _canSubmit,
      );
      setState(() {
        if (prev == null) {
          _field = _EmailTestField.template;
        } else {
          _focusedAction = prev;
        }
      });
      return;
    }

    setState(() {
      _field = switch (_field) {
        _EmailTestField.none => _EmailTestField.actions,
        _EmailTestField.to => _EmailTestField.actions,
        _EmailTestField.template => _EmailTestField.to,
        _EmailTestField.actions => _EmailTestField.template,
      };
      if (_field == _EmailTestField.actions) {
        _focusedAction = devFormLastAction(submitEnabled: _canSubmit);
      }
    });
  }

  DevFormAction get _effectiveFocusedAction =>
      devFormEffectiveAction(action: _focusedAction, submitEnabled: _canSubmit);

  void _activateAction() {
    switch (_effectiveFocusedAction) {
      case DevFormAction.cancel:
        _cancel();
      case DevFormAction.submit:
        _submit();
    }
  }

  bool get _canSubmit {
    final to = _toController.text.trim();
    return to.isNotEmpty && _templates.isNotEmpty;
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
        if (_field == _EmailTestField.actions && devFormActivateKey(event)) {
          _activateAction();
          return true;
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
        footer: DevFormActionBar(
          submitLabel: 'Send',
          focusedAction: _field == _EmailTestField.actions
              ? _effectiveFocusedAction
              : null,
          onFocusSubmit: () => setState(() {
            _field = _EmailTestField.actions;
            _focusedAction = DevFormAction.submit;
          }),
          onFocusCancel: () => setState(() {
            _field = _EmailTestField.actions;
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
