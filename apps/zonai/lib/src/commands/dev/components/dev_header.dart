import 'package:nocterm/nocterm.dart';

import 'dev_theme.dart';

enum DevActionBadgeState { running, succeeded }

const _maxIndividualBadges = 3;

class DevHeader extends StatelessComponent {
  const DevHeader({
    required this.runningActions,
    required this.serverRunning,
    super.key,
  });

  final Map<String, DevActionBadgeState> runningActions;
  final bool serverRunning;

  @override
  Component build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: DevTheme.surface,
        border: BoxBorder(bottom: BorderSide(color: DevTheme.border, width: 1)),
      ),
      child: Row(
        children: [
          Container(
            width: 1,
            decoration: BoxDecoration(color: DevTheme.accent),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Text(
                          'zonai',
                          style: TextStyle(
                            color: DevTheme.text,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(width: 1),
                        Text('/', style: TextStyle(color: DevTheme.textDim)),
                        SizedBox(width: 1),
                        Text(
                          'dev',
                          style: TextStyle(
                            color: DevTheme.accentBright,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (runningActions.isNotEmpty) ...[
                          SizedBox(width: 2),
                          _ActionBadges(actions: runningActions),
                        ],
                      ],
                    ),
                  ),
                  _ServerBadge(running: serverRunning),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBadges extends StatelessComponent {
  const _ActionBadges({required this.actions});

  final Map<String, DevActionBadgeState> actions;

  @override
  Component build(BuildContext context) {
    if (actions.length <= _maxIndividualBadges) {
      return Row(
        children: [
          for (final entry in actions.entries) ...[
            _ActionBadge(label: entry.key, state: entry.value),
            SizedBox(width: 1),
          ],
        ],
      );
    }

    return _GroupedActionBadge(actions: actions);
  }
}

class _GroupedActionBadge extends StatelessComponent {
  const _GroupedActionBadge({required this.actions});

  final Map<String, DevActionBadgeState> actions;

  @override
  Component build(BuildContext context) {
    final running = actions.entries
        .where((entry) => entry.value == DevActionBadgeState.running)
        .length;
    final succeededEntries = actions.entries.where(
      (entry) => entry.value == DevActionBadgeState.succeeded,
    );

    return Row(
      children: [
        if (running > 0) ...[
          _RunningCountBadge(count: running),
          SizedBox(width: 1),
        ],
        for (final entry in succeededEntries) ...[
          _ActionBadge(label: entry.key, state: DevActionBadgeState.succeeded),
          SizedBox(width: 1),
        ],
      ],
    );
  }
}

class _RunningCountBadge extends StatelessComponent {
  const _RunningCountBadge({required this.count});

  final int count;

  @override
  Component build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: DevTheme.warningMuted,
        border: BoxBorder.all(color: DevTheme.warning),
      ),
      padding: EdgeInsets.symmetric(horizontal: 1),
      child: Text(
        '⟳ $count ',
        style: TextStyle(color: DevTheme.warning, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _ActionBadge extends StatelessComponent {
  const _ActionBadge({required this.label, required this.state});

  final String label;
  final DevActionBadgeState state;

  @override
  Component build(BuildContext context) {
    final succeeded = state == DevActionBadgeState.succeeded;

    return Container(
      decoration: BoxDecoration(
        color: succeeded ? DevTheme.successMuted : DevTheme.warningMuted,
        border: BoxBorder.all(
          color: succeeded ? DevTheme.successBorder : DevTheme.warning,
        ),
      ),
      padding: EdgeInsets.symmetric(horizontal: 1),
      child: Text(
        '${succeeded ? '✓' : '⟳'} $label ',
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: succeeded ? DevTheme.success : DevTheme.warning,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _ServerBadge extends StatelessComponent {
  const _ServerBadge({required this.running});

  final bool running;

  @override
  Component build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: running ? DevTheme.successMuted : DevTheme.errorMuted,
        border: BoxBorder.all(
          color: running ? DevTheme.successBorder : DevTheme.errorBorder,
        ),
      ),
      padding: EdgeInsets.symmetric(horizontal: 1),
      child: Text(
        running ? '● server online' : '○ server offline',
        style: TextStyle(
          color: running ? DevTheme.success : DevTheme.error,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
