import 'package:xml/xml.dart';

/// Element names a developer-supplied `iconSvg` may use.
///
/// Deliberately small: no `script`, `style`, `foreignObject`, `image`, `use`,
/// `iframe`, or `a` — every one of those is either a known SVG script vector
/// or a way to pull in something other than shape/color data. `title`/`desc`
/// are kept for accessibility text.
const _allowedElements = {
  'svg',
  'g',
  'path',
  'circle',
  'rect',
  'ellipse',
  'line',
  'polyline',
  'polygon',
  'defs',
  'lineargradient',
  'radialgradient',
  'stop',
  'clippath',
  'mask',
  'title',
  'desc',
};

/// Attributes allowed anywhere in an `iconSvg`.
///
/// No `href`/`xlink:href` (external or `javascript:` references) and no
/// `style` (CSS `url()`/`expression()` injection) — presentation must go
/// through the explicit attributes below instead.
const _allowedAttributes = {
  'id',
  'class',
  'viewbox',
  'width',
  'height',
  'xmlns',
  'fill',
  'fill-rule',
  'fill-opacity',
  'stroke',
  'stroke-width',
  'stroke-linecap',
  'stroke-linejoin',
  'stroke-dasharray',
  'stroke-opacity',
  'opacity',
  'd',
  'cx',
  'cy',
  'r',
  'rx',
  'ry',
  'x',
  'y',
  'x1',
  'y1',
  'x2',
  'y2',
  'points',
  'offset',
  'stop-color',
  'stop-opacity',
  'gradientunits',
  'gradienttransform',
  'transform',
  'clip-path',
  'clip-rule',
  'mask',
};

/// Validates a developer-authored `iconSvg` string against a strict
/// element/attribute allowlist and returns it unchanged if it passes, or
/// `null` if it doesn't.
///
/// This is an accept-or-reject gate, not a stripper: partial stripping of a
/// hostile input is easy to get subtly wrong (an attribute allowed on one
/// element but not sanitized on another, a nesting case missed), so anything
/// that isn't entirely built from the allowlist below is rejected outright
/// and the caller falls through to the next icon rung instead of rendering
/// it. [OAuthProviderIcon] never puts an unvalidated string in the DOM.
String? sanitizeInlineSvg(String source) {
  final trimmed = source.trim();
  if (trimmed.isEmpty) return null;

  final XmlDocument document;
  try {
    document = XmlDocument.parse(trimmed);
  } on XmlException {
    return null;
  }

  if (document.children.whereType<XmlDoctype>().isNotEmpty) return null;

  final XmlElement root;
  try {
    root = document.rootElement;
  } on StateError {
    return null;
  }

  if (root.name.local.toLowerCase() != 'svg') return null;
  if (!_isSafe(root)) return null;

  return root.toXmlString();
}

bool _isSafe(XmlElement element) {
  if (!_allowedElements.contains(element.name.local.toLowerCase())) {
    return false;
  }

  for (final attribute in element.attributes) {
    final name = attribute.name.local.toLowerCase();
    if (name.startsWith('on')) return false;
    if (name == 'href') return false;
    if (name == 'style') return false;
    if (!_allowedAttributes.contains(name)) return false;

    final value = attribute.value.toLowerCase();
    if (value.contains('javascript:')) return false;
    if (value.contains('data:text/html')) return false;
  }

  for (final child in element.childElements) {
    if (!_isSafe(child)) return false;
  }

  return true;
}
