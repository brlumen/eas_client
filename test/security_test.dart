import 'dart:typed_data';

import 'package:eas_client/eas_client.dart';
import 'package:test/test.dart';

void main() {
  group('Autodiscover security', () {
    late Autodiscover autodiscover;

    setUp(() {
      autodiscover = Autodiscover();
    });

    tearDown(() {
      autodiscover.dispose();
    });

    test('XML special characters are escaped in request', () {
      // Access _buildRequest indirectly through parseResponse
      // to verify the escaping logic works correctly
      expect(Autodiscover.escapeXmlForTest('<script>'), equals('&lt;script&gt;'));
      expect(Autodiscover.escapeXmlForTest('a&b'), equals('a&amp;b'));
      expect(Autodiscover.escapeXmlForTest('"quoted"'), equals('&quot;quoted&quot;'));
      expect(Autodiscover.escapeXmlForTest("it's"), equals("it&apos;s"));
    });

    test('rejects HTTP URL in Autodiscover response', () {
      const xml = '''<Response>
  <Action>
    <Settings>
      <Server>
        <Type>MobileSync</Type>
        <Url>http://mail.example.com/Microsoft-Server-ActiveSync</Url>
      </Server>
    </Settings>
  </Action>
</Response>''';

      final result = autodiscover.parseResponse(xml);
      expect(result, isNull, reason: 'HTTP URLs must be rejected');
    });

    test('accepts HTTPS URL in Autodiscover response', () {
      const xml = '''<Response>
  <Action>
    <Settings>
      <Server>
        <Type>MobileSync</Type>
        <Url>https://mail.example.com/Microsoft-Server-ActiveSync</Url>
      </Server>
    </Settings>
  </Action>
</Response>''';

      final result = autodiscover.parseResponse(xml);
      expect(result, isNotNull);
      expect(result!.server, equals('mail.example.com'));
    });

    test('discover throws on invalid email format', () {
      final credentials = BasicCredentials(
        username: 'test',
        password: 'pass',
      );

      expect(
        () => autodiscover.discover(
          email: 'noemail',
          credentials: credentials,
        ),
        throwsA(isA<AutodiscoverException>()),
      );
    });

    test('discover throws on empty domain', () {
      final credentials = BasicCredentials(
        username: 'test',
        password: 'pass',
      );

      expect(
        () => autodiscover.discover(
          email: 'user@',
          credentials: credentials,
        ),
        throwsA(isA<AutodiscoverException>()),
      );
    });
  });

  group('WBXML security', () {
    test('rejects opaque data exceeding size limit', () {
      final decoder = WbxmlDecoder(maxOpaqueSize: 10);

      // Build a minimal WBXML with opaque data larger than limit
      // Header: version=0x03, publicId=0x01, charset=0x6A, strtbl=0
      // Body: SWITCH_PAGE 0, tag 0x05 (Sync) with content,
      //       OPAQUE with length=100
      final builder = BytesBuilder();
      builder.addByte(0x03); // version
      builder.addByte(0x01); // publicId
      builder.addByte(0x6A); // charset UTF-8
      builder.addByte(0x00); // string table length

      builder.addByte(0x00); // SWITCH_PAGE
      builder.addByte(0x00); // page 0 (AirSync)

      builder.addByte(0x05 | 0x40); // tag=Sync (0x05) + has content
      builder.addByte(0xC3); // OPAQUE token
      builder.addByte(100); // length = 100 (exceeds maxOpaqueSize=10)
      // We don't need the actual data — decoder should throw before reading

      // Pad with enough bytes
      builder.add(Uint8List(100));
      builder.addByte(0x01); // END

      expect(
        () => decoder.decode(builder.toBytes()),
        throwsA(isA<WbxmlException>()),
      );
    });

    test('rejects excessive nesting depth', () {
      final decoder = WbxmlDecoder(maxDepth: 3);

      // Build WBXML with 5 levels of nesting
      final builder = BytesBuilder();
      builder.addByte(0x03); // version
      builder.addByte(0x01); // publicId
      builder.addByte(0x6A); // charset
      builder.addByte(0x00); // string table length

      builder.addByte(0x00); // SWITCH_PAGE
      builder.addByte(0x00); // page 0 (AirSync)

      // Nest 5 elements: Sync > Collections > Collection > Commands > Add
      // Sync (0x05), Collections (0x06), Collection (0x07),
      // Commands (0x12), Add (0x08) — all with content bit
      for (final tag in [0x05, 0x06, 0x07, 0x12, 0x08]) {
        builder.addByte(tag | 0x40); // tag + has content
      }

      // Close all 5
      for (var i = 0; i < 5; i++) {
        builder.addByte(0x01); // END
      }

      expect(
        () => decoder.decode(builder.toBytes()),
        throwsA(isA<WbxmlException>()),
      );
    });

    test('normal nesting depth is allowed', () {
      final decoder = WbxmlDecoder(maxDepth: 50);
      final encoder = WbxmlEncoder();

      // 3 levels: Sync > Collections > SyncKey (text)
      final doc = WbxmlDocument(
        root: WbxmlElement(
          namespace: 'AirSync',
          tag: 'Sync',
          codePageIndex: 0,
          children: [
            WbxmlElement(
              namespace: 'AirSync',
              tag: 'Collections',
              codePageIndex: 0,
              children: [
                WbxmlElement.withText(
                  namespace: 'AirSync',
                  tag: 'SyncKey',
                  text: '0',
                  codePageIndex: 0,
                ),
              ],
            ),
          ],
        ),
      );

      final bytes = encoder.encode(doc);
      final decoded = decoder.decode(bytes);
      expect(decoded.root.tag, equals('Sync'));
    });
  });

  group('AutodiscoverException', () {
    test('toString does not leak URLs', () {
      final exception = AutodiscoverException(
        'Discovery failed',
        triedUrls: [
          'https://internal.corp.example.com/autodiscover/autodiscover.xml',
          'https://autodiscover.corp.example.com/autodiscover/autodiscover.xml',
        ],
      );

      final str = exception.toString();
      expect(str, equals('AutodiscoverException: Discovery failed'));
      expect(str, isNot(contains('internal.corp')));
      expect(str, isNot(contains('autodiscover.corp')));
    });

    test('triedUrls still accessible for debugging', () {
      final exception = AutodiscoverException(
        'fail',
        triedUrls: ['https://a.com', 'https://b.com'],
      );

      expect(exception.triedUrls, hasLength(2));
    });

    test('toString does not leak email (PII)', () {
      final exception = AutodiscoverException(
        'Could not discover EAS settings',
        email: 'secret.user@corp.example.com',
      );

      final str = exception.toString();
      expect(str, isNot(contains('secret.user')));
      expect(str, isNot(contains('corp.example.com')));
      expect(exception.email, equals('secret.user@corp.example.com'));
    });
  });
}
