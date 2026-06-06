import 'package:nocterm/nocterm.dart';

import 'dev_theme.dart';

class DevOutputPanel extends StatelessComponent {
  const DevOutputPanel({
    required this.outputLines,
    required this.scrollController,
    this.showEmptyState = true,
    super.key,
  });

  final List<DevOutputLine> outputLines;
  final ScrollController scrollController;
  final bool showEmptyState;

  @override
  Component build(BuildContext context) {
    if (outputLines.isEmpty) {
      if (!showEmptyState) {
        return Container(decoration: BoxDecoration(color: DevTheme.bg));
      }
      return const DevEmptyState(
        title: 'Ready',
        message:
            'Pick an action from the sidebar, or press Enter or Space to run the highlighted command.',
      );
    }

    return Container(
      decoration: BoxDecoration(color: DevTheme.bg),
      padding: EdgeInsets.symmetric(horizontal: 2, vertical: 0.5),
      child: ListView(
        controller: scrollController,
        children: [
          for (var i = 0; i < outputLines.length; i++)
            Text(
              outputLines[i].text,
              overflow: TextOverflow.ellipsis,
              style: devOutputLineStyle(outputLines[i]),
            ),
        ],
      ),
    );
  }
}
