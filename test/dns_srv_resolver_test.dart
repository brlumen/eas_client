import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:eas_client/eas_client.dart';
import 'package:test/test.dart';

const _qname = '_autodiscover._tcp.example.com';

List<int> _name(String name) => [
  for (final l in name.split('.')) ...[l.length, ...l.codeUnits],
  0,
];

List<int> _u16(int v) => [v >> 8, v & 0xFF];

List<int> _srvRdata(int prio, int weight, int port, List<int> target) => [
  ..._u16(prio),
  ..._u16(weight),
  ..._u16(port),
  ...target,
];

/// Builds a DNS response. Question name starts at offset 12.
Uint8List _response({
  int id = 0x1234,
  int flags = 0x8180,
  int qdCount = 1,
  List<int>? question,
  required List<List<int>> answers,
}) {
  return Uint8List.fromList([
    ..._u16(id),
    ..._u16(flags),
    ..._u16(qdCount),
    ..._u16(answers.length),
    0, 0, 0, 0, //
    ...(question ?? [..._name(_qname), ..._u16(33), ..._u16(1)]),
    for (final a in answers) ...a,
  ]);
}

List<int> _answer(
  List<int> owner,
  List<int> rdata, {
  int type = 33,
  int? rdLength,
}) => [
  ...owner,
  ..._u16(type),
  ..._u16(1),
  0, 0, 0x0E, 0x10, // TTL
  ..._u16(rdLength ?? rdata.length),
  ...rdata,
];

/// Compression pointer to the question name (offset 12).
const _ptrQ = [0xC0, 12];

List<DnsSrvRecord> _parse(Uint8List p) =>
    DnsSrvCodec.parseResponse(p, expectedId: 0x1234, queryName: _qname);

void main() {
  group('DnsSrvCodec.buildQuery', () {
    test('encodes header, labels and SRV/IN question', () {
      final q = DnsSrvCodec.buildQuery(_qname, 0xABCD);
      expect(q.sublist(0, 12), [0xAB, 0xCD, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0]);
      expect(q.sublist(12), [..._name(_qname), 0, 33, 0, 1]);
    });

    test('rejects invalid names', () {
      expect(() => DnsSrvCodec.buildQuery('', 1), throwsArgumentError);
      expect(() => DnsSrvCodec.buildQuery('a..b', 1), throwsArgumentError);
      expect(
        () => DnsSrvCodec.buildQuery('${'a' * 64}.com', 1),
        throwsArgumentError,
      );
      expect(() => DnsSrvCodec.buildQuery('a b.com', 1), throwsArgumentError);
      expect(
        () => DnsSrvCodec.buildQuery('x.com', 0x10000),
        throwsArgumentError,
      );
    });
  });

  group('DnsSrvCodec.parseResponse', () {
    test('parses SRV answers with compressed owner and target', () {
      // Target "mail" + pointer to "example.com" inside question (12 + 20).
      final exampleOffset = 12 + 1 + 13 + 1 + 4;
      final p = _response(
        answers: [
          _answer(
            _ptrQ,
            _srvRdata(10, 5, 443, [
              4,
              ...'mail'.codeUnits,
              0xC0,
              exampleOffset,
            ]),
          ),
          _answer(
            _name(_qname),
            _srvRdata(20, 0, 8443, _name('alt.example.org')),
          ),
        ],
      );
      final records = _parse(p);
      expect(records, [
        const DnsSrvRecord(
          priority: 10,
          weight: 5,
          port: 443,
          target: 'mail.example.com',
        ),
        const DnsSrvRecord(
          priority: 20,
          weight: 0,
          port: 8443,
          target: 'alt.example.org',
        ),
      ]);
    });

    test(
      'owner name comparison is case-insensitive; foreign records skipped',
      () {
        final p = _response(
          answers: [
            _answer(
              _name('other.example.com'),
              _srvRdata(1, 1, 443, _name('evil.com')),
            ),
            _answer(_name('mail.example.com'), [1, 2, 3, 4], type: 1),
            _answer(
              _name('_AUTODISCOVER._TCP.EXAMPLE.COM'),
              _srvRdata(1, 1, 443, _name('ok.com')),
            ),
          ],
        );
        expect(_parse(p).map((r) => r.target), ['ok.com']);
      },
    );

    test('NXDOMAIN returns empty list', () {
      expect(_parse(_response(flags: 0x8183, answers: [])), isEmpty);
    });

    test('SERVFAIL throws DnsLookupException', () {
      expect(
        () => _parse(_response(flags: 0x8182, answers: [])),
        throwsA(isA<DnsLookupException>()),
      );
    });

    test('truncated flag throws DnsLookupException', () {
      expect(
        () => _parse(_response(flags: 0x8380, answers: [])),
        throwsA(isA<DnsLookupException>()),
      );
    });

    final malformed = <String, Uint8List Function()>{
      'shorter than header': () => Uint8List.fromList([0x12, 0x34, 0x81]),
      'empty packet': () => Uint8List(0),
      'ID mismatch': () => _response(id: 0x9999, answers: []),
      'not a response (QR=0)': () => _response(flags: 0x0100, answers: []),
      'non-zero opcode': () => _response(flags: 0x8980, answers: []),
      'zero questions': () => _response(qdCount: 0, question: [], answers: []),
      'question mismatch': () => _response(
        question: [..._name('_autodiscover._tcp.evil.com'), 0, 33, 0, 1],
        answers: [],
      ),
      'question wrong type': () =>
          _response(question: [..._name(_qname), 0, 1, 0, 1], answers: []),
      'answer count exceeds data': () {
        final p = _response(answers: []);
        p[7] = 3; // ANCOUNT = 3 with no answers
        return p;
      },
      'RDLENGTH beyond packet': () => _response(
        answers: [
          _answer(_ptrQ, _srvRdata(1, 1, 443, _name('a.com')), rdLength: 500),
        ],
      ),
      'SRV RDATA too short': () => _response(
        answers: [
          _answer(_ptrQ, [0, 1, 0, 1], rdLength: 4),
        ],
      ),
      'SRV RDATA length mismatch': () => _response(
        answers: [
          _answer(_ptrQ, [..._srvRdata(1, 1, 443, _name('a.com')), 0, 0]),
        ],
      ),
      'forward compression pointer': () => _response(
        answers: [
          _answer([0xC0, 0xFF], _srvRdata(1, 1, 443, _name('a.com'))),
        ],
      ),
      'self-referencing pointer': () {
        final p = _response(answers: []);
        // Replace question name start with pointer to itself (offset 12).
        final b = BytesBuilder()
          ..add(p.sublist(0, 12))
          ..add([0xC0, 12, 0, 33, 0, 1]);
        return b.toBytes();
      },
      'pointer into header': () => _response(
        answers: [
          _answer([0xC0, 2], _srvRdata(1, 1, 443, _name('a.com'))),
        ],
      ),
      'pointer loop between two offsets': () {
        // Answer target: label "a" then pointer back to itself region.
        final base = _response(answers: []);
        final start = base.length;
        final rdataStart = start + 2 + 10; // owner ptr(2) + fixed(10)
        final targetStart = rdataStart + 6;
        return Uint8List.fromList([
          ...base.sublist(0, 7),
          1, // ANCOUNT
          ...base.sublist(8),
          ..._ptrQ,
          0, 33, 0, 1, 0, 0, 0, 0, 0, 10,
          ..._srvRdata(1, 1, 443, [1, 0x61, 0xC0, targetStart]),
        ]);
      },
      'truncated pointer': () {
        final p = _response(answers: []);
        return Uint8List.fromList([...p.sublist(0, 12), 0xC0]);
      },
      'label exceeds packet': () => Uint8List.fromList([
        ..._response(answers: []).sublist(0, 12),
        40,
        0x61,
      ]),
      'extended label type 0x40': () => Uint8List.fromList([
        ..._response(answers: []).sublist(0, 12),
        0x41,
        0,
      ]),
      'name longer than 255': () => _response(
        question: [
          for (var i = 0; i < 5; i++) ...[63, ...List.filled(63, 0x61)],
          0,
          0,
          33,
          0,
          1,
        ],
        answers: [],
      ),
      'invalid char in label': () => _response(
        answers: [
          _answer(_ptrQ, _srvRdata(1, 1, 443, [3, 0x61, 0x2E, 0x62, 0])),
        ],
      ),
      'missing name terminator': () => Uint8List.fromList([
        ..._response(answers: []).sublist(0, 12),
        1,
        0x61,
      ]),
    };

    for (final entry in malformed.entries) {
      test('rejects malformed packet: ${entry.key}', () {
        expect(() => _parse(entry.value()), throwsA(isA<DnsFormatException>()));
      });
    }

    test('random garbage never throws anything but DNS exceptions', () {
      final rnd = Random(42);
      for (var i = 0; i < 2000; i++) {
        final len = rnd.nextInt(80);
        final p = Uint8List.fromList(
          List.generate(len, (_) => rnd.nextInt(256)),
        );
        if (len >= 2) {
          p[0] = 0x12;
          p[1] = 0x34;
        }
        try {
          _parse(p);
        } on DnsFormatException {
          // expected
        } on DnsLookupException {
          // expected
        }
      }
    });
  });

  group('DnsSrvCodec.order', () {
    test('sorts by priority, drops empty targets', () {
      final ordered = DnsSrvCodec.order([
        const DnsSrvRecord(priority: 20, weight: 1, port: 443, target: 'c'),
        const DnsSrvRecord(priority: 10, weight: 1, port: 443, target: 'a'),
        const DnsSrvRecord(priority: 0, weight: 0, port: 0, target: ''),
        const DnsSrvRecord(priority: 15, weight: 1, port: 443, target: 'b'),
      ], Random(1));
      expect(ordered.map((r) => r.target), ['a', 'b', 'c']);
    });

    test('weighted selection prefers heavier records', () {
      var heavyFirst = 0;
      final rnd = Random(7);
      for (var i = 0; i < 1000; i++) {
        final o = DnsSrvCodec.order([
          const DnsSrvRecord(
            priority: 1,
            weight: 1,
            port: 443,
            target: 'light',
          ),
          const DnsSrvRecord(
            priority: 1,
            weight: 99,
            port: 443,
            target: 'heavy',
          ),
        ], rnd);
        expect(o, hasLength(2));
        if (o.first.target == 'heavy') heavyFirst++;
      }
      expect(heavyFirst, greaterThan(900));
    });
  });

  group('UdpDnsSrvResolver (loopback)', () {
    late RawDatagramSocket server;

    setUp(() async {
      server = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    });

    tearDown(() => server.close());

    UdpDnsSrvResolver resolver() => UdpDnsSrvResolver(
      nameServer: InternetAddress.loopbackIPv4,
      port: server.port,
      timeout: const Duration(milliseconds: 500),
    );

    Uint8List answerFor(Uint8List query, {int? idOverride}) {
      final id = idOverride ?? DnsSrvCodec.peekId(query)!;
      final p = _response(
        id: id,
        question: query.sublist(12),
        answers: [
          _answer(_ptrQ, _srvRdata(0, 0, 443, _name('mail.example.com'))),
        ],
      );
      return p;
    }

    test('resolves SRV records; ignores responses with wrong ID', () async {
      server.listen((e) {
        if (e != RawSocketEvent.read) return;
        final dg = server.receive();
        if (dg == null) return;
        final wrongId = (DnsSrvCodec.peekId(dg.data)! + 1) & 0xFFFF;
        server.send(
          answerFor(dg.data, idOverride: wrongId),
          dg.address,
          dg.port,
        );
        server.send(answerFor(dg.data), dg.address, dg.port);
      });
      final records = await resolver().lookupSrv(_qname);
      expect(records.single.target, 'mail.example.com');
    });

    test('times out when server does not answer', () async {
      expect(resolver().lookupSrv(_qname), throwsA(isA<DnsLookupException>()));
    });

    test('propagates DnsFormatException for malformed reply', () async {
      server.listen((e) {
        if (e != RawSocketEvent.read) return;
        final dg = server.receive();
        if (dg == null) return;
        final bad = answerFor(dg.data);
        bad[2] = 0x01; // QR=0
        server.send(bad, dg.address, dg.port);
      });
      expect(resolver().lookupSrv(_qname), throwsA(isA<DnsFormatException>()));
    });
  });
}
