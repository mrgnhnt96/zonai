import 'package:jaspr/dom.dart';

import 'spacing.dart';

/// Standard text-button sizes for the Zonai web app.
enum ZonaiButtonSize {
  /// Default actions — primary forms, dialogs, footers.
  md,

  /// Compact actions — ghost buttons, chips, presets.
  sm,

  /// Dense toolbars — operator toggles, datetime footers, segments.
  xs,

  /// Tight operator chips — search filter operators.
  xxs,
}

/// Standard square icon-button sizes for the Zonai web app.
enum ZonaiIconButtonSize {
  /// Mobile nav, prominent toolbar actions.
  lg,

  /// Sidebar rail items, table toolbar toggles.
  md,

  /// Panel close buttons, row remove controls.
  sm,

  /// Inline icon actions — selection bar, sidebar collapse, toast dismiss.
  xs,

  /// Micro inline actions — foreign-key detail affordance.
  xxs,
}

/// Visual variants for [ZonaiIconButton].
enum ZonaiIconButtonVariant {
  /// Bordered surface button.
  bordered,

  /// Transparent background, no border.
  ghost,
}

/// Central button sizing tokens and class-name helpers.
abstract final class ZonaiButtonSizes {
  ZonaiButtonSizes._();

  static const textBtn = 'z-btn';
  static const iconBtn = 'z-icon-btn';

  static String textSizeClass(ZonaiButtonSize size) => 'z-btn--${size.name}';

  static String iconSizeClass(ZonaiIconButtonSize size) => 'z-icon-btn--${size.name}';

  static String iconVariantClass(ZonaiIconButtonVariant variant) => switch (variant) {
    ZonaiIconButtonVariant.bordered => 'z-icon-btn--bordered',
    ZonaiIconButtonVariant.ghost => 'z-icon-btn--ghost',
  };

  static String textButtonClasses({
    required ZonaiButtonSize size,
    required String variantClass,
    bool fullWidth = false,
  }) {
    return [
      textBtn,
      textSizeClass(size),
      variantClass,
      if (fullWidth) 'z-btn--full',
    ].join(' ');
  }

  static String iconButtonClasses({
    required ZonaiIconButtonSize size,
    ZonaiIconButtonVariant variant = ZonaiIconButtonVariant.bordered,
    String? extra,
  }) {
    return [
      iconBtn,
      iconSizeClass(size),
      iconVariantClass(variant),
      if (extra != null && extra.isNotEmpty) extra,
    ].join(' ');
  }

  static ZonaiButtonSize defaultTextSizeForVariant(String variantClass) {
    return variantClass.contains('ghost') ? ZonaiButtonSize.sm : ZonaiButtonSize.md;
  }

  static Padding textPadding(ZonaiButtonSize size) => .symmetric(
    horizontal: textPaddingHorizontal(size),
    vertical: textPaddingVertical(size),
  );

  static textPaddingHorizontal(ZonaiButtonSize size) => switch (size) {
    ZonaiButtonSize.md => ZonaiSpacing.s9,
    ZonaiButtonSize.sm => ZonaiSpacing.s7,
    ZonaiButtonSize.xs => ZonaiSpacing.s5,
    ZonaiButtonSize.xxs => ZonaiSpacing.s4,
  };

  static textPaddingVertical(ZonaiButtonSize size) => switch (size) {
    ZonaiButtonSize.md => ZonaiSpacing.s5_5,
    ZonaiButtonSize.sm => ZonaiSpacing.s4_5,
    ZonaiButtonSize.xs => ZonaiSpacing.s3,
    ZonaiButtonSize.xxs => ZonaiSpacing.s2,
  };

  static textFontSize(ZonaiButtonSize size) => switch (size) {
    ZonaiButtonSize.md => 0.9375.rem,
    ZonaiButtonSize.sm => 0.8125.rem,
    ZonaiButtonSize.xs => 0.75.rem,
    ZonaiButtonSize.xxs => 0.75.rem,
  };

  static textRadius(ZonaiButtonSize size) => switch (size) {
    ZonaiButtonSize.md => 10.px,
    ZonaiButtonSize.sm => 8.px,
    ZonaiButtonSize.xs => 6.px,
    ZonaiButtonSize.xxs => 6.px,
  };

  static iconDimension(ZonaiIconButtonSize size) => switch (size) {
    ZonaiIconButtonSize.lg => 40.px,
    ZonaiIconButtonSize.md => 36.px,
    ZonaiIconButtonSize.sm => 32.px,
    ZonaiIconButtonSize.xs => 28.px,
    ZonaiIconButtonSize.xxs => 24.px,
  };

  static iconFontSize(ZonaiIconButtonSize size) => switch (size) {
    ZonaiIconButtonSize.lg => 1.25.rem,
    ZonaiIconButtonSize.md => 1.rem,
    ZonaiIconButtonSize.sm => 1.rem,
    ZonaiIconButtonSize.xs => 1.125.rem,
    ZonaiIconButtonSize.xxs => 0.875.rem,
  };

  static iconRadius(ZonaiIconButtonSize size) => switch (size) {
    ZonaiIconButtonSize.lg => 8.px,
    ZonaiIconButtonSize.md => 8.px,
    ZonaiIconButtonSize.sm => 8.px,
    ZonaiIconButtonSize.xs => 6.px,
    ZonaiIconButtonSize.xxs => 5.px,
  };
}
