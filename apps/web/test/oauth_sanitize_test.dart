import 'package:test/test.dart';
import 'package:zonai_web/components/theme/oauth_sanitize.dart';

void main() {
  group('sanitizeInlineSvg', () {
    test('accepts a plain shape svg unchanged', () {
      const source = '<svg viewBox="0 0 24 24"><path d="M0 0h24v24H0z" fill="#123456"/></svg>';
      expect(sanitizeInlineSvg(source), isNotNull);
    });

    test('accepts nested groups, gradients, and text labels', () {
      const source =
          '<svg viewBox="0 0 24 24">'
          '<defs><linearGradient id="g"><stop offset="0" stop-color="#fff"/></linearGradient></defs>'
          '<g><title>Acme</title><circle cx="12" cy="12" r="10" fill="url(#g)"/></g>'
          '</svg>';
      expect(sanitizeInlineSvg(source), isNotNull);
    });

    test('rejects empty or blank input', () {
      expect(sanitizeInlineSvg(''), isNull);
      expect(sanitizeInlineSvg('   '), isNull);
    });

    test('rejects malformed xml', () {
      expect(sanitizeInlineSvg('<svg><path d="M0 0"></svg'), isNull);
    });

    test('rejects a non-svg root element', () {
      expect(sanitizeInlineSvg('<div><path d="M0 0"/></div>'), isNull);
    });

    test('rejects a script element anywhere in the tree', () {
      expect(sanitizeInlineSvg('<svg><script>alert(1)</script></svg>'), isNull);
      expect(sanitizeInlineSvg('<svg><g><script>alert(1)</script></g></svg>'), isNull);
    });

    test('rejects an onload/onclick event-handler attribute', () {
      expect(sanitizeInlineSvg('<svg onload="alert(1)"><path d="M0 0"/></svg>'), isNull);
      expect(sanitizeInlineSvg('<svg><path d="M0 0" onclick="alert(1)"/></svg>'), isNull);
    });

    test('rejects a javascript: URI hidden in an attribute value', () {
      expect(sanitizeInlineSvg('<svg><path d="M0 0" fill="javascript:alert(1)"/></svg>'), isNull);
    });

    test('rejects href/xlink:href on an otherwise-allowed element', () {
      expect(sanitizeInlineSvg('<svg><path d="M0 0" href="javascript:alert(1)"/></svg>'), isNull);
      expect(
        sanitizeInlineSvg('<svg xmlns:xlink="http://www.w3.org/1999/xlink"><path d="M0 0" xlink:href="#evil"/></svg>'),
        isNull,
      );
    });

    test('rejects a style attribute (CSS injection surface)', () {
      expect(sanitizeInlineSvg('<svg><path d="M0 0" style="fill:url(javascript:alert(1))"/></svg>'), isNull);
    });

    test('rejects foreignObject, image, and iframe elements', () {
      expect(sanitizeInlineSvg('<svg><foreignObject><p>hi</p></foreignObject></svg>'), isNull);
      expect(sanitizeInlineSvg('<svg><image href="https://evil.example/x.png"/></svg>'), isNull);
      expect(sanitizeInlineSvg('<svg><iframe src="https://evil.example"></iframe></svg>'), isNull);
    });

    test('rejects an attribute outside the allowlist', () {
      expect(sanitizeInlineSvg('<svg><path d="M0 0" data-evil="1"/></svg>'), isNull);
    });
  });
}
