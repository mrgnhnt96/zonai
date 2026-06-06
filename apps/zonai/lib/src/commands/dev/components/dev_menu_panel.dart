import 'package:nocterm/nocterm.dart';

import '../../../utils/terminal_pointer.dart';

import 'dev_menu_item.dart';
import 'dev_theme.dart';

class _Spacer {
  const _Spacer();
}

class _MenuItemRow {
  const _MenuItemRow(this.menuIndex, this.item);
  final int menuIndex;
  final DevMenuItem item;
}

class DevMenuPanel extends StatefulComponent {
  const DevMenuPanel({
    required this.selectedIndex,
    required this.serverRunning,
    this.onItemTap,
    super.key,
  });

  final int selectedIndex;
  final bool serverRunning;
  final ValueChanged<int>? onItemTap;

  @override
  State<DevMenuPanel> createState() => _DevMenuPanelState();
}

class _DevMenuPanelState extends State<DevMenuPanel> {
  static const _rowHeight = 1.0;

  final _scrollController = ScrollController();
  late final List<Object> _rows;
  late final List<int> _menuItemRowIndices;
  int? _hoveredIndex;

  @override
  void initState() {
    super.initState();
    final built = _buildRows();
    _rows = built.$1;
    _menuItemRowIndices = built.$2;
    _scheduleScrollToSelected();
  }

  @override
  void didUpdateComponent(DevMenuPanel oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (component.selectedIndex != oldComponent.selectedIndex) {
      _scheduleScrollToSelected();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  (List<Object>, List<int>) _buildRows() {
    final rows = <Object>[];
    final menuItemRowIndices = List<int>.filled(devMenuItems.length, 0);
    String? currentGroup;

    for (var i = 0; i < devMenuItems.length; i++) {
      final item = devMenuItems[i];

      if (item.group != currentGroup) {
        if (currentGroup != null) rows.add(_Spacer());
        currentGroup = item.group;
        rows.add(item.group);
      }

      menuItemRowIndices[i] = rows.length;
      rows.add(_MenuItemRow(i, item));
    }

    return (rows, menuItemRowIndices);
  }

  void _scheduleScrollToSelected() {
    TerminalBinding.instance.addPostFrameCallback(_scrollToSelected);
  }

  void _scrollToSelected(Duration _) {
    if (!mounted) return;

    final rowIndex = _menuItemRowIndices[component.selectedIndex];
    final itemTop = rowIndex * _rowHeight;
    final itemBottom = itemTop + _rowHeight;

    final viewportTop = _scrollController.offset;
    final viewportBottom = viewportTop + _scrollController.viewportDimension;

    if (itemTop < viewportTop) {
      _scrollController.jumpTo(itemTop);
    } else if (itemBottom > viewportBottom) {
      _scrollController.jumpTo(
        (itemBottom - _scrollController.viewportDimension).clamp(
          _scrollController.minScrollExtent,
          _scrollController.maxScrollExtent,
        ),
      );
    }
  }

  @override
  Component build(BuildContext context) {
    return SizedBox(
      width: 34,
      child: Container(
        decoration: BoxDecoration(
          color: DevTheme.surface,
          border: BoxBorder(
            right: BorderSide(color: DevTheme.border, width: 1),
          ),
        ),
        child: Column(
          children: [
            const DevSidebarTitle(),
            SizedBox(height: 1),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                itemExtent: _rowHeight,
                itemCount: _rows.length,
                itemBuilder: (context, index) => _buildRow(_rows[index]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Component _buildRow(Object row) {
    if (row is _Spacer) {
      return Container();
    }

    if (row is String) {
      return Padding(
        padding: EdgeInsets.only(left: 2),
        child: Text(
          _formatGroup(row),
          style: TextStyle(
            color: DevTheme.textMuted,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    if (row is _MenuItemRow) {
      return _buildMenuItem(row.menuIndex, row.item);
    }

    return Container();
  }

  String _formatGroup(String group) {
    if (group.isEmpty) return group;
    return '${group[0]}${group.substring(1).toLowerCase()}';
  }

  String _labelFor(DevMenuItem item) {
    if (item.group == 'SERVER' && item.key == 's') {
      return component.serverRunning ? 'Stop server' : 'Start server';
    }
    return item.label;
  }

  Component _buildMenuItem(int menuIndex, DevMenuItem item) {
    final isSelected = menuIndex == component.selectedIndex;
    final isHovered = _hoveredIndex == menuIndex;
    final pointer = isSelected ? '›' : ' ';
    final label = _labelFor(item);

    return MouseRegion(
      onEnter: (_) {
        TerminalPointer.push(TerminalPointerShape.pointer);
        if (_hoveredIndex == menuIndex) return;
        setState(() => _hoveredIndex = menuIndex);
      },
      onExit: (_) {
        TerminalPointer.pop();
        if (_hoveredIndex != menuIndex) return;
        setState(() => _hoveredIndex = null);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: component.onItemTap == null
            ? null
            : () => component.onItemTap!(menuIndex),
        child: Row(
          children: [
            Container(
              width: isSelected ? 1 : 0.5,
              decoration: BoxDecoration(
                color: isSelected ? DevTheme.accent : DevTheme.borderSubtle,
              ),
            ),
            Expanded(
              child: Container(
                decoration: isSelected
                    ? BoxDecoration(color: DevTheme.selection)
                    : isHovered
                    ? BoxDecoration(color: DevTheme.surfaceHover)
                    : null,
                padding: EdgeInsets.only(left: 1, right: 1),
                child: RichText(
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    style: TextStyle(
                      color: isSelected || isHovered
                          ? DevTheme.text
                          : DevTheme.textMuted,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                    children: [
                      TextSpan(text: '$pointer '),
                      TextSpan(
                        text: item.key,
                        style: TextStyle(
                          color: isSelected || isHovered
                              ? DevTheme.textDim
                              : DevTheme.textFaint,
                          fontWeight: isSelected || isHovered
                              ? FontWeight.normal
                              : FontWeight.dim,
                        ),
                      ),
                      TextSpan(text: '  $label'),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
