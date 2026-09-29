import 'dart:convert';
import 'dart:typed_data';

import 'package:eas_client/eas_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

final _encoder = WbxmlEncoder();
final _decoder = WbxmlDecoder();

WbxmlElement _rt(WbxmlDocument doc) =>
    _decoder.decode(_encoder.encode(doc)).root;

WbxmlElement _e(
  String ns,
  int cp,
  String tag, {
  String? text,
  List<WbxmlElement>? children,
}) => WbxmlElement(
  namespace: ns,
  tag: tag,
  codePageIndex: cp,
  text: text,
  children: children,
);

WbxmlElement _rr(String tag, {String? text, List<WbxmlElement>? children}) =>
    _e('ResolveRecipients', 10, tag, text: text, children: children);

WbxmlElement _vc(String tag, {String? text, List<WbxmlElement>? children}) =>
    _e('ValidateCert', 11, tag, text: text, children: children);

WbxmlElement _pv(String tag, {String? text, List<WbxmlElement>? children}) =>
    _e('Provision', 14, tag, text: text, children: children);

List<String> _tags(WbxmlElement el) => [for (final c in el.children) c.tag];

void main() {
  group('ResolveRecipients', () {
    test('request: To elements, then Options in schema order', () {
      final root = _rt(
        ResolveRecipientsCommand(
          recipients: ['a@example.com', 'Testers'],
          certificateRetrieval: CertificateRetrieval.mini,
          maxCertificates: 99,
          maxAmbiguousRecipients: 5,
          availabilityStartTime: DateTime.utc(2026, 1, 1, 8),
          availabilityEndTime: DateTime.utc(2026, 1, 2, 8),
          picture: true,
          pictureMaxSize: 1024,
          maxPictures: 10,
        ).buildRequest(),
      );
      expect(_tags(root), ['To', 'To', 'Options']);
      final options = root.findChild('ResolveRecipients', 'Options')!;
      expect(_tags(options), [
        'CertificateRetrieval',
        'MaxCertificates',
        'MaxAmbiguousRecipients',
        'Availability',
        'Picture',
      ]);
      expect(
        options.childText('ResolveRecipients', 'CertificateRetrieval'),
        '3',
      );
      final avail = options.findChild('ResolveRecipients', 'Availability')!;
      expect(
        avail.childText('ResolveRecipients', 'StartTime'),
        '2026-01-01T08:00:00.000Z',
      );
      final pic = options.findChild('ResolveRecipients', 'Picture')!;
      expect(pic.childText('ResolveRecipients', 'MaxSize'), '1024');
      expect(pic.childText('ResolveRecipients', 'MaxPictures'), '10');
    });

    test('request without options has no Options element', () {
      final root = _rt(
        ResolveRecipientsCommand(recipients: ['a']).buildRequest(),
      );
      expect(_tags(root), ['To']);
    });

    test('validation', () {
      expect(
        () => ResolveRecipientsCommand(recipients: const []),
        throwsArgumentError,
      );
      expect(
        () => ResolveRecipientsCommand(recipients: ['x' * 257]),
        throwsArgumentError,
      );
      expect(
        () => ResolveRecipientsCommand(recipients: List.filled(101, 'a')),
        throwsArgumentError,
      );
      expect(
        () => ResolveRecipientsCommand(
          recipients: ['a'],
          maxAmbiguousRecipients: 10000,
        ),
        throwsArgumentError,
      );
      expect(
        () => ResolveRecipientsCommand(
          recipients: ['a'],
          availabilityEndTime: DateTime.utc(2026),
        ),
        throwsArgumentError,
      );
    });

    test('response: certificates, mini certificate, availability, picture', () {
      final cert = [1, 2, 3, 4];
      final doc = WbxmlDocument(
        root: _rr(
          'ResolveRecipients',
          children: [
            _rr('Status', text: '1'),
            _rr(
              'Response',
              children: [
                _rr('To', text: 'Testers'),
                _rr('Status', text: '1'),
                _rr('RecipientCount', text: '1'),
                _rr(
                  'Recipient',
                  children: [
                    _rr('Type', text: '2'),
                    _rr('DisplayName', text: 'Testers'),
                    _rr('EmailAddress', text: 't@example.com'),
                    _rr(
                      'Availability',
                      children: [
                        _rr('Status', text: '1'),
                        _rr('MergedFreeBusy', text: '0120'),
                      ],
                    ),
                    _rr(
                      'Certificates',
                      children: [
                        _rr('Status', text: '1'),
                        _rr('CertificateCount', text: '2'),
                        _rr('RecipientCount', text: '3'),
                        _rr('Certificate', text: base64.encode(cert)),
                        _rr('MiniCertificate', text: 'AAAAAEfXfBA='),
                      ],
                    ),
                    _rr(
                      'Picture',
                      children: [
                        _rr('Status', text: '1'),
                        _rr('Data', text: base64.encode([9, 9])),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
      final r = ResolveRecipientsCommand(
        recipients: ['Testers'],
      ).parseResponse(_decoder.decode(_encoder.encode(doc)));
      expect(r, hasLength(1));
      expect(r.first.recipientCount, 1);
      final rec = r.first.recipients.single;
      expect(rec.type, ResolvedRecipientType.contact);
      expect(rec.availability!.status, 1);
      expect(rec.mergedFreeBusy, '0120');
      expect(rec.certificateInfo!.certificateCount, 2);
      expect(rec.certificateInfo!.recipientCount, 3);
      expect(rec.certificates.single, cert);
      expect(rec.certificateInfo!.miniCertificate, isNotNull);
      expect(rec.picture!.data, [9, 9]);
      expect(rec.toString(), isNot(contains('example.com')));
    });

    test('top-level failure maps to every recipient', () {
      final doc = WbxmlDocument(
        root: _rr('ResolveRecipients', children: [_rr('Status', text: '5')]),
      );
      final r = ResolveRecipientsCommand(
        recipients: ['a', 'b'],
      ).parseResponse(doc);
      expect(r.map((e) => e.status), [5, 5]);
      expect(r.first.statusInfo, ResolveRecipientsStatus.protocolError);
    });
  });

  group('ValidateCert', () {
    final cert = Uint8List.fromList([0x30, 0x82, 0x01, 0x0A]);
    final ca = Uint8List.fromList([0x30, 0x82, 0x02, 0x0B]);

    test('request: CertificateChain, Certificates, CheckCRL; base64 text', () {
      final root = _rt(
        ValidateCertCommand(
          certificates: [cert],
          certificateChain: [ca],
        ).buildRequest(),
      );
      expect(_tags(root), ['CertificateChain', 'Certificates', 'CheckCRL']);
      expect(
        root
            .findChild('ValidateCert', 'Certificates')!
            .childText('ValidateCert', 'Certificate'),
        base64.encode(cert),
      );
      expect(
        root
            .findChild('ValidateCert', 'CertificateChain')!
            .childText('ValidateCert', 'Certificate'),
        base64.encode(ca),
      );
      expect(root.childText('ValidateCert', 'CheckCRL'), '1');
    });

    test('CheckCRL omitted when null', () {
      final root = _rt(
        ValidateCertCommand(
          certificates: [cert],
          checkCRL: null,
        ).buildRequest(),
      );
      expect(_tags(root), ['Certificates']);
    });

    test('response: per-certificate status', () {
      final doc = WbxmlDocument(
        root: _vc(
          'ValidateCert',
          children: [
            _vc('Status', text: '1'),
            _vc('Certificate', children: [_vc('Status', text: '1')]),
            _vc('Certificate', children: [_vc('Status', text: '13')]),
          ],
        ),
      );
      final r = ValidateCertCommand(
        certificates: [cert, cert],
      ).parseResponse(_decoder.decode(_encoder.encode(doc)));
      expect(r.map((e) => e.status), [1, 13]);
      expect(r.last.statusInfo, ValidateCertStatus.revoked);
    });

    test('response: top-level failure', () {
      final doc = WbxmlDocument(
        root: _vc('ValidateCert', children: [_vc('Status', text: '17')]),
      );
      final r = ValidateCertCommand(certificates: [cert]).parseResponse(doc);
      expect(r.single.status, 17);
    });
  });

  group('Provision', () {
    test('initial request: DeviceInformation precedes Policies', () {
      final root = _rt(
        ProvisionCommand.buildInitialRequest(
          easProvisioningWbxml,
          EasDeviceInformation(model: 'M', os: 'OS'),
        ),
      );
      expect(_tags(root), ['DeviceInformation', 'Policies']);
      expect(
        root
            .findChild('Settings', 'DeviceInformation')!
            .findChild('Settings', 'Set')!
            .childText('Settings', 'Model'),
        'M',
      );
    });

    test('policy type and DeviceInformation depend on version', () {
      expect(ProvisionCommand.policyTypeFor('2.5'), wapProvisioningXml);
      expect(ProvisionCommand.policyTypeFor('12.1'), easProvisioningWbxml);
      expect(ProvisionCommand.sendsDeviceInformation('14.0'), isFalse);
      expect(ProvisionCommand.sendsDeviceInformation('14.1'), isTrue);
      expect(ProvisionCommand.sendsDeviceInformation('16.1'), isTrue);
    });

    test('DeviceInformation requires Model', () {
      expect(
        () => ProvisionCommand(
          policyAckStatus: PolicyAckStatus.success,
          deviceInformation: EasDeviceInformation(os: 'x'),
        ),
        throwsArgumentError,
      );
    });

    test('acknowledgement: PolicyType, PolicyKey, Status', () {
      final policy = _rt(
        ProvisionCommand.buildAcknowledgement(
          easProvisioningWbxml,
          '123',
          PolicyAckStatus.success,
        ),
      ).findChild('Provision', 'Policies')!.findChild('Provision', 'Policy')!;
      expect(_tags(policy), ['PolicyType', 'PolicyKey', 'Status']);
    });

    WbxmlDocument response(List<WbxmlElement> provDoc) => WbxmlDocument(
      root: _pv(
        'Provision',
        children: [
          _pv('Status', text: '1'),
          _pv(
            'Policies',
            children: [
              _pv(
                'Policy',
                children: [
                  _pv('PolicyType', text: easProvisioningWbxml),
                  _pv('Status', text: '1'),
                  _pv('PolicyKey', text: '42'),
                  _pv(
                    'Data',
                    children: [_pv('EASProvisionDoc', children: provDoc)],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    test('parses 14.x/16.x elements and application lists', () {
      final r = ProvisionCommand(policyAckStatus: PolicyAckStatus.success)
          .parseResponse(
            _decoder.decode(
              _encoder.encode(
                response([
                  _pv('AllowBluetooth', text: '1'),
                  _pv('MaxCalendarAgeFilter', text: '5'),
                  _pv('MaxEmailAgeFilter', text: '3'),
                  _pv('RequireSignedSMIMEAlgorithm', text: '0'),
                  _pv('RequireEncryptionSMIMEAlgorithm', text: '2'),
                  _pv('AllowSMIMEEncryptionAlgorithmNegotiation', text: '1'),
                  _pv('MaxInactivityTimeDeviceLock', text: ''),
                  _pv(
                    'UnapprovedInROMApplicationList',
                    children: [
                      _pv('ApplicationName', text: 'app1'),
                      _pv('ApplicationName', text: 'app2'),
                    ],
                  ),
                  _pv(
                    'ApprovedApplicationList',
                    children: [_pv('Hash', text: 'abc=')],
                  ),
                ]),
              ),
            ),
          );
      final policy = r.policy!;
      expect(policy.allowBluetooth, isTrue);
      final doc = policy.provisionDoc!;
      expect(doc.allowBluetooth, BluetoothPolicy.handsFreeOnly);
      expect(doc.maxCalendarAgeFilter, 5);
      expect(doc.maxEmailAgeFilter, 3);
      expect(doc.requireSignedSMIMEAlgorithm, 0);
      expect(doc.requireEncryptionSMIMEAlgorithm, 2);
      expect(doc.allowSMIMEEncryptionAlgorithmNegotiation, 1);
      expect(doc.has('MaxInactivityTimeDeviceLock'), isTrue);
      expect(doc.integer('MaxInactivityTimeDeviceLock'), isNull);
      expect(doc.unapprovedInRomApplications, ['app1', 'app2']);
      expect(doc.approvedApplicationHashes, ['abc=']);
    });

    test('AllowBluetooth 0 disables, 2 allows', () {
      final cmd = ProvisionCommand(policyAckStatus: PolicyAckStatus.success);
      expect(
        cmd
            .parseResponse(response([_pv('AllowBluetooth', text: '0')]))
            .policy!
            .allowBluetooth,
        isFalse,
      );
      expect(
        cmd
            .parseResponse(response([_pv('AllowBluetooth', text: '2')]))
            .policy!
            .allowBluetooth,
        isTrue,
      );
    });

    test('two-phase flow over HTTP keeps phase 1 policies', () async {
      final requests = <http.Request>[];
      var phase = 0;
      final client = EasHttpClient(
        server: 'mail.example.com',
        credentials: BasicCredentials(username: 'u', password: 'p'),
        deviceId: 'dev1',
        protocolVersion: '14.0',
        httpClient: MockClient((req) async {
          requests.add(req);
          phase++;
          final doc = phase == 1
              ? response([_pv('DevicePasswordEnabled', text: '1')])
              : WbxmlDocument(
                  root: _pv(
                    'Provision',
                    children: [
                      _pv('Status', text: '1'),
                      _pv(
                        'Policies',
                        children: [
                          _pv(
                            'Policy',
                            children: [
                              _pv('PolicyType', text: easProvisioningWbxml),
                              _pv('Status', text: '1'),
                              _pv('PolicyKey', text: '777'),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                );
          return http.Response.bytes(_encoder.encode(doc), 200);
        }),
      );
      final policy = await ProvisionCommand(
        policyAckStatus: PolicyAckStatus.success,
      ).execute(client);
      expect(policy!.policyKey, '777');
      expect(policy.devicePasswordEnabled, isTrue);
      expect(client.policyKey, '777');
      // 14.0: no DeviceInformation in the initial request.
      final first = _decoder.decode(requests.first.bodyBytes).root;
      expect(first.findChild('Settings', 'DeviceInformation'), isNull);
    });

    test(
      'ack without final PolicyKey throws EasPolicyNotAcceptedException',
      () async {
        var phase = 0;
        final client = EasHttpClient(
          server: 'mail.example.com',
          credentials: BasicCredentials(username: 'u', password: 'p'),
          deviceId: 'dev1',
          protocolVersion: '14.0',
          httpClient: MockClient((req) async {
            phase++;
            final doc = phase == 1
                ? response([])
                : WbxmlDocument(
                    root: _pv(
                      'Provision',
                      children: [
                        _pv('Status', text: '1'),
                        _pv(
                          'Policies',
                          children: [
                            _pv(
                              'Policy',
                              children: [
                                _pv('PolicyType', text: easProvisioningWbxml),
                                _pv('Status', text: '1'),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
            return http.Response.bytes(_encoder.encode(doc), 200);
          }),
        );
        await expectLater(
          ProvisionCommand(
            policyAckStatus: PolicyAckStatus.notApplied,
          ).execute(client),
          throwsA(
            isA<EasPolicyNotAcceptedException>().having(
              (e) => e.ackStatus,
              'ackStatus',
              PolicyAckStatus.notApplied,
            ),
          ),
        );
      },
    );

    test('HTTP 503 maps to EasServiceUnavailableException', () async {
      final client = EasHttpClient(
        server: 'mail.example.com',
        credentials: BasicCredentials(username: 'u', password: 'p'),
        deviceId: 'dev1',
        httpClient: MockClient(
          (req) async => http.Response('', 503, headers: {'retry-after': '7'}),
        ),
      );
      await expectLater(
        ProvisionCommand(
          policyAckStatus: PolicyAckStatus.success,
        ).execute(client),
        throwsA(
          isA<EasServiceUnavailableException>().having(
            (e) => e.retryAfter,
            'retryAfter',
            const Duration(seconds: 7),
          ),
        ),
      );
    });
  });

  group('SmartForward meeting (16.x)', () {
    test('Body precedes Forwardees; no Mime/SaveInSentItems', () {
      final root = _rt(
        SmartForwardCommand.meeting(
          clientId: 'c',
          serverId: '1',
          collectionId: '2',
          accountId: 'acc',
          body: 'FYI',
          forwardees: const [Forwardee(email: 'b@example.com', name: 'B')],
        ).buildRequest(),
      );
      expect(_tags(root), [
        'ClientId',
        'Source',
        'AccountId',
        'Body',
        'Forwardees',
      ]);
      final f = root
          .findChild('ComposeMail', 'Forwardees')!
          .findChild('ComposeMail', 'Forwardee')!;
      expect(f.childText('ComposeMail', 'Email'), 'b@example.com');
      expect(f.childText('ComposeMail', 'Name'), 'B');
    });

    test('requires forwardees or body', () {
      expect(
        () => SmartForwardCommand.meeting(clientId: 'c', longId: 'L'),
        throwsArgumentError,
      );
    });
  });

  group('MeetingResponse proposal', () {
    test('ProposedStartTime and ProposedEndTime must be set together', () {
      expect(
        () => MeetingResponseCommand.single(
          longId: 'L',
          response: MeetingResponseStatus.declined,
          sendResponse: MeetingSendResponse(
            proposedEndTime: DateTime.utc(2026),
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => MeetingResponseCommand.single(
          longId: 'L',
          response: MeetingResponseStatus.tentative,
          sendResponse: MeetingSendResponse(
            proposedStartTime: DateTime.utc(2026),
            proposedEndTime: DateTime.utc(2026, 1, 1, 1),
          ),
        ),
        returnsNormally,
      );
    });
  });
}
