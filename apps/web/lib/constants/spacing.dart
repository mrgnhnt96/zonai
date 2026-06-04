import 'package:jaspr/dom.dart';

/// Central spacing scale for the Zonai web app.
///
/// Use these tokens for [Padding], [Margin], and [Gap] so layout rhythm stays
/// consistent across screens and components.
abstract final class ZonaiSpacing {
  ZonaiSpacing._();

  /// 0px
  static final s0 = 0.px;

  /// 2px
  static final s1 = 2.px;

  /// 3px — tight inset (e.g. segmented controls)
  static final s1_5 = 3.px;

  /// 4px
  static final s2 = 4.px;

  /// 5px — compact vertical inset
  static final s2_5 = 5.px;

  /// 6px
  static final s3 = 6.px;

  /// 8px
  static final s4 = 8.px;

  /// 9px — ghost button vertical padding
  static final s4_5 = 9.px;

  /// 10px
  static final s5 = 10.px;

  /// 11px — form control vertical padding
  static final s5_5 = 11.px;

  /// 12px
  static final s6 = 12.px;

  /// 14px — form control horizontal padding, section offsets
  static final s7 = 14.px;

  /// 16px
  static final s8 = 16.px;

  /// 18px — primary button horizontal padding
  static final s9 = 18.px;

  /// 20px
  static final s10 = 20.px;

  /// 24px
  static final s11 = 24.px;

  /// 26px — popover offset from trigger
  static final s11_5 = 26.px;

  /// 28px — large section spacing
  static final s12 = 28.px;

  /// 32px — page/section padding
  static final s13 = 32.px;

  /// 36px — auth card padding, select chevron inset
  static final s14 = 36.px;

  /// 40px — empty state panel padding
  static final s15 = 40.px;

  /// 72px — clearance above fixed selection bar
  static final selectionBar = 72.px;
}
