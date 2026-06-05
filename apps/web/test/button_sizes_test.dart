import 'package:test/test.dart';
import 'package:zonai_web/constants/button_sizes.dart';

void main() {
  group('ZonaiButtonSizes', () {
    test('text size classes are stable', () {
      expect(ZonaiButtonSizes.textSizeClass(ZonaiButtonSize.md), 'z-btn--md');
      expect(ZonaiButtonSizes.textSizeClass(ZonaiButtonSize.sm), 'z-btn--sm');
      expect(ZonaiButtonSizes.textSizeClass(ZonaiButtonSize.xs), 'z-btn--xs');
      expect(ZonaiButtonSizes.textSizeClass(ZonaiButtonSize.xxs), 'z-btn--xxs');
    });

    test('icon size classes are stable', () {
      expect(ZonaiButtonSizes.iconSizeClass(ZonaiIconButtonSize.lg), 'z-icon-btn--lg');
      expect(ZonaiButtonSizes.iconSizeClass(ZonaiIconButtonSize.md), 'z-icon-btn--md');
      expect(ZonaiButtonSizes.iconSizeClass(ZonaiIconButtonSize.sm), 'z-icon-btn--sm');
      expect(ZonaiButtonSizes.iconSizeClass(ZonaiIconButtonSize.xs), 'z-icon-btn--xs');
      expect(ZonaiButtonSizes.iconSizeClass(ZonaiIconButtonSize.xxs), 'z-icon-btn--xxs');
    });

    test('text button classes include size and variant', () {
      expect(
        ZonaiButtonSizes.textButtonClasses(
          size: ZonaiButtonSize.sm,
          variantClass: 'z-btn--ghost',
        ),
        'z-btn z-btn--sm z-btn--ghost',
      );
    });

    test('ghost defaults to sm size', () {
      expect(
        ZonaiButtonSizes.defaultTextSizeForVariant('z-btn--ghost'),
        ZonaiButtonSize.sm,
      );
      expect(
        ZonaiButtonSizes.defaultTextSizeForVariant('z-btn--primary'),
        ZonaiButtonSize.md,
      );
    });
  });
}
