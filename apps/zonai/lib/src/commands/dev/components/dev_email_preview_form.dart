import 'package:nocterm/nocterm.dart';

import '../../../deps/fs.dart';
import '../../../deps/settings.dart';
import '../../../utils/email_template_variables.dart';
import 'dev_select_field.dart';
import 'dev_theme.dart';

enum _PreviewField { none, template, preview, variables }

class DevEmailPreviewForm extends StatefulComponent {
  const DevEmailPreviewForm({
    required this.emailTemplates,
    required this.onCancel,
    required this.onPreview,
    super.key,
  });

  final List<String> emailTemplates;
  final VoidCallback onCancel;
  final void Function(String template, Map<String, String> variables) onPreview;

  @override
  State<DevEmailPreviewForm> createState() => _DevEmailPreviewFormState();
}

class _DevEmailPreviewFormState extends State<DevEmailPreviewForm> {
  final _variablesController = TextEditingController();
  int _templateIndex = 0;
  _PreviewField _field = _PreviewField.none;
  List<String> _requiredVariables = [];

  List<String> get _templates => component.emailTemplates;

  String? get _selectedTemplate =>
      _templates.isEmpty ? null : _templates[_templateIndex];

  bool get _variablesFocused => _field == _PreviewField.variables;

  int get _focusedFieldIndex => _variablesFocused ? 1 : 0;

  @override
  void initState() {
    super.initState();
    _variablesController.addListener(_onVariablesChanged);
    _loadVariablesForSelectedTemplate();
  }

  @override
  void dispose() {
    _variablesController.removeListener(_onVariablesChanged);
    _variablesController.dispose();
    super.dispose();
  }

  void _onVariablesChanged() {
    if (mounted) setState(() {});
  }

  String? _templateSource(String template) {
    final file = fs.file(
      fs.path.join(settings.emailTemplatesPath, '$template.html'),
    );
    if (!file.existsSync()) return null;
    return file.readAsStringSync();
  }

  void _loadVariablesForSelectedTemplate() {
    final template = _selectedTemplate;
    if (template == null) {
      _requiredVariables = [];
      _variablesController
        ..text = ''
        ..selection = const TextSelection.collapsed(offset: 0);
      return;
    }

    final source = _templateSource(template);
    if (source == null) {
      _requiredVariables = [];
      _variablesController
        ..text = ''
        ..selection = const TextSelection.collapsed(offset: 0);
      return;
    }

    _requiredVariables = extractMustacheVariables(source);
    final lines = formatVariableLines(defaultVariablesForTemplate(source));
    _variablesController.text = lines;
    _variablesController.selection = TextSelection.collapsed(
      offset: lines.length,
    );
  }

  List<String> get _missingVariables => missingTemplateVariableKeys(
    _requiredVariables,
    parseVariableLines(_variablesController.text),
  );

  void _blurField() {
    if (_field == _PreviewField.none) return;
    setState(() => _field = _PreviewField.none);
  }

  void _cancel() {
    _variablesController.clear();
    setState(() {
      _templateIndex = 0;
      _field = _PreviewField.none;
      _requiredVariables = [];
    });
    component.onCancel();
  }

  void _cycleTemplate({required bool forward}) {
    if (_templates.isEmpty) return;
    setState(() {
      _templateIndex = forward
          ? (_templateIndex + 1) % _templates.length
          : (_templateIndex - 1 + _templates.length) % _templates.length;
      _field = _PreviewField.template;
      _loadVariablesForSelectedTemplate();
    });
  }

  void _nextField() {
    final canPreview = _missingVariables.isEmpty;
    setState(() {
      _field = switch (_field) {
        _PreviewField.none => _PreviewField.template,
        _PreviewField.template => _PreviewField.variables,
        _PreviewField.variables =>
          canPreview ? _PreviewField.preview : _PreviewField.template,
        _PreviewField.preview => _PreviewField.template,
      };
    });
  }

  void _previousField() {
    final canPreview = _missingVariables.isEmpty;
    setState(() {
      _field = switch (_field) {
        _PreviewField.none =>
          canPreview ? _PreviewField.preview : _PreviewField.variables,
        _PreviewField.template =>
          canPreview ? _PreviewField.preview : _PreviewField.variables,
        _PreviewField.variables => _PreviewField.template,
        _PreviewField.preview => _PreviewField.variables,
      };
    });
  }

  void _activateFocusedField() {
    switch (_field) {
      case _PreviewField.none:
        setState(() => _field = _PreviewField.template);
      case _PreviewField.template:
        setState(() => _field = _PreviewField.variables);
      case _PreviewField.preview:
        _preview();
      case _PreviewField.variables:
        break;
    }
  }

  bool _handleQuitKey() {
    if (_field != _PreviewField.none) {
      _blurField();
      return true;
    }
    _cancel();
    return true;
  }

  void _preview() {
    final template = _selectedTemplate;
    if (template == null) return;

    final missing = _missingVariables;
    if (missing.isNotEmpty) {
      setState(() => _field = _PreviewField.variables);
      return;
    }

    component.onPreview(
      template,
      parseVariableLines(_variablesController.text),
    );
  }

  Component? _requiredFooter() {
    if (_requiredVariables.isEmpty) return null;
    return Text(
      'Required: ${_requiredVariables.join(', ')}',
      style: TextStyle(color: DevTheme.textMuted),
    );
  }

  @override
  Component build(BuildContext context) {
    if (_templates.isEmpty) {
      return Focusable(
        focused: true,
        onKeyEvent: (event) {
          if (event.logicalKey == LogicalKey.escape ||
              event.logicalKey == LogicalKey.keyQ) {
            _cancel();
            return true;
          }
          return false;
        },
        child: DevFormCard(
          title: 'Preview Email',
          accentColor: DevTheme.warning,
          fields: const [
            DevEmptyState(
              title: 'No templates found',
              message:
                  'Add .html files under lib/src/email_templates, or create one from the menu.',
            ),
          ],
        ),
      );
    }

    final missing = _missingVariables;

    return Focusable(
      focused: true,
      onKeyEvent: (event) {
        if (_variablesFocused) return false;
        if (event.logicalKey == LogicalKey.escape ||
            event.logicalKey == LogicalKey.keyQ) {
          return _handleQuitKey();
        }
        if (event.logicalKey == LogicalKey.tab && !event.isShiftPressed) {
          _nextField();
          return true;
        }
        if (event.logicalKey == LogicalKey.tab && event.isShiftPressed) {
          _previousField();
          return true;
        }
        if (_field == _PreviewField.template) {
          if (event.logicalKey == LogicalKey.arrowDown) {
            _cycleTemplate(forward: true);
            return true;
          }
          if (event.logicalKey == LogicalKey.arrowUp) {
            _cycleTemplate(forward: false);
            return true;
          }
        }
        if (devFormActivateKey(event)) {
          _activateFocusedField();
          return true;
        }
        return false;
      },
      child: DevFormCard(
        title: 'Preview Email',
        subtitle:
            'Supply values for each template variable (one key=value per line), then press Ctrl/Cmd+Enter to open the rendered email in your browser.',
        focusedFieldIndex: _focusedFieldIndex,
        onBackgroundTap: _blurField,
        fields: const [],
        expandedField: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DevSelectField(
              label: 'Template',
              options: _templates,
              selectedIndex: _templateIndex,
              focused: _field == _PreviewField.template,
              footer: _requiredFooter(),
              onTap: () => setState(() => _field = _PreviewField.template),
            ),
            SizedBox(height: 1),
            DevFieldLabel(label: 'Variables'),
            SizedBox(
              height: devTextAreaTotalHeight(3).toDouble(),
              child: DevTextArea(
                controller: _variablesController,
                focused: _variablesFocused,
                hasError: missing.isNotEmpty,
                minLines: 3,
                onFocus: () => setState(() => _field = _PreviewField.variables),
                placeholder: 'name=Test User\nemail=user@example.com',
                onSubmitted: (_) => _preview(),
                onKeyEvent: (event) {
                  if (event.logicalKey == LogicalKey.escape) {
                    return _handleQuitKey();
                  }
                  if (event.logicalKey == LogicalKey.tab &&
                      !event.isShiftPressed) {
                    _nextField();
                    return true;
                  }
                  if (event.logicalKey == LogicalKey.tab &&
                      event.isShiftPressed) {
                    _previousField();
                    return true;
                  }
                  return false;
                },
              ),
            ),
            Expanded(child: SizedBox()),
            if (missing.isNotEmpty) ...[
              SizedBox(height: 0.5),
              Text(
                'Missing: ${missing.join(', ')}',
                style: TextStyle(color: DevTheme.error),
              ),
            ],
          ],
        ),
        footer: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            DevFormButton(
              label: 'Preview',
              primary: true,
              enabled: missing.isEmpty,
              focused: _field == _PreviewField.preview && missing.isEmpty,
              onTap: () {
                setState(() => _field = _PreviewField.preview);
                _preview();
              },
            ),
          ],
        ),
      ),
    );
  }
}
