import 'dart:math';

import 'package:eas_client/eas_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

final _creds = BasicCredentials(username: 'user', password: 'secret');

String _settings(String url, {String? displayName}) =>
    '''<?xml version="1.0" encoding="utf-8"?>
<Autodiscover xmlns:autodiscover="http://schemas.microsoft.com/exchange/autodiscover/mobilesync/responseschema/2006">
  <autodiscover:Response>
    <autodiscover:Culture>en:us</autodiscover:Culture>
    <autodiscover:User>
      ${displayName != null ? '<autodiscover:DisplayName>$displayName</autodiscover:DisplayName>' : ''}
      <autodiscover:EMailAddress>chris@example.com</autodiscover:EMailAddress>
    </autodiscover:User>
    <autodiscover:Action>
      <autodiscover:Settings>
        <autodiscover:Server>
          <autodiscover:Type>MobileSync</autodiscover:Type>
          <autodiscover:Url>$url</autodiscover:Url>
          <autodiscover:Name>$url</autodiscover:Name>
        </autodiscover:Server>
        <autodiscover:Server>
          <autodiscover:Type>CertEnroll</autodiscover:Type>
          <autodiscover:Url>https://cert.example.com/CertEnroll</autodiscover:Url>
          <autodiscover:Name />
          <autodiscover:ServerData>CertEnrollTemplate</autodiscover:ServerData>
        </autodiscover:Server>
      </autodiscover:Settings>
    </autodiscover:Action>
  </autodiscover:Response>
</Autodiscover>''';

String _redirect(String email) =>
    '''<?xml version="1.0" encoding="utf-8"?>
<Autodiscover xmlns:autodiscover="http://schemas.microsoft.com/exchange/autodiscover/mobilesync/responseschema/2006">
  <autodiscover:Response>
    <autodiscover:Action>
      <autodiscover:Redirect>$email </autodiscover:Redirect>
    </autodiscover:Action>
  </autodiscover:Response>
</Autodiscover>''';

class _FakeSrv implements DnsSrvResolver {
  final List<DnsSrvRecord> records;
  final List<String> queried = [];
  _FakeSrv(this.records);

  @override
  Future<List<DnsSrvRecord>> lookupSrv(String name) async {
    queried.add(name);
    return records;
  }
}

void main() {
  group('Autodiscover response parsing (full schema)', () {
    test('parses prefixed response with all fields', () {
      final r = AutodiscoverResponse.tryParse(
        _settings(
          'https://mail.example.com/Microsoft-Server-ActiveSync',
          displayName: 'Chris Gray',
        ),
      )!;
      expect(r.culture, 'en:us');
      expect(r.displayName, 'Chris Gray');
      expect(r.emailAddress, 'chris@example.com');
      expect(r.servers, hasLength(2));
      expect(r.mobileSync!.url, contains('mail.example.com'));
      expect(r.certEnroll!.url, 'https://cert.example.com/CertEnroll');
      expect(r.certEnroll!.serverData, 'CertEnrollTemplate');
      expect(r.certEnroll!.name, isNull);
      expect(r.error, isNull);
      expect(r.redirectEmail, isNull);
    });

    test('Action/Redirect is parsed as email redirect', () {
      final r = AutodiscoverResponse.tryParse(
        _redirect('chris@loan.example.com'),
      )!;
      expect(r.redirectEmail, 'chris@loan.example.com');
      expect(Autodiscover.resultFrom(r), isNull);
    });

    test('Response/Error with ErrorCode and attributes', () {
      final r = AutodiscoverResponse.tryParse('''<Autodiscover
 xmlns:autodiscover="http://schemas.microsoft.com/exchange/autodiscover/mobilesync/responseschema/2006">
<autodiscover:Response>
<autodiscover:Error Time="16:56:32.6164027" Id="1054084152">
<autodiscover:ErrorCode>600</autodiscover:ErrorCode>
<autodiscover:Message>Invalid Request</autodiscover:Message>
<autodiscover:DebugData />
</autodiscover:Error>
</autodiscover:Response>
</Autodiscover>''')!;
      final e = r.error!;
      expect(e.errorCode, AutodiscoverErrorCode.invalidRequest);
      expect(e.message, 'Invalid Request');
      expect(e.debugData, isNull);
      expect(e.time, '16:56:32.6164027');
      expect(e.id, '1054084152');
      expect(e.isActionError, isFalse);
      expect(e.toString(), contains('Invalid request'));
    });

    test('Action/Error with Status', () {
      final r = AutodiscoverResponse.tryParse('''<Autodiscover><Response>
<Action><Error><Status>2</Status><Message>Directory unreachable</Message>
<DebugData>MailUser</DebugData></Error></Action></Response></Autodiscover>''')!;
      expect(r.error!.status, AutodiscoverError.statusProtocolError);
      expect(r.error!.isActionError, isTrue);
      expect(r.error!.debugData, 'MailUser');
    });

    test('error code descriptions', () {
      for (final c in [500, 501, 600, 601, 602, 603]) {
        expect(AutodiscoverErrorCode.describe(c), isNotNull);
      }
      expect(AutodiscoverErrorCode.describe(999), isNull);
    });

    test('MobileSync with non-HTTPS URL is ignored', () {
      final r = AutodiscoverResponse.tryParse(
        _settings('http://mail.example.com/Microsoft-Server-ActiveSync'),
      )!;
      expect(r.mobileSync, isNull);
    });

    test('malformed XML returns null', () {
      expect(AutodiscoverResponse.tryParse('<Autodiscover><Response>'), isNull);
    });
  });

  group('Autodiscover discovery flow', () {
    test('step 1 success; credentials only over HTTPS', () async {
      final requests = <http.Request>[];
      final client = MockClient((req) async {
        requests.add(req);
        expect(req.url.scheme, 'https');
        return http.Response(
          _settings(
            'https://mail.example.com/Microsoft-Server-ActiveSync',
            displayName: 'Chris',
          ),
          200,
        );
      });
      final r = await Autodiscover(
        httpClient: client,
      ).discover(email: 'chris@example.com', credentials: _creds);
      expect(r.server, 'mail.example.com');
      expect(r.displayName, 'Chris');
      expect(r.culture, 'en:us');
      expect(r.certEnroll!.serverData, 'CertEnrollTemplate');
      expect(requests.single.headers['authorization'], startsWith('Basic '));
      expect(requests.single.body, contains('chris@example.com'));
    });

    test('follows HTTPS 302 and 451 redirects on HTTPS steps', () async {
      final client = MockClient((req) async {
        switch (req.url.host) {
          case 'example.com':
            return http.Response(
              '',
              302,
              headers: {
                'location':
                    'https://ad1.example.net/autodiscover/autodiscover.xml',
              },
            );
          case 'ad1.example.net':
            return http.Response(
              '',
              451,
              headers: {
                'x-ms-location':
                    'https://ad2.example.net/autodiscover/autodiscover.xml',
              },
            );
          case 'ad2.example.net':
            return http.Response(
              _settings('https://eas.example.net/Microsoft-Server-ActiveSync'),
              200,
            );
        }
        return http.Response('', 404);
      });
      final r = await Autodiscover(
        httpClient: client,
        useOffice365Fallback: false,
      ).discover(email: 'u@example.com', credentials: _creds);
      expect(r.server, 'eas.example.net');
    });

    test('refuses redirect to HTTP on HTTPS step', () async {
      final hosts = <String>[];
      final client = MockClient((req) async {
        hosts.add('${req.url.scheme}://${req.url.host}');
        if (req.url.host == 'example.com') {
          return http.Response(
            '',
            302,
            headers: {
              'location':
                  'http://evil.example.com/autodiscover/autodiscover.xml',
            },
          );
        }
        return http.Response('', 404);
      });
      await expectLater(
        Autodiscover(
          httpClient: client,
          useOffice365Fallback: false,
        ).discover(email: 'u@example.com', credentials: _creds),
        throwsA(isA<AutodiscoverException>()),
      );
      expect(hosts, isNot(contains('http://evil.example.com')));
    });

    test('detects circular HTTP redirects', () async {
      var count = 0;
      final client = MockClient((req) async {
        count++;
        return http.Response(
          '',
          302,
          headers: {'location': req.url.toString()},
        );
      });
      await expectLater(
        Autodiscover(
          httpClient: client,
          useOffice365Fallback: false,
        ).discover(email: 'u@example.com', credentials: _creds),
        throwsA(isA<AutodiscoverException>()),
      );
      expect(count, 2); // one per HTTPS candidate
    });

    test('limits HTTP redirect chain length', () async {
      var n = 0;
      final client = MockClient((req) async {
        n++;
        return http.Response(
          '',
          302,
          headers: {'location': 'https://r$n.example.com/a'},
        );
      });
      await expectLater(
        Autodiscover(
          httpClient: client,
          useOffice365Fallback: false,
        ).discover(email: 'u@example.com', credentials: _creds),
        throwsA(isA<AutodiscoverException>()),
      );
      expect(n, 2 * (Autodiscover.maxHttpRedirects + 1));
    });

    test('Action/Redirect restarts discovery with new email', () async {
      final bodies = <String>[];
      final client = MockClient((req) async {
        bodies.add(req.body);
        if (req.url.host == 'example.com') {
          return http.Response(_redirect('chris@loan.example.org'), 200);
        }
        if (req.url.host == 'loan.example.org') {
          return http.Response(
            _settings('https://loan.example.org/Microsoft-Server-ActiveSync'),
            200,
          );
        }
        return http.Response('', 404);
      });
      final r = await Autodiscover(
        httpClient: client,
      ).discover(email: 'chris@example.com', credentials: _creds);
      expect(r.server, 'loan.example.org');
      expect(bodies.last, contains('chris@loan.example.org'));
    });

    test('email redirect loop is limited to 10', () async {
      var i = 0;
      final client = MockClient((req) async {
        i++;
        return http.Response(_redirect('u$i@d$i.example.com'), 200);
      });
      final future = Autodiscover(
        httpClient: client,
      ).discover(email: 'u@example.com', credentials: _creds);
      await expectLater(
        future,
        throwsA(
          isA<AutodiscoverException>().having(
            (e) => e.message,
            'message',
            contains('Too many'),
          ),
        ),
      );
      expect(i, Autodiscover.maxEmailRedirects + 1);
    });

    test('circular email redirect is skipped', () async {
      final client = MockClient((req) async {
        return http.Response(_redirect('U@example.com'), 200);
      });
      await expectLater(
        Autodiscover(
          httpClient: client,
          useOffice365Fallback: false,
        ).discover(email: 'u@example.com', credentials: _creds),
        throwsA(
          isA<AutodiscoverException>().having(
            (e) => e.errors.values,
            'errors',
            contains('Circular email redirect'),
          ),
        ),
      );
    });

    test('Autodiscover Error moves on to next candidate', () async {
      final client = MockClient((req) async {
        if (req.url.host == 'example.com') {
          return http.Response(
            '<Autodiscover><Response><Error><ErrorCode>603</ErrorCode>'
            '</Error></Response></Autodiscover>',
            200,
          );
        }
        return http.Response(
          _settings('https://eas.example.com/Microsoft-Server-ActiveSync'),
          200,
        );
      });
      final r = await Autodiscover(
        httpClient: client,
      ).discover(email: 'u@example.com', credentials: _creds);
      expect(r.server, 'eas.example.com');
    });

    test('rejects oversized responses', () async {
      final client = MockClient((req) async => http.Response('x' * 2000, 200));
      await expectLater(
        Autodiscover(
          httpClient: client,
          maxResponseSize: 1000,
          useOffice365Fallback: false,
        ).discover(email: 'u@example.com', credentials: _creds),
        throwsA(
          isA<AutodiscoverException>().having(
            (e) => e.errors.values,
            'errors',
            everyElement('Response exceeds size limit'),
          ),
        ),
      );
    });

    test('rejects domains that could alter the URL', () async {
      final client = MockClient((req) async => http.Response('', 404));
      for (final email in [
        'a@evil.com/x',
        'a@evil.com#',
        'a@x..com',
        'a@evil.com:8080',
      ]) {
        await expectLater(
          Autodiscover(
            httpClient: client,
          ).discover(email: email, credentials: _creds),
          throwsA(isA<AutodiscoverException>()),
          reason: email,
        );
      }
    });
  });

  group('Step 3: HTTP GET redirect (opt-in)', () {
    MockClient step3Client(List<http.Request> log, {String? location}) =>
        MockClient((req) async {
          log.add(req);
          if (req.url.scheme == 'http') {
            return http.Response('', 302, headers: {'location': ?location});
          }
          if (req.url.host == 'redirected.example.net') {
            return http.Response(
              _settings('https://eas.example.net/Microsoft-Server-ActiveSync'),
              200,
            );
          }
          return http.Response('', 404);
        });

    const target =
        'https://redirected.example.net/autodiscover/autodiscover.xml';

    test('disabled by default: no plain HTTP request', () async {
      final log = <http.Request>[];
      await expectLater(
        Autodiscover(
          httpClient: step3Client(log, location: target),
          useOffice365Fallback: false,
          confirmRedirect: (_) async => true,
        ).discover(email: 'u@example.com', credentials: _creds),
        throwsA(isA<AutodiscoverException>()),
      );
      expect(log.where((r) => r.url.scheme == 'http'), isEmpty);
    });

    test('GET is unauthenticated; confirmed HTTPS target is used', () async {
      final log = <http.Request>[];
      final confirmed = <Uri>[];
      final r = await Autodiscover(
        httpClient: step3Client(log, location: target),
        enableHttpRedirectStep: true,
        useOffice365Fallback: false,
        confirmRedirect: (uri) async {
          confirmed.add(uri);
          return true;
        },
      ).discover(email: 'u@example.com', credentials: _creds);

      expect(r.server, 'eas.example.net');
      expect(confirmed, [Uri.parse(target)]);
      final get = log.singleWhere((r) => r.url.scheme == 'http');
      expect(get.method, 'GET');
      expect(
        get.url.toString(),
        'http://autodiscover.example.com/autodiscover/autodiscover.xml',
      );
      expect(
        get.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('authorization')),
      );
      expect(get.body, isEmpty);
      final post = log.last;
      expect(post.url.host, 'redirected.example.net');
      expect(post.headers['authorization'], isNotNull);
    });

    test('rejected when no confirmation callback is provided', () async {
      final log = <http.Request>[];
      await expectLater(
        Autodiscover(
          httpClient: step3Client(log, location: target),
          enableHttpRedirectStep: true,
          useOffice365Fallback: false,
        ).discover(email: 'u@example.com', credentials: _creds),
        throwsA(isA<AutodiscoverException>()),
      );
      expect(log.where((r) => r.url.host == 'redirected.example.net'), isEmpty);
    });

    test('rejected when consumer declines or callback throws', () async {
      for (final cb in <AutodiscoverRedirectConfirmation>[
        (_) async => false,
        (_) async => throw StateError('boom'),
      ]) {
        final log = <http.Request>[];
        await expectLater(
          Autodiscover(
            httpClient: step3Client(log, location: target),
            enableHttpRedirectStep: true,
            useOffice365Fallback: false,
            confirmRedirect: cb,
          ).discover(email: 'u@example.com', credentials: _creds),
          throwsA(isA<AutodiscoverException>()),
        );
        expect(
          log.where((r) => r.url.host == 'redirected.example.net'),
          isEmpty,
        );
      }
    });

    test('HTTP Location is never followed', () async {
      final log = <http.Request>[];
      var asked = false;
      await expectLater(
        Autodiscover(
          httpClient: step3Client(
            log,
            location:
                'http://redirected.example.net/autodiscover/autodiscover.xml',
          ),
          enableHttpRedirectStep: true,
          useOffice365Fallback: false,
          confirmRedirect: (_) async => asked = true,
        ).discover(email: 'u@example.com', credentials: _creds),
        throwsA(isA<AutodiscoverException>()),
      );
      expect(asked, isFalse);
      expect(log.where((r) => r.url.host == 'redirected.example.net'), isEmpty);
    });
  });

  group('Step 4: DNS SRV (opt-in)', () {
    MockClient srvClient(List<http.Request> log) => MockClient((req) async {
      log.add(req);
      if (req.url.host == 'srv.example.net') {
        return http.Response(
          _settings('https://eas.example.net/Microsoft-Server-ActiveSync'),
          200,
        );
      }
      return http.Response('', 404);
    });

    test('uses ordered, confirmed SRV targets over HTTPS', () async {
      final log = <http.Request>[];
      final srv = _FakeSrv(const [
        DnsSrvRecord(
          priority: 20,
          weight: 0,
          port: 443,
          target: 'srv.example.net',
        ),
        DnsSrvRecord(
          priority: 10,
          weight: 0,
          port: 8443,
          target: 'first.example.net',
        ),
        DnsSrvRecord(priority: 5, weight: 0, port: 443, target: ''),
      ]);
      final confirmed = <Uri>[];
      final r = await Autodiscover(
        httpClient: srvClient(log),
        srvResolver: srv,
        useOffice365Fallback: false,
        random: Random(1),
        confirmRedirect: (u) async {
          confirmed.add(u);
          return true;
        },
      ).discover(email: 'u@example.com', credentials: _creds);

      expect(r.server, 'eas.example.net');
      expect(srv.queried, ['_autodiscover._tcp.example.com']);
      expect(confirmed.map((u) => u.toString()), [
        'https://first.example.net:8443/autodiscover/autodiscover.xml',
        'https://srv.example.net/autodiscover/autodiscover.xml',
      ]);
      expect(log.every((r) => r.url.scheme == 'https'), isTrue);
    });

    test('SRV targets rejected without confirmation', () async {
      final log = <http.Request>[];
      await expectLater(
        Autodiscover(
          httpClient: srvClient(log),
          srvResolver: _FakeSrv(const [
            DnsSrvRecord(
              priority: 1,
              weight: 0,
              port: 443,
              target: 'srv.example.net',
            ),
          ]),
          useOffice365Fallback: false,
        ).discover(email: 'u@example.com', credentials: _creds),
        throwsA(isA<AutodiscoverException>()),
      );
      expect(log.where((r) => r.url.host == 'srv.example.net'), isEmpty);
    });

    test('invalid SRV target hostnames are skipped', () async {
      final log = <http.Request>[];
      final confirmed = <Uri>[];
      await expectLater(
        Autodiscover(
          httpClient: srvClient(log),
          srvResolver: _FakeSrv(const [
            DnsSrvRecord(priority: 1, weight: 0, port: 443, target: 'bad host'),
            DnsSrvRecord(priority: 1, weight: 0, port: 0, target: 'zero.port'),
          ]),
          useOffice365Fallback: false,
          confirmRedirect: (u) async {
            confirmed.add(u);
            return true;
          },
        ).discover(email: 'u@example.com', credentials: _creds),
        throwsA(isA<AutodiscoverException>()),
      );
      expect(confirmed, isEmpty);
    });
  });
}
