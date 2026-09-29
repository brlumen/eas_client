import 'dart:convert';
import 'dart:typed_data';

import 'package:eas_client/eas_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

EasHttpClient _client({
  EasCredentials? credentials,
  String protocolVersion = '16.1',
  String deviceId = 'v140Device',
  String deviceType = 'SmartPhone',
  bool base64Query = true,
  http.Client? httpClient,
}) => EasHttpClient(
  server: 'mail.example.com',
  credentials: credentials ?? OAuthCredentials(accessToken: 'token'),
  protocolVersion: protocolVersion,
  deviceId: deviceId,
  deviceType: deviceType,
  useBase64QueryString: base64Query,
  httpClient: httpClient,
);

void main() {
  group('Base64 query (MS-ASHTTP 2.2.1.1.1.1)', () {
    test('matches the spec example', () {
      final c = _client(protocolVersion: '14.0');
      expect(
        c.buildBase64Query('Sync'),
        'jAAJBAp2MTQwRGV2aWNlAApTbWFydFBob25l',
      );
    });

    test('encodes policy key (uint32 LE) and User parameter', () {
      final c = _client(
        credentials: BasicCredentials(username: 'bob', password: 'pw'),
      )..policyKey = '3942919513';
      final bytes = base64.decode(c.buildBase64Query('Provision'));

      expect(bytes[0], 161); // protocol version
      expect(bytes[1], 20); // Provision
      expect(bytes.sublist(2, 4), [0x09, 0x04]); // locale en-US
      expect(bytes[4], 10);
      expect(ascii.decode(bytes.sublist(5, 15)), 'v140Device');
      expect(bytes[15], 4);
      final key = ByteData.sublistView(
        Uint8List.fromList(bytes),
        16,
        20,
      ).getUint32(0, Endian.little);
      expect(key, 3942919513);
      expect(bytes[20], 10);
      expect(ascii.decode(bytes.sublist(21, 31)), 'SmartPhone');
      expect(bytes.sublist(31), [8, 3, ...ascii.encode('bob')]);
    });

    test('non-numeric policy key is omitted', () {
      final c = _client()..policyKey = 'abc';
      final bytes = base64.decode(c.buildBase64Query('Sync'));
      expect(bytes[15], 0);
    });

    test('unknown command is rejected', () {
      expect(() => _client().buildBase64Query('Bogus'), throwsArgumentError);
    });

    test('deviceType longer than 255 chars is rejected', () {
      expect(() => _client(deviceType: 'A' * 256), throwsArgumentError);
      expect(
        () => _client(deviceType: 'A' * 256, base64Query: false),
        returnsNormally,
      );
    });

    Future<Uri> captureUri({
      required bool base64Query,
      String protocolVersion = '16.1',
    }) async {
      late Uri uri;
      final c = _client(
        base64Query: base64Query,
        protocolVersion: protocolVersion,
        httpClient: MockClient((req) async {
          uri = req.url;
          return http.Response('', 200);
        }),
      );
      await c.sendCommand('Sync', null);
      return uri;
    }

    test('sendCommand uses base64 query when enabled (HTTPS)', () async {
      final uri = await captureUri(base64Query: true);
      expect(uri.scheme, 'https');
      expect(uri.path, '/Microsoft-Server-ActiveSync');
      expect(uri.queryParameters.containsKey('Cmd'), isFalse);
      expect(base64.decode(uri.query)[1], 0);
    });

    test('plain text query by default', () async {
      final uri = await captureUri(base64Query: false);
      expect(uri.queryParameters['Cmd'], 'Sync');
    });

    test('falls back to plain text for 12.0', () async {
      final uri = await captureUri(base64Query: true, protocolVersion: '12.0');
      expect(uri.queryParameters['Cmd'], 'Sync');
    });
  });
}
