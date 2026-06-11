import 'dart:async';

import 'package:nocterm/nocterm.dart';

import 'dev_theme.dart';

enum _ConfirmChoice { confirm, cancel }

class DevConfirmForm extends StatefulComponent {
  const DevConfirmForm({
    required this.title,
    required this.message,
    required this.onCancel,
    required this.onConfirm,
    super.key,
  });

  final String title;
  final String message;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  State<DevConfirmForm> createState() => _DevConfirmFormState();
}

class _DevConfirmFormState extends State<DevConfirmForm> {
  static const _holdDuration = Duration(seconds: 3);
  static const _minHintDuration = Duration(milliseconds: 500);
  static const _countdownTick = Duration(milliseconds: 100);

  _ConfirmChoice _choice = _ConfirmChoice.confirm;
  Timer? _holdTimer;
  Timer? _countdownTimer;
  Timer? _hintHideTimer;
  DateTime? _holdStartedAt;
  DateTime? _hintShownAt;
  int? _holdSecondsRemaining;
  var _showHoldHint = false;

  @override
  void dispose() {
    _holdTimer?.cancel();
    _countdownTimer?.cancel();
    _hintHideTimer?.cancel();
    super.dispose();
  }

  void _activateChoice(_ConfirmChoice choice) {
    setState(() => _choice = choice);
    switch (choice) {
      case _ConfirmChoice.confirm:
        component.onConfirm();
      case _ConfirmChoice.cancel:
        component.onCancel();
    }
  }

  void _toggleChoice() {
    setState(() {
      _choice = _choice == _ConfirmChoice.confirm
          ? _ConfirmChoice.cancel
          : _ConfirmChoice.confirm;
    });
  }

  void _submitFocused() {
    switch (_choice) {
      case _ConfirmChoice.confirm:
        component.onConfirm();
      case _ConfirmChoice.cancel:
        component.onCancel();
    }
  }

  void _cancelHold({required bool completed}) {
    _holdTimer?.cancel();
    _holdTimer = null;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _holdStartedAt = null;

    if (completed) {
      _hintHideTimer?.cancel();
      setState(() {
        _showHoldHint = false;
        _holdSecondsRemaining = null;
        _hintShownAt = null;
      });
      return;
    }

    final shownAt = _hintShownAt;
    if (shownAt == null || !_showHoldHint) return;

    final elapsed = DateTime.now().difference(shownAt);
    final remaining = _minHintDuration - elapsed;
    _hintHideTimer?.cancel();
    _hintHideTimer = Timer(
      remaining.isNegative ? Duration.zero : remaining,
      () {
        if (!mounted) return;
        setState(() {
          _showHoldHint = false;
          _holdSecondsRemaining = null;
          _hintShownAt = null;
        });
      },
    );
  }

  void _updateHoldCountdown() {
    final startedAt = _holdStartedAt;
    if (startedAt == null) return;

    final remainingMs =
        _holdDuration.inMilliseconds -
        DateTime.now().difference(startedAt).inMilliseconds;
    if (remainingMs <= 0) return;

    final seconds = (remainingMs / 1000).ceil().clamp(
      1,
      _holdDuration.inSeconds,
    );
    if (_holdSecondsRemaining == seconds) return;

    setState(() => _holdSecondsRemaining = seconds);
  }

  void _onConfirmTapDown(TapDownDetails _) {
    _hintHideTimer?.cancel();
    final now = DateTime.now();
    _holdStartedAt = now;
    _hintShownAt = now;

    setState(() {
      _choice = _ConfirmChoice.confirm;
      _showHoldHint = true;
      _holdSecondsRemaining = _holdDuration.inSeconds;
    });

    _holdTimer?.cancel();
    _holdTimer = Timer(_holdDuration, () {
      if (!mounted) return;
      _cancelHold(completed: true);
      component.onConfirm();
    });

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(_countdownTick, (_) {
      if (!mounted) return;
      _updateHoldCountdown();
    });
  }

  void _onConfirmTapEnd() {
    if (_holdStartedAt == null) return;
    _cancelHold(completed: false);
  }

  @override
  Component build(BuildContext context) {
    return Focusable(
      focused: true,
      onKeyEvent: (event) {
        switch (event.logicalKey) {
          case LogicalKey.escape:
          case LogicalKey.keyN:
          case LogicalKey.keyQ:
            component.onCancel();
            return true;
          case LogicalKey.keyY:
            component.onConfirm();
            return true;
          case LogicalKey.tab:
            _toggleChoice();
            return true;
          case LogicalKey.enter:
          case LogicalKey.space:
            _submitFocused();
            return true;
          default:
            return false;
        }
      },
      child: DevFormCard(
        title: component.title,
        subtitle:
            'Permanently deletes all rows from your local database. Type CONFIRM to proceed — this cannot be undone.',
        accentColor: DevTheme.error,
        fields: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('⚠', style: TextStyle(color: DevTheme.warning)),
              SizedBox(height: 0.5),
              Text(component.message, style: TextStyle(color: DevTheme.text)),
              SizedBox(height: 1.5),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      DevFormButton(
                        label: 'Confirm',
                        focused: _choice == _ConfirmChoice.confirm,
                        destructive: true,
                        onTapDown: _onConfirmTapDown,
                        onTapUp: (_) => _onConfirmTapEnd(),
                        onTapCancel: _onConfirmTapEnd,
                      ),
                      SizedBox(width: 1),
                      DevFormButton(
                        label: 'Cancel',
                        focused: _choice == _ConfirmChoice.cancel,
                        onTap: () => _activateChoice(_ConfirmChoice.cancel),
                      ),
                    ],
                  ),
                  if (_showHoldHint && _holdSecondsRemaining != null) ...[
                    SizedBox(height: 0.5),
                    Text(
                      'hold for ${_holdSecondsRemaining}s to confirm',
                      style: TextStyle(color: DevTheme.errorSoft),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
