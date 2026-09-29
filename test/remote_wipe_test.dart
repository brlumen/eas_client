import 'package:eas_client/eas_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

WbxmlElement _prov(String tag, {String? text, List<WbxmlElement>? children}) =>
    WbxmlElement(
      namespace: 'Provision',
      tag: tag,
      codePageIndex: 14,
      text: text,
      children: children,
    );

WbxmlDocument _response(List<WbxmlElement> extra) => WbxmlDocument(
  root: _prov(
    'Provision',
    children: [
      _prov('Status', text: '1'),
      ...extra,
    ],
  ),
);

void main() {
  final encoder = WbxmlEncoder();
  final decoder = WbxmlDecoder();
  final provision = ProvisionCommand(policyAckStatus: PolicyAckStatus.success);

  group('Provision remote wipe parsing', () {
    test('RemoteWipe → full', () {
      final r = provision.parseResponse(_response([_prov('RemoteWipe')]));
      expect(r.remoteWipe, RemoteWipeType.full);
    });

    test('AccountOnlyRemoteWipe → accountOnly (WBXML round-trip)', () {
      final bytes = encoder.encode(_response([_prov('AccountOnlyRemoteWipe')]));
      final r = provision.parseResponse(decoder.decode(bytes));
      expect(r.remoteWipe, RemoteWipeType.accountOnly);
    });

    test('no wipe element → null', () {
      expect(provision.parseResponse(_response([])).remoteWipe, isNull);
    });
  });

  group('RemoteWipeAckCommand', () {
    test('builds RemoteWipe/Status request', () {
      final doc = RemoteWipeAckCommand(
        type: RemoteWipeType.full,
        status: RemoteWipeAckStatus.success,
      ).buildRequest();
      final decoded = decoder.decode(encoder.encode(doc));
      final wipe = decoded.root.findChild('Provision', 'RemoteWipe');
      expect(wipe?.childText('Provision', 'Status'), '1');
      expect(decoded.root.findChild('Provision', 'Policies'), isNull);
    });

    test('builds AccountOnlyRemoteWipe/Status request', () {
      final doc = RemoteWipeAckCommand(
        type: RemoteWipeType.accountOnly,
        status: RemoteWipeAckStatus.failure,
      ).buildRequest();
      final decoded = decoder.decode(encoder.encode(doc));
      final wipe = decoded.root.findChild('Provision', 'AccountOnlyRemoteWipe');
      expect(wipe?.childText('Provision', 'Status'), '2');
    });

    test('parses Provision status', () {
      final cmd = RemoteWipeAckCommand(
        type: RemoteWipeType.full,
        status: RemoteWipeAckStatus.success,
      );
      expect(cmd.parseResponse(_response([])), ProvisionStatus.success);
    });
  });

  group('EasClient remote wipe flow', () {
    test('provision throws, acknowledgeRemoteWipe sends ack', () async {
      final requests = <WbxmlDocument>[];
      final client = EasClient(
        server: 'mail.example.com',
        credentials: BasicCredentials(username: 'user', password: 'secret'),
        deviceId: 'dev1',
        httpClient: MockClient((req) async {
          final doc = decoder.decode(req.bodyBytes);
          requests.add(doc);
          final wipeRequested =
              doc.root.findChild('Provision', 'RemoteWipe') == null;
          return http.Response.bytes(
            encoder.encode(
              _response(wipeRequested ? [_prov('RemoteWipe')] : []),
            ),
            200,
          );
        }),
      );

      await expectLater(
        client.provision(policyAckStatus: PolicyAckStatus.success),
        throwsA(
          isA<EasRemoteWipeException>().having(
            (e) => e.type,
            'type',
            RemoteWipeType.full,
          ),
        ),
      );

      await client.acknowledgeRemoteWipe(
        type: RemoteWipeType.full,
        status: RemoteWipeAckStatus.success,
      );
      final ack = requests.last.root.findChild('Provision', 'RemoteWipe');
      expect(ack?.childText('Provision', 'Status'), '1');
    });

    test('acknowledgeRemoteWipe throws on non-success status', () async {
      final client = EasClient(
        server: 'mail.example.com',
        credentials: BasicCredentials(username: 'user', password: 'secret'),
        deviceId: 'dev1',
        httpClient: MockClient(
          (_) async => http.Response.bytes(
            encoder.encode(
              WbxmlDocument(
                root: _prov(
                  'Provision',
                  children: [_prov('Status', text: '3')],
                ),
              ),
            ),
            200,
          ),
        ),
      );
      await expectLater(
        client.acknowledgeRemoteWipe(
          type: RemoteWipeType.accountOnly,
          status: RemoteWipeAckStatus.success,
        ),
        throwsA(
          isA<EasCommandException>().having((e) => e.easStatus, 'easStatus', 3),
        ),
      );
    });
  });
}
