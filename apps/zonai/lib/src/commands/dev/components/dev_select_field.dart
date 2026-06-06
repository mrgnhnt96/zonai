import 'package:nocterm/nocterm.dart';

import 'dev_theme.dart';

class DevSelectField extends StatelessComponent {
  const DevSelectField({
    required this.label,
    required this.options,
    required this.selectedIndex,
    required this.focused,
    this.width = 42.0,
    this.footer,
    this.onTap,
    super.key,
  });

  final String label;
  final List<String> options;
  final int selectedIndex;
  final bool focused;
  final double width;
  final Component? footer;
  final VoidCallback? onTap;

  @override
  Component build(BuildContext context) {
    final value = options.isEmpty
        ? '(none available)'
        : options[selectedIndex.clamp(0, options.length - 1)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DevFieldLabel(label: label),
        DevInputBox(
          focused: focused,
          width: width,
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: options.isEmpty ? DevTheme.textDim : DevTheme.text,
                  ),
                ),
                if (focused && options.isNotEmpty)
                  Text('▾', style: TextStyle(color: DevTheme.accentBright)),
              ],
            ),
          ),
        ),
        if (footer != null) ...[SizedBox(height: 0.5), footer!],
      ],
    );
  }
}
