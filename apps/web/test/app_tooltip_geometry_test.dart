import 'package:test/test.dart';
import 'package:zonai_web/providers/app_tooltip_provider.dart';
import 'package:zonai_web/utils/app_tooltip_geometry.dart';

/// The dashboard's Sessions figures: a `belowLeft` tip on a small tile, with
/// a tooltip wide enough to reach the viewport edge from most of the row.
({double top, double left, AppTooltipPlacement placement}) _place({
  AppTooltipPlacement placement = AppTooltipPlacement.belowLeft,
  double anchorTop = 100,
  double anchorLeft = 100,
  double anchorWidth = 160,
  double anchorHeight = 60,
  double tooltipWidth = 384,
  double tooltipHeight = 60,
  double viewportWidth = 1280,
  double viewportHeight = 800,
}) => resolveAppTooltipPosition(
  placement: placement,
  anchorTop: anchorTop,
  anchorLeft: anchorLeft,
  anchorWidth: anchorWidth,
  anchorHeight: anchorHeight,
  tooltipWidth: tooltipWidth,
  tooltipHeight: tooltipHeight,
  viewportWidth: viewportWidth,
  viewportHeight: viewportHeight,
);

/// The left edge the browser will paint, once `.app-tooltip`'s transform has
/// pulled the box back by a fraction of its own width.
double _paintedLeft(({double top, double left, AppTooltipPlacement placement}) p, double width) =>
    switch (p.placement) {
      AppTooltipPlacement.belowCenter || AppTooltipPlacement.aboveCenter => p.left - width / 2,
      _ => p.left,
    };

double _paintedTop(({double top, double left, AppTooltipPlacement placement}) p, double height) =>
    switch (p.placement) {
      AppTooltipPlacement.aboveCenter || AppTooltipPlacement.aboveLeft => p.top - height,
      AppTooltipPlacement.rightCenter => p.top - height / 2,
      _ => p.top,
    };

void main() {
  group('resolveAppTooltipPosition', () {
    test('leaves a tooltip with room on all sides exactly where it was asked for', () {
      final p = _place();

      expect(p.placement, AppTooltipPlacement.belowLeft);
      expect(p.top, 160 + appTooltipGap);
      expect(p.left, 100);
    });

    test('an anchor near the right edge no longer pushes the tooltip off-screen', () {
      // The Sessions panel's third figure: 384px of tip anchored 120px from
      // the right edge. Before the clamp this ran to x = 1544 on a 1280px
      // window and the text was simply unreadable.
      final p = _place(anchorLeft: 1160, anchorWidth: 120);

      expect(_paintedLeft(p, 384), 1280 - appTooltipMargin - 384);
      expect(_paintedLeft(p, 384) + 384, lessThanOrEqualTo(1280 - appTooltipMargin));
    });

    test('an anchor near the left edge is pushed back in, not out', () {
      final p = _place(placement: AppTooltipPlacement.belowCenter, anchorLeft: 4, anchorWidth: 40);

      expect(_paintedLeft(p, 384), appTooltipMargin);
    });

    test('a tooltip wider than the viewport pins to the near margin instead of overshooting', () {
      final p = _place(anchorLeft: 900, tooltipWidth: 1400, viewportWidth: 1280);

      expect(_paintedLeft(p, 1400), appTooltipMargin);
    });

    test('flips above when the anchor sits too low for the measured height', () {
      final p = _place(placement: AppTooltipPlacement.belowCenter, anchorTop: 720, anchorHeight: 40);

      expect(p.placement, AppTooltipPlacement.aboveCenter);
      expect(_paintedTop(p, 60), 720 - appTooltipGap - 60);
    });

    test('a measured height that clears the bottom does not flip', () {
      // The old 44px constant flipped anything within 44px of the bottom.
      // A 24px tooltip 30px clear of the edge has room and should stay put.
      final p = _place(placement: AppTooltipPlacement.belowCenter, anchorTop: 700, anchorHeight: 56, tooltipHeight: 24);

      expect(p.placement, AppTooltipPlacement.belowCenter);
    });

    test('clamps rather than flips when neither side has room', () {
      final p = _place(
        placement: AppTooltipPlacement.belowLeft,
        anchorTop: 20,
        anchorHeight: 40,
        tooltipHeight: 700,
        viewportHeight: 760,
      );

      expect(p.placement, AppTooltipPlacement.belowLeft);
      // Pulled UP off the anchor so the bottom edge clears the margin, rather
      // than flipped to a side with even less room.
      expect(_paintedTop(p, 700), 760 - appTooltipMargin - 700);
      expect(_paintedTop(p, 700), lessThan(60 + appTooltipGap));
    });

    test('a rightCenter tooltip is centred on the anchor and kept inside the top edge', () {
      final p = _place(placement: AppTooltipPlacement.rightCenter, anchorTop: 0, anchorHeight: 20, tooltipHeight: 60);

      expect(p.placement, AppTooltipPlacement.rightCenter);
      expect(_paintedTop(p, 60), appTooltipMargin);
    });
  });
}
