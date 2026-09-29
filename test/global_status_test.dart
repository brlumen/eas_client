import 'dart:typed_data';

import 'package:eas_client/eas_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// Minimal command for exercising [EasCommand] base behaviour.
class _StubCommand extends EasCommand<String?> {
  @override
  String get commandName => 'Ping';

  @override
  WbxmlDocument buildRequest() => WbxmlDocument(
    root: WbxmlElement(namespace: 'Ping', tag: 'Ping', codePageIndex: 13),
  );

  @override
  String? parseResponse(WbxmlDocument response) =>
      response.root.childText('Ping', 'Status');
}

WbxmlDocument _statusDoc(String status) => WbxmlDocument(
  root: WbxmlElement(
    namespace: 'Ping',
    tag: 'Ping',
    codePageIndex: 13,
    children: [
      WbxmlElement.withText(
        namespace: 'Ping',
        tag: 'Status',
        text: status,
        codePageIndex: 13,
      ),
    ],
  ),
);

EasHttpClient _client(Uint8List body) => EasHttpClient(
  server: 'mail.example.com',
  credentials: BasicCredentials(username: 'user', password: 'secret'),
  deviceId: 'dev1',
  httpClient: MockClient((_) async => http.Response.bytes(body, 200)),
);

void main() {
  group('EasGlobalStatus', () {
    test('fromCode maps known codes, rejects command-specific ones', () {
      expect(EasGlobalStatus.fromCode(110), EasGlobalStatus.serverError);
      expect(
        EasGlobalStatus.fromCode(140),
        EasGlobalStatus.remoteWipeRequested,
      );
      expect(
        EasGlobalStatus.fromCode(177),
        EasGlobalStatus.maximumDevicesReached,
      );
      expect(EasGlobalStatus.fromCode(1), isNull);
      expect(EasGlobalStatus.fromCode(157), isNull);
    });

    test('requiresProvisioning only for 142/143/144', () {
      final codes = EasGlobalStatus.values
          .where((s) => s.requiresProvisioning)
          .map((s) => s.code);
      expect(codes, [142, 143, 144]);
    });
  });

  group('EasCommand.checkGlobalStatus', () {
    final cmd = _StubCommand();

    test('command-specific status (< 101) is left to parseResponse', () {
      expect(() => cmd.checkGlobalStatus(_statusDoc('1')), returnsNormally);
      expect(() => cmd.checkGlobalStatus(_statusDoc('9')), returnsNormally);
    });

    test('no Status element is ignored', () {
      final doc = WbxmlDocument(
        root: WbxmlElement(namespace: 'Ping', tag: 'Ping', codePageIndex: 13),
      );
      expect(() => cmd.checkGlobalStatus(doc), returnsNormally);
    });

    for (final code in [142, 143, 144]) {
      test('$code → re-provision signal (same as HTTP 449)', () {
        expect(
          () => cmd.checkGlobalStatus(_statusDoc('$code')),
          throwsA(
            isA<EasCommandException>()
                .having((e) => e.easStatus, 'easStatus', code)
                .having((e) => e.requiresProvisioning, 'reprov', isTrue),
          ),
        );
      });
    }

    test('HTTP 449 exception also reports requiresProvisioning', () {
      final e = EasCommandException(
        command: 'Sync',
        statusCode: 449,
        message: 'x',
      );
      expect(e.requiresProvisioning, isTrue);
      expect(e.globalStatus, isNull);
    });

    test('140 → EasRemoteWipeException without type', () {
      expect(
        () => cmd.checkGlobalStatus(_statusDoc('140')),
        throwsA(
          isA<EasRemoteWipeException>().having((e) => e.type, 'type', isNull),
        ),
      );
    });

    for (final code in [110, 111, 126, 129, 177]) {
      test('$code → EasCommandException with easStatus', () {
        expect(
          () => cmd.checkGlobalStatus(_statusDoc('$code')),
          throwsA(
            isA<EasCommandException>()
                .having((e) => e.easStatus, 'easStatus', code)
                .having((e) => e.globalStatus?.code, 'global', code)
                .having((e) => e.requiresProvisioning, 'reprov', isFalse),
          ),
        );
      });
    }

    test('unknown code >= 101 → EasCommandException', () {
      expect(
        () => cmd.checkGlobalStatus(_statusDoc('199')),
        throwsA(
          isA<EasCommandException>().having(
            (e) => e.easStatus,
            'easStatus',
            199,
          ),
        ),
      );
    });
  });

  group('EasCommand.execute global status', () {
    final encoder = WbxmlEncoder();

    test('status 1 is parsed by the command', () async {
      final client = _client(encoder.encode(_statusDoc('1')));
      expect(await _StubCommand().execute(client), '1');
    });

    test('status 144 throws re-provision EasCommandException', () async {
      final client = _client(encoder.encode(_statusDoc('144')));
      await expectLater(
        _StubCommand().execute(client),
        throwsA(
          isA<EasCommandException>().having(
            (e) => e.requiresProvisioning,
            'reprov',
            isTrue,
          ),
        ),
      );
    });

    test('status 140 throws EasRemoteWipeException', () async {
      final client = _client(encoder.encode(_statusDoc('140')));
      await expectLater(
        _StubCommand().execute(client),
        throwsA(isA<EasRemoteWipeException>()),
      );
    });
  });

  test('exceptions do not leak PII in toString()', () {
    final e = EasCommandException(
      command: 'Sync',
      statusCode: 200,
      easStatus: 126,
      message: EasGlobalStatus.userDisabledForSync.description,
    );
    final w = EasRemoteWipeException(
      command: 'Provision',
      type: RemoteWipeType.accountOnly,
    );
    for (final s in [e.toString(), w.toString()]) {
      expect(s, isNot(contains('user@')));
      expect(s, isNot(contains('secret')));
      expect(s, isNot(contains('dev1')));
    }
    expect(w.toString(), contains('accountOnly'));
  });
}
