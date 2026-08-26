import 'dart:math' as math;

import '../providers/app_tooltip_provider.dart';

/// Space between the tooltip and the anchor it describes.
const appTooltipGap = 6.0;

/// The closest the tooltip is allowed to get to a viewport edge.
///
/// `.app-tooltip`'s `max-width` subtracts two of these from `100vw`, so the
/// box is always narrow enough for [resolveAppTooltipPosition] to seat it
/// between both margins -- the clamp is never asked for the impossible.
const appTooltipMargin = 8.0;

/// Where a tooltip lands, given the anchor, its own measured box and the
/// viewport.
///
/// Pure on purpose: the DOM supplies the four rects and nothing else, so the
/// edge cases that used to need a browser to see -- an anchor by the bottom
/// of the window, a long tip on an anchor hard against the right edge -- are
/// ordinary unit tests.
///
/// [top] and [left] are an ANCHOR POINT rather than the tooltip's corner: the
/// `transform` on `.app-tooltip` pulls the box back by a fraction of its own
/// size afterwards, and this returns the point that makes that transform land
/// where it should.
({double top, double left, AppTooltipPlacement placement}) resolveAppTooltipPosition({
  required AppTooltipPlacement placement,
  required double anchorTop,
  required double anchorLeft,
  required double anchorWidth,
  required double anchorHeight,
  required double tooltipWidth,
  required double tooltipHeight,
  required double viewportWidth,
  required double viewportHeight,
}) {
  final anchorBottom = anchorTop + anchorHeight;
  final anchorRight = anchorLeft + anchorWidth;

  // A `below*` tooltip on an anchor near the bottom of the window renders past
  // the bottom edge. It is `position: fixed`, so no ancestor clips it and
  // nothing scrolls it back into view -- it is simply not there. The last
  // actions in the row detail panel sit exactly that low.
  //
  // Flipping is only an improvement when the space above is space the tooltip
  // actually fits in. When neither side fits, the clamp below is what saves
  // it, and clamping a `below*` keeps the tooltip on the side the caller
  // asked for.
  final fitsBelow = anchorBottom + appTooltipGap + tooltipHeight <= viewportHeight - appTooltipMargin;
  final fitsAbove = anchorTop - appTooltipGap - tooltipHeight >= appTooltipMargin;
  final flip = !fitsBelow && fitsAbove;

  final resolved = switch (placement) {
    AppTooltipPlacement.belowCenter when flip => AppTooltipPlacement.aboveCenter,
    AppTooltipPlacement.belowLeft when flip => AppTooltipPlacement.aboveLeft,
    _ => placement,
  };

  // The `above*` pair anchors at the anchor's TOP and is pulled up by its own
  // height in CSS (`translateY(-100%)`).
  final (top, left) = switch (resolved) {
    AppTooltipPlacement.belowCenter => (anchorBottom + appTooltipGap, anchorLeft + anchorWidth / 2),
    AppTooltipPlacement.belowLeft => (anchorBottom + appTooltipGap, anchorLeft),
    AppTooltipPlacement.aboveCenter => (anchorTop - appTooltipGap, anchorLeft + anchorWidth / 2),
    AppTooltipPlacement.aboveLeft => (anchorTop - appTooltipGap, anchorLeft),
    AppTooltipPlacement.rightCenter => (anchorTop + anchorHeight / 2, anchorRight + appTooltipGap + 2),
  };

  // Work out where the transform lands the real edge, clamp THAT into the
  // viewport, then hand the same shift back to the anchor point -- the
  // transform reproduces it exactly.
  final leftEdge = switch (resolved) {
    AppTooltipPlacement.belowCenter || AppTooltipPlacement.aboveCenter => left - tooltipWidth / 2,
    _ => left,
  };
  final topEdge = switch (resolved) {
    AppTooltipPlacement.aboveCenter || AppTooltipPlacement.aboveLeft => top - tooltipHeight,
    AppTooltipPlacement.rightCenter => top - tooltipHeight / 2,
    _ => top,
  };

  return (
    top: top + (_clampEdge(topEdge, tooltipHeight, viewportHeight) - topEdge),
    left: left + (_clampEdge(leftEdge, tooltipWidth, viewportWidth) - leftEdge),
    placement: resolved,
  );
}

/// Keeps [edge] inside the viewport, and pins it to the near margin when the
/// tooltip is wider (or taller) than the space it has -- rather than shoving
/// it off the other side, which is what a bare `clamp` does once the low bound
/// crosses the high one.
double _clampEdge(double edge, double extent, double viewport) {
  final limit = math.max(appTooltipMargin, viewport - appTooltipMargin - extent);
  return edge.clamp(appTooltipMargin, limit).toDouble();
}
