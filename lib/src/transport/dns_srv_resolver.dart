/// Minimal pure-Dart DNS SRV client (RFC 1035 / RFC 2782) over UDP.
///
/// `dart:io` has no SRV lookup API, so this implements just enough of DNS to
/// resolve `_autodiscover._tcp.<domain>` (MS-OXDISCO 3.1.5.3).
///
/// Design decisions:
/// * **Explicit resolver address.** There is no portable way to obtain the
///   system resolver from pure Dart (no `/etc/resolv.conf` on Android/iOS/
///   Windows), so [UdpDnsSrvResolver] requires the consumer to pass
///   [UdpDnsSrvResolver.nameServer]. Nothing is guessed or hard-coded.
/// * **Anti-spoofing.** Random 16-bit query ID from `Random.secure()`;
///   datagrams from any other address/port or with another ID are ignored;
///   the echoed question must match the query.
/// * **No TCP fallback.** Truncated (TC) responses raise
///   [DnsLookupException].
/// * **Strict parsing.** Every read is bounds-checked; compression pointers
///   must point strictly backwards into the packet (after the header) with a
///   bounded jump count; names are limited to 255 octets; SRV RDATA must be
///   consumed exactly. Any violation raises [DnsFormatException].
///
/// DNS answers are unauthenticated (no DNSSEC): results MUST only be used as
/// HTTPS hosts with certificate validation, after consumer confirmation.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:collection/collection.dart';

/// Single SRV record (RFC 2782).
class DnsSrvRecord {
  final int priority;
  final int weight;
  final int port;

  /// Target hostname without trailing dot. Empty means "service not
  /// available" (RFC 2782 target ".").
  final String target;

  const DnsSrvRecord({
    required this.priority,
    required this.weight,
    required this.port,
    required this.target,
  });

  @override
  bool operator ==(Object other) =>
      other is DnsSrvRecord &&
      other.priority == priority &&
      other.weight == weight &&
      other.port == port &&
      other.target == target;

  @override
  int get hashCode => Object.hash(priority, weight, port, target);

  @override
  String toString() => 'DnsSrvRecord($priority $weight $port $target)';
}

/// Malformed DNS packet.
class DnsFormatException implements Exception {
  final String message;
  const DnsFormatException(this.message);

  @override
  String toString() => 'DnsFormatException: $message';
}

/// DNS lookup failure (timeout, server error, truncation).
class DnsLookupException implements Exception {
  final String message;
  const DnsLookupException(this.message);

  @override
  String toString() => 'DnsLookupException: $message';
}

/// Abstraction for SRV lookups (injectable in tests).
abstract interface class DnsSrvResolver {
  /// Returns SRV records for [name]; empty list if the name does not exist
  /// or has no SRV records.
  Future<List<DnsSrvRecord>> lookupSrv(String name);
}

/// DNS wire-format codec for SRV queries.
abstract final class DnsSrvCodec {
  static const typeSrv = 33;
  static const classIn = 1;
  static const _headerSize = 12;
  static const _maxNameLength = 255;
  static const _maxPointerJumps = 32;
  static const _rcodeNxDomain = 3;

  static final _labelPattern = RegExp(r'^[A-Za-z0-9_]([A-Za-z0-9_-]*)$');

  /// Builds a recursive SRV query for [name] with transaction [id].
  static Uint8List buildQuery(String name, int id) {
    if (id < 0 || id > 0xFFFF) throw ArgumentError.value(id, 'id');
    final labels = _splitName(name);
    final out = BytesBuilder(copy: false)
      ..add([id >> 8, id & 0xFF, 0x01, 0x00]) // RD=1
      ..add([0, 1, 0, 0, 0, 0, 0, 0]); // QD=1, AN=NS=AR=0
    for (final l in labels) {
      out
        ..addByte(l.length)
        ..add(l.codeUnits);
    }
    out
      ..addByte(0)
      ..add([0, typeSrv, 0, classIn]);
    return out.takeBytes();
  }

  /// Reads the transaction ID, or `null` if [packet] is too short.
  static int? peekId(Uint8List packet) =>
      packet.length < 2 ? null : (packet[0] << 8) | packet[1];

  /// Parses a response to an SRV query for [queryName] with [expectedId].
  ///
  /// Returns an empty list on NXDOMAIN. Throws [DnsFormatException] on
  /// malformed packets and [DnsLookupException] on truncation / server errors.
  static List<DnsSrvRecord> parseResponse(
    Uint8List packet, {
    required int expectedId,
    required String queryName,
  }) {
    final r = _Reader(packet);
    if (packet.length < _headerSize) {
      throw const DnsFormatException('Packet shorter than header');
    }
    final id = r.u16();
    if (id != expectedId) throw const DnsFormatException('ID mismatch');
    final flags = r.u16();
    if (flags & 0x8000 == 0) throw const DnsFormatException('Not a response');
    if ((flags >> 11) & 0xF != 0) {
      throw const DnsFormatException('Unexpected opcode');
    }
    if (flags & 0x0200 != 0) {
      throw const DnsLookupException('Truncated response (TCP unsupported)');
    }
    final rcode = flags & 0xF;
    final qd = r.u16();
    final an = r.u16();
    r.u16(); // NS
    r.u16(); // AR

    if (qd != 1) throw const DnsFormatException('Question count must be 1');
    final wanted = _canonical(queryName);
    final qName = r.name();
    final qType = r.u16();
    final qClass = r.u16();
    if (qName.toLowerCase() != wanted ||
        qType != typeSrv ||
        qClass != classIn) {
      throw const DnsFormatException('Question does not match query');
    }

    if (rcode == _rcodeNxDomain) return const [];
    if (rcode != 0) throw DnsLookupException('Server returned RCODE $rcode');

    final records = <DnsSrvRecord>[];
    for (var i = 0; i < an; i++) {
      final owner = r.name();
      final type = r.u16();
      final cls = r.u16();
      r.u32(); // TTL
      final rdLength = r.u16();
      final rdEnd = r.offset + rdLength;
      if (rdEnd > packet.length) {
        throw const DnsFormatException('RDATA exceeds packet');
      }
      if (type == typeSrv && cls == classIn && owner.toLowerCase() == wanted) {
        if (rdLength < 7) throw const DnsFormatException('SRV RDATA too short');
        final priority = r.u16();
        final weight = r.u16();
        final port = r.u16();
        final target = r.name();
        if (r.offset != rdEnd) {
          throw const DnsFormatException('SRV RDATA length mismatch');
        }
        records.add(
          DnsSrvRecord(
            priority: priority,
            weight: weight,
            port: port,
            target: target,
          ),
        );
      } else {
        r.offset = rdEnd;
      }
    }
    return records;
  }

  /// Orders [records] per RFC 2782: ascending priority, weighted random
  /// selection within a priority. Records with empty target are dropped.
  static List<DnsSrvRecord> order(List<DnsSrvRecord> records, Random random) {
    final byPriority = groupBy(
      records.where((r) => r.target.isNotEmpty),
      (DnsSrvRecord r) => r.priority,
    );
    final result = <DnsSrvRecord>[];
    for (final p in byPriority.keys.toList()..sort()) {
      // Zero-weight records first (RFC 2782), then weighted draws.
      final pool = [...byPriority[p]!]
        ..sort((a, b) => a.weight.compareTo(b.weight));
      while (pool.isNotEmpty) {
        final total = pool.fold<int>(0, (s, r) => s + r.weight);
        final pick = total == 0 ? 0 : random.nextInt(total + 1);
        var running = 0;
        var index = pool.length - 1;
        for (var i = 0; i < pool.length; i++) {
          running += pool[i].weight;
          if (running >= pick) {
            index = i;
            break;
          }
        }
        result.add(pool.removeAt(index));
      }
    }
    return result;
  }

  /// Validates a hostname (ASCII LDH + underscore labels).
  static bool isValidHostname(String name) {
    try {
      _splitName(name);
      return true;
    } on ArgumentError {
      return false;
    }
  }

  static String _canonical(String name) =>
      _splitName(name).join('.').toLowerCase();

  static List<String> _splitName(String name) {
    final trimmed = name.endsWith('.')
        ? name.substring(0, name.length - 1)
        : name;
    if (trimmed.isEmpty || trimmed.length > 253) {
      throw ArgumentError.value(name, 'name', 'Invalid DNS name length');
    }
    final labels = trimmed.split('.');
    for (final l in labels) {
      if (l.isEmpty || l.length > 63 || !_labelPattern.hasMatch(l)) {
        throw ArgumentError.value(name, 'name', 'Invalid DNS label');
      }
    }
    return labels;
  }
}

/// Bounds-checked reader over a DNS packet.
class _Reader {
  final Uint8List _p;
  int offset = 0;

  _Reader(this._p);

  void _need(int n) {
    if (offset + n > _p.length) {
      throw const DnsFormatException('Unexpected end of packet');
    }
  }

  int u16() {
    _need(2);
    final v = (_p[offset] << 8) | _p[offset + 1];
    offset += 2;
    return v;
  }

  int u32() {
    final hi = u16();
    return (hi << 16) | u16();
  }

  /// Reads a (possibly compressed) domain name; advances [offset] past it.
  String name() {
    final labels = <String>[];
    var pos = offset;
    int? resumeAt;
    var jumps = 0;
    var length = 1; // terminating root label
    while (true) {
      if (pos >= _p.length) {
        throw const DnsFormatException('Name exceeds packet');
      }
      final len = _p[pos];
      if (len == 0) {
        pos += 1;
        break;
      }
      switch (len & 0xC0) {
        case 0xC0:
          if (pos + 1 >= _p.length) {
            throw const DnsFormatException('Truncated compression pointer');
          }
          final target = ((len & 0x3F) << 8) | _p[pos + 1];
          if (target < DnsSrvCodec._headerSize || target >= pos) {
            throw const DnsFormatException('Invalid compression pointer');
          }
          if (++jumps > DnsSrvCodec._maxPointerJumps) {
            throw const DnsFormatException('Too many compression pointers');
          }
          resumeAt ??= pos + 2;
          pos = target;
        case 0x00:
          if (pos + 1 + len > _p.length) {
            throw const DnsFormatException('Label exceeds packet');
          }
          length += len + 1;
          if (length > DnsSrvCodec._maxNameLength) {
            throw const DnsFormatException('Name too long');
          }
          final bytes = _p.sublist(pos + 1, pos + 1 + len);
          if (bytes.any((b) => b == 0x2E || b < 0x21 || b > 0x7E)) {
            throw const DnsFormatException('Invalid character in label');
          }
          labels.add(String.fromCharCodes(bytes));
          pos += 1 + len;
        default:
          throw const DnsFormatException('Unsupported label type');
      }
    }
    offset = resumeAt ?? pos;
    return labels.join('.');
  }
}

/// SRV resolver that queries one explicitly configured DNS server over UDP.
class UdpDnsSrvResolver implements DnsSrvResolver {
  /// DNS server to query (consumer-supplied; see library docs).
  final InternetAddress nameServer;
  final int port;
  final Duration timeout;
  final Random _random;

  UdpDnsSrvResolver({
    required this.nameServer,
    this.port = 53,
    this.timeout = const Duration(seconds: 5),
    Random? random,
  }) : _random = random ?? Random.secure();

  @override
  Future<List<DnsSrvRecord>> lookupSrv(String name) async {
    final id = _random.nextInt(0x10000);
    final query = DnsSrvCodec.buildQuery(name, id);
    final socket = await RawDatagramSocket.bind(
      nameServer.type == InternetAddressType.IPv6
          ? InternetAddress.anyIPv6
          : InternetAddress.anyIPv4,
      0,
    );
    final completer = Completer<List<DnsSrvRecord>>();
    const eq = ListEquality<int>();
    final sub = socket.listen((event) {
      if (event != RawSocketEvent.read || completer.isCompleted) return;
      final dg = socket.receive();
      if (dg == null) return;
      // Ignore datagrams not from the configured server or with foreign ID.
      if (dg.port != port ||
          !eq.equals(dg.address.rawAddress, nameServer.rawAddress) ||
          DnsSrvCodec.peekId(dg.data) != id) {
        return;
      }
      try {
        completer.complete(
          DnsSrvCodec.parseResponse(dg.data, expectedId: id, queryName: name),
        );
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    try {
      if (socket.send(query, nameServer, port) != query.length) {
        throw const DnsLookupException('Failed to send DNS query');
      }
      return await completer.future.timeout(
        timeout,
        onTimeout: () => throw const DnsLookupException('DNS query timed out'),
      );
    } finally {
      await sub.cancel();
      socket.close();
    }
  }
}
