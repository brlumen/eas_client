/// Raw HTTP/1.1 encoding of EAS requests and parsing of responses.
///
/// Used to run a command over a socket the consumer manages itself (e.g.
/// a TLS stream tunneled through a proxy that keeps a Ping open while the
/// device sleeps).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'eas_http_client.dart';

/// A fully prepared EAS HTTP request: the same method, URI, headers and
/// body [EasHttpClient] sends.
class EasHttpRequest {
  /// EAS command name (e.g. `Ping`).
  final String command;

  /// HTTP method (`POST`, `OPTIONS`).
  final String method;
  final Uri uri;

  /// Header names as sent (`Content-Type`, `MS-ASProtocolVersion`, ...).
  /// Does not contain `Host`, `Content-Length` or `Connection`.
  final Map<String, String> headers;

  /// Request body; `null` sends none (`Content-Length: 0`).
  final Uint8List? body;

  const EasHttpRequest({
    required this.command,
    required this.method,
    required this.uri,
    required this.headers,
    this.body,
  });

  /// The request as HTTP/1.1 bytes: request line with origin-form target,
  /// `Host`, [headers], `Content-Length`, `Connection: keep-alive`, blank
  /// line, body. No `Expect` header is sent.
  ///
  /// Throws [ArgumentError] if a header contains CR, LF or non-ASCII
  /// characters (header injection).
  Uint8List toHttp11Bytes() {
    final target = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
    final all = <String, String>{
      'Host': uri.authority,
      ...headers,
      'Content-Length': '${body?.length ?? 0}',
      'Connection': 'keep-alive',
    };
    final head = StringBuffer('$method $target HTTP/1.1\r\n');
    for (final e in all.entries) {
      if (!_headerPattern.hasMatch(e.key) ||
          !_headerValuePattern.hasMatch(e.value)) {
        throw ArgumentError.value(e.key, 'headers', 'Invalid header');
      }
      head.write('${e.key}: ${e.value}\r\n');
    }
    head.write('\r\n');
    return (BytesBuilder(copy: false)
          ..add(ascii.encode(head.toString()))
          ..add(body ?? const <int>[]))
        .toBytes();
  }

  static final _headerPattern = RegExp(r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$");
  static final _headerValuePattern = RegExp(r'^[\x20-\x7e]*$');
}

/// A parsed raw HTTP response and the number of bytes it occupied.
typedef RawHttpParseResult = ({EasResponse response, int length});

/// Parser of raw HTTP/1.1 responses (status line, headers,
/// `Content-Length` / chunked bodies).
abstract final class EasRawHttpParser {
  static const _crlf = [13, 10];
  static const _headerEnd = [13, 10, 13, 10];

  /// Maximum size of the response head (status line + headers).
  static const maxHeadSize = 64 * 1024;

  /// Parse the first complete response in [bytes]; `null` if more bytes
  /// are needed. Interim (1xx) responses are skipped.
  ///
  /// A body without `Content-Length` or chunked encoding extends to the
  /// end of [bytes] only when [endOfStream] is `true` (the connection was
  /// closed); otherwise `null` is returned.
  ///
  /// Headers are returned with lower-case names; repeated headers are
  /// joined with `, `. Throws [FormatException] on a malformed response
  /// and [EasResponseTooLargeException] if the body exceeds
  /// [maxBodySize].
  static RawHttpParseResult? tryParse(
    Uint8List bytes, {
    bool endOfStream = false,
    int maxBodySize = 25 * 1024 * 1024,
  }) {
    var offset = 0;
    while (true) {
      final headEnd = _indexOf(bytes, _headerEnd, offset);
      if (headEnd < 0) {
        if (bytes.length - offset > maxHeadSize) {
          throw const FormatException('HTTP response head too large');
        }
        if (endOfStream) {
          throw const FormatException('Incomplete HTTP response head');
        }
        return null;
      }
      final lines = latin1
          .decode(Uint8List.sublistView(bytes, offset, headEnd))
          .split('\r\n');
      final status = _parseStatusLine(lines.first);
      final headers = <String, String>{};
      for (final line in lines.skip(1)) {
        final colon = line.indexOf(':');
        if (colon <= 0) throw FormatException('Malformed header', line);
        final name = line.substring(0, colon).trim().toLowerCase();
        final value = line.substring(colon + 1).trim();
        headers.update(name, (v) => '$v, $value', ifAbsent: () => value);
      }
      final bodyStart = headEnd + _headerEnd.length;
      if (status >= 100 && status < 200) {
        offset = bodyStart;
        continue;
      }

      final body = _readBody(
        bytes,
        bodyStart,
        headers,
        status,
        endOfStream: endOfStream,
        maxBodySize: maxBodySize,
      );
      if (body == null) return null;
      return (
        response: EasResponse(
          statusCode: status,
          headers: headers,
          body: body.data,
        ),
        length: body.end,
      );
    }
  }

  /// Parse a complete response; throws [FormatException] if [bytes] do
  /// not contain one.
  static EasResponse parse(
    Uint8List bytes, {
    int maxBodySize = 25 * 1024 * 1024,
  }) {
    final result = tryParse(bytes, endOfStream: true, maxBodySize: maxBodySize);
    if (result == null) {
      throw const FormatException('Incomplete HTTP response');
    }
    return result.response;
  }

  static int _parseStatusLine(String line) {
    final m = RegExp(r'^HTTP/1\.[01] (\d{3})(?: .*)?$').firstMatch(line);
    if (m == null) throw FormatException('Malformed status line', line);
    return int.parse(m.group(1)!);
  }

  static ({Uint8List data, int end})? _readBody(
    Uint8List bytes,
    int start,
    Map<String, String> headers,
    int status, {
    required bool endOfStream,
    required int maxBodySize,
  }) {
    if (status == 204 || status == 304) {
      return (data: Uint8List(0), end: start);
    }
    final encoding = headers['transfer-encoding']?.toLowerCase();
    if (encoding != null && encoding.split(',').last.trim() == 'chunked') {
      return _readChunked(bytes, start, maxBodySize);
    }
    final lengthHeader = headers['content-length'];
    if (lengthHeader != null) {
      final length = int.tryParse(lengthHeader);
      if (length == null || length < 0) {
        throw FormatException('Invalid Content-Length', lengthHeader);
      }
      if (length > maxBodySize) {
        throw EasResponseTooLargeException(length, maxBodySize);
      }
      if (bytes.length - start < length) {
        if (endOfStream) {
          throw const FormatException('Truncated HTTP response body');
        }
        return null;
      }
      return (
        data: Uint8List.fromList(bytes.sublist(start, start + length)),
        end: start + length,
      );
    }
    if (!endOfStream) return null;
    if (bytes.length - start > maxBodySize) {
      throw EasResponseTooLargeException(bytes.length - start, maxBodySize);
    }
    return (data: Uint8List.fromList(bytes.sublist(start)), end: bytes.length);
  }

  static ({Uint8List data, int end})? _readChunked(
    Uint8List bytes,
    int start,
    int maxBodySize,
  ) {
    final out = BytesBuilder();
    var pos = start;
    while (true) {
      final lineEnd = _indexOf(bytes, _crlf, pos);
      if (lineEnd < 0) return null;
      final sizeText = latin1
          .decode(Uint8List.sublistView(bytes, pos, lineEnd))
          .split(';')
          .first
          .trim();
      final size = int.tryParse(sizeText, radix: 16);
      if (size == null || size < 0) {
        throw FormatException('Invalid chunk size', sizeText);
      }
      pos = lineEnd + 2;
      if (size == 0) {
        // Trailer section: header lines until an empty line.
        while (true) {
          final end = _indexOf(bytes, _crlf, pos);
          if (end < 0) return null;
          final empty = end == pos;
          pos = end + 2;
          if (empty) return (data: out.toBytes(), end: pos);
        }
      }
      if (out.length + size > maxBodySize) {
        throw EasResponseTooLargeException(out.length + size, maxBodySize);
      }
      if (bytes.length < pos + size + 2) return null;
      out.add(Uint8List.sublistView(bytes, pos, pos + size));
      pos += size;
      if (bytes[pos] != 13 || bytes[pos + 1] != 10) {
        throw const FormatException('Missing CRLF after chunk');
      }
      pos += 2;
    }
  }

  static int _indexOf(Uint8List bytes, List<int> pattern, int from) {
    outer:
    for (var i = from; i <= bytes.length - pattern.length; i++) {
      for (var j = 0; j < pattern.length; j++) {
        if (bytes[i + j] != pattern[j]) continue outer;
      }
      return i;
    }
    return -1;
  }
}
