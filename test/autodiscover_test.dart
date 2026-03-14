import 'package:eas_client/eas_client.dart';
import 'package:test/test.dart';

void main() {
  late Autodiscover autodiscover;

  setUp(() {
    autodiscover = Autodiscover();
  });

  tearDown(() {
    autodiscover.dispose();
  });

  group('Autodiscover XML parsing', () {
    test('parses standard MobileSync response with Url', () {
      const xml = '''<?xml version="1.0" encoding="utf-8"?>
<Autodiscover xmlns="http://schemas.microsoft.com/exchange/autodiscover/responseschema/2006">
  <Response xmlns="http://schemas.microsoft.com/exchange/autodiscover/mobilesync/responseschema/2006">
    <Culture>en:us</Culture>
    <User>
      <DisplayName>John Doe</DisplayName>
      <EMailAddress>john@example.com</EMailAddress>
    </User>
    <Action>
      <Settings>
        <Server>
          <Type>MobileSync</Type>
          <Url>https://mail.example.com/Microsoft-Server-ActiveSync</Url>
          <Name>https://mail.example.com/Microsoft-Server-ActiveSync</Name>
        </Server>
      </Settings>
    </Action>
  </Response>
</Autodiscover>''';

      final result = autodiscover.parseResponse(xml);

      expect(result, isNotNull);
      expect(result!.server, equals('mail.example.com'));
      expect(result.url,
          equals('https://mail.example.com/Microsoft-Server-ActiveSync'));
      expect(result.displayName, equals('John Doe'));
    });

    test('parses response with Server element fallback', () {
      const xml = '''<?xml version="1.0" encoding="utf-8"?>
<Autodiscover>
  <Response>
    <Server>eas.company.org</Server>
  </Response>
</Autodiscover>''';

      final result = autodiscover.parseResponse(xml);

      expect(result, isNotNull);
      expect(result!.server, equals('eas.company.org'));
      expect(result.url,
          equals('https://eas.company.org/Microsoft-Server-ActiveSync'));
    });

    test('returns null for response without EAS URL', () {
      const xml = '''<?xml version="1.0" encoding="utf-8"?>
<Autodiscover>
  <Response>
    <Error>
      <ErrorCode>600</ErrorCode>
      <Message>Invalid Request</Message>
    </Error>
  </Response>
</Autodiscover>''';

      final result = autodiscover.parseResponse(xml);
      expect(result, isNull);
    });

    test('returns null for empty body', () {
      final result = autodiscover.parseResponse('');
      expect(result, isNull);
    });

    test('parses URL with query parameters', () {
      const xml = '''<Response>
  <Action>
    <Settings>
      <Server>
        <Type>MobileSync</Type>
        <Url>https://outlook.office365.com/Microsoft-Server-ActiveSync?Protocol=2</Url>
      </Server>
    </Settings>
  </Action>
</Response>''';

      final result = autodiscover.parseResponse(xml);

      expect(result, isNotNull);
      expect(result!.server, equals('outlook.office365.com'));
    });

    test('parses without DisplayName', () {
      const xml = '''<Response>
  <Action>
    <Settings>
      <Server>
        <Type>MobileSync</Type>
        <Url>https://mail.test.com/Microsoft-Server-ActiveSync</Url>
      </Server>
    </Settings>
  </Action>
</Response>''';

      final result = autodiscover.parseResponse(xml);

      expect(result, isNotNull);
      expect(result!.displayName, isNull);
      expect(result.server, equals('mail.test.com'));
    });
  });
}
