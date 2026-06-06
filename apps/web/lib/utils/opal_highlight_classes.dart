import 'package:opal/opal.dart';

/// Maps an [opal] token tag list to a CSS class for preview syntax coloring.
String? opalTokenCssClass(List<Tag> tags) {
  if (tags.contains(Tags.whitespace)) return 'syntax-hl-ws';
  if (tags.contains(Tags.nullLiteral)) return 'syntax-hl-null';
  if (tags.contains(Tags.trueLiteral) || tags.contains(Tags.falseLiteral) || tags.contains(Tags.booleanLiteral)) {
    return 'syntax-hl-bool';
  }
  if (tags.contains(Tags.numberLiteral) || tags.contains(Tags.integerLiteral) || tags.contains(Tags.floatLiteral)) {
    return 'syntax-hl-number';
  }
  if (tags.contains(Tags.property)) return 'syntax-hl-key';
  if (tags.contains(Tags.comment) ||
      tags.contains(Tags.lineComment) ||
      tags.contains(Tags.blockComment) ||
      tags.contains(Tags.docComment)) {
    return 'syntax-hl-comment';
  }
  if (tags.contains(Tags.keyword) ||
      tags.contains(Tags.declarationKeyword) ||
      tags.contains(Tags.controlKeyword) ||
      tags.contains(Tags.modifierKeyword)) {
    return 'syntax-hl-keyword';
  }
  if (tags.contains(Tags.annotation)) return 'syntax-hl-annotation';
  if (tags.contains(Tags.builtInType) || tags.contains(Tags.type)) return 'syntax-hl-type';
  if (tags.contains(Tags.function) || tags.contains(Tags.constructor)) return 'syntax-hl-call';
  if (tags.contains(Tags.stringLiteral) ||
      tags.contains(Tags.stringContent) ||
      tags.contains(Tags.quotedString) ||
      tags.contains(Tags.singleQuoteString) ||
      tags.contains(Tags.doubleQuoteString) ||
      tags.contains(Tags.tripleQuoteString) ||
      tags.contains(Tags.characterLiteral)) {
    return 'syntax-hl-string';
  }
  if (tags.contains(Tags.operator) || tags.contains(Tags.customOperator)) {
    return 'syntax-hl-operator';
  }
  if (tags.contains(Tags.punctuation) || tags.contains(Tags.separator) || tags.contains(Tags.accessor)) {
    return 'syntax-hl-punct';
  }
  return null;
}
