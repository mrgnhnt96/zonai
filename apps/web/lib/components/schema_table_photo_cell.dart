import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:zonai_schema/payloads.dart';

import '../api/api_client.dart';
import '../constants/spacing.dart';
import '../constants/theme.dart';
import '../utils/photo_edit_value.dart';

enum SchemaTablePhotoSize { compact, detail }

/// Inline photo thumbnails for table rows and row detail.
class SchemaTablePhotoCell extends StatelessComponent {
  const SchemaTablePhotoCell({
    required this.rawValue,
    required this.shape,
    this.size = SchemaTablePhotoSize.compact,
    super.key,
  });

  final Object? rawValue;
  final ColumnShape shape;
  final SchemaTablePhotoSize size;

  @override
  Component build(BuildContext context) {
    final urls = photoUrlsFromCell(rawValue, shape, imageBaseUrl: revaliBaseUrl);
    if (urls.isEmpty) return .text('—');

    final sizeClass = switch (size) {
      SchemaTablePhotoSize.compact => 'schema-table-photo-cell--compact',
      SchemaTablePhotoSize.detail => 'schema-table-photo-cell--detail',
    };

    return div(classes: 'schema-table-photo-cell $sizeClass', [
      for (final url in urls)
        a(
          href: url,
          classes: 'schema-table-photo-cell__link',
          attributes: {
            'target': '_blank',
            'rel': 'noopener noreferrer',
            'aria-label': 'Open image in new tab',
          },
          events: size == SchemaTablePhotoSize.compact
              ? {
                  'click': (event) => event.stopPropagation(),
                }
              : const {},
          [
            img(src: url, attributes: {'alt': shape.name, 'loading': 'lazy'}),
          ],
        ),
    ]);
  }
}

@css
List<StyleRule> get schemaTablePhotoCellStyles => [
  css('.schema-table-photo-cell').styles(
    display: .flex,
    flexDirection: FlexDirection.row,
    flexWrap: FlexWrap.wrap,
    alignItems: .center,
    gap: Gap.all(ZonaiSpacing.s2),
  ),
  css('.schema-table-photo-cell__link').styles(
    display: .flex,
    alignItems: .center,
    justifyContent: .center,
    flex: Flex(grow: 0, shrink: 0),
    overflow: Overflow.hidden,
    radius: .all(Radius.circular(4.px)),
    border: Border.all(color: borderColor, width: 1.px),
    cursor: .pointer,
    raw: const {'line-height': '0'},
  ),
  css('.schema-table-photo-cell__link:hover').styles(
    border: Border.all(color: primaryColor, width: 1.px),
  ),
  css('.schema-table-photo-cell__link img').styles(
    display: .block,
    width: 100.percent,
    height: 100.percent,
    raw: const {'object-fit': 'contain', 'object-position': 'center'},
  ),
  css('.schema-table-photo-cell--compact .schema-table-photo-cell__link').styles(
    width: 28.px,
    height: 28.px,
  ),
  css('.schema-table-photo-cell--detail').styles(
    gap: Gap.all(ZonaiSpacing.s3),
  ),
  css('.schema-table-photo-cell--detail .schema-table-photo-cell__link').styles(
    width: 72.px,
    height: 72.px,
    radius: .all(Radius.circular(6.px)),
  ),
];
