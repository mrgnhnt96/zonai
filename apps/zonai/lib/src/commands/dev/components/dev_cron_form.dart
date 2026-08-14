import 'package:nocterm/nocterm.dart';

import 'dev_select_field.dart';
import 'dev_theme.dart';

class DevCronForm extends StatefulComponent {
  const DevCronForm({
    required this.cronJobNames,
    required this.onCancel,
    required this.onSubmit,
    super.key,
  });

  final List<String> cronJobNames;
  final VoidCallback onCancel;
  final void Function(String name) onSubmit;

  @override
  State<DevCronForm> createState() => _DevCronFormState();
}

class _DevCronFormState extends State<DevCronForm> {
  int _jobIndex = 0;
  DevFormAction _focusedAction = DevFormAction.submit;
  var _actionsFocused = false;

  List<String> get _jobs => component.cronJobNames;

  void _cancel() {
    setState(() => _jobIndex = 0);
    component.onCancel();
  }

  void _cycleJob({required bool forward}) {
    if (_jobs.isEmpty) return;
    setState(() {
      _jobIndex = forward
          ? (_jobIndex + 1) % _jobs.length
          : (_jobIndex - 1 + _jobs.length) % _jobs.length;
    });
  }

  void _submit() {
    if (_jobs.isEmpty) return;
    component.onSubmit(_jobs[_jobIndex]);
    setState(() {
      _jobIndex = 0;
      _actionsFocused = false;
    });
  }

  void _activateAction() {
    switch (_effectiveFocusedAction) {
      case DevFormAction.cancel:
        _cancel();
      case DevFormAction.submit:
        _submit();
    }
  }

  bool get _canSubmit => _jobs.isNotEmpty;

  DevFormAction get _effectiveFocusedAction =>
      devFormEffectiveAction(action: _focusedAction, submitEnabled: _canSubmit);

  int get _focusedFieldIndex => _actionsFocused ? 1 : 0;

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
        if (event.logicalKey == LogicalKey.arrowDown) {
          _cycleJob(forward: true);
          return true;
        }
        if (event.logicalKey == LogicalKey.arrowUp) {
          _cycleJob(forward: false);
          return true;
        }
        if (event.logicalKey == LogicalKey.tab && !event.isShiftPressed) {
          if (_actionsFocused) {
            final next = devFormTabNextAction(
              current: _effectiveFocusedAction,
              submitEnabled: _canSubmit,
            );
            setState(() {
              if (next == null) {
                _actionsFocused = false;
              } else {
                _focusedAction = next;
              }
            });
          } else {
            setState(() {
              _actionsFocused = true;
              _focusedAction = devFormFirstAction();
            });
          }
          return true;
        }
        if (event.logicalKey == LogicalKey.tab && event.isShiftPressed) {
          if (_actionsFocused) {
            final prev = devFormTabPreviousAction(
              current: _effectiveFocusedAction,
              submitEnabled: _canSubmit,
            );
            setState(() {
              if (prev == null) {
                _actionsFocused = false;
              } else {
                _focusedAction = prev;
              }
            });
          } else {
            setState(() {
              _actionsFocused = true;
              _focusedAction = devFormLastAction(submitEnabled: _canSubmit);
            });
          }
          return true;
        }
        if (_actionsFocused && devFormActivateKey(event)) {
          _activateAction();
          return true;
        }
        if (devFormActivateKey(event)) {
          _submit();
          return true;
        }
        return false;
      },
      child: DevFormCard(
        title: 'Run Cron Job',
        subtitle:
            'Runs the selected cron job right now, ignoring its normal schedule — handy for testing job logic without waiting.',
        focusedFieldIndex: _focusedFieldIndex,
        fields: [
          DevSelectField(
            label: 'Job',
            options: _jobs,
            selectedIndex: _jobIndex,
            focused: !_actionsFocused,
          ),
        ],
        footer: DevFormActionBar(
          submitLabel: 'Run',
          focusedAction: _actionsFocused ? _effectiveFocusedAction : null,
          onFocusSubmit: () => setState(() {
            _actionsFocused = true;
            _focusedAction = DevFormAction.submit;
          }),
          onFocusCancel: () => setState(() {
            _actionsFocused = true;
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
