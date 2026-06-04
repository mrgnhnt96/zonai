import 'package:jaspr_riverpod/jaspr_riverpod.dart';

import 'table_focus_provider.dart';

enum AppTooltipPlacement {
  belowCenter,
  belowLeft,
  rightCenter,
}

final class AppTooltipState {
  const AppTooltipState({
    this.text,
    this.top = 0,
    this.left = 0,
    this.placement = AppTooltipPlacement.belowCenter,
  });

  final String? text;
  final double top;
  final double left;
  final AppTooltipPlacement placement;
}

final appTooltipProvider = NotifierProvider<AppTooltipNotifier, AppTooltipState>(
  AppTooltipNotifier.new,
);

class AppTooltipNotifier extends Notifier<AppTooltipState> {
  @override
  AppTooltipState build() {
    ref.watch(tableFocusProvider);
    return const AppTooltipState();
  }

  void show({
    required String text,
    required double top,
    required double left,
    AppTooltipPlacement placement = AppTooltipPlacement.belowCenter,
  }) {
    state = AppTooltipState(text: text, top: top, left: left, placement: placement);
  }

  void hide() {
    if (state.text != null) {
      state = const AppTooltipState();
    }
  }
}
