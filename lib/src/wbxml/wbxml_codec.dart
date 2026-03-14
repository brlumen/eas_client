/// WBXML encoder and decoder for EAS protocol.
///
/// Implements WAP-192-WBXML specification as used by MS-ASWBXML.
/// Handles encoding Dart DOM → binary WBXML and decoding binary WBXML → Dart DOM.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'code_pages/code_page_registry.dart';
import 'wbxml_constants.dart';
import 'wbxml_document.dart';

/// Exception thrown when WBXML encoding/decoding fails.
class WbxmlException implements Exception {
  final String message;
  WbxmlException(this.message);

  @override
  String toString() => 'WbxmlException: $message';
}

// ---------------------------------------------------------------------------
// Decoder
// ---------------------------------------------------------------------------

/// Decodes binary WBXML data into a [WbxmlDocument].
class WbxmlDecoder {
  final CodePageRegistry _registry;

  /// Maximum allowed size for opaque data blocks (default 50 MB).
  final int maxOpaqueSize;

  /// Maximum allowed element nesting depth (default 50).
  final int maxDepth;

  WbxmlDecoder({
    CodePageRegistry? registry,
    this.maxOpaqueSize = 50 * 1024 * 1024,
    this.maxDepth = 50,
  }) : _registry = registry ?? CodePageRegistry.instance;

  /// Decode [data] bytes into a [WbxmlDocument].
  WbxmlDocument decode(Uint8List data) {
    final reader = _ByteReader(data);

    // Header
    final version = reader.readByte();
    final publicId = reader.readMbUint32();
    final charset = reader.readMbUint32();

    // String table
    final stringTableLength = reader.readMbUint32();
    final stringTable = stringTableLength > 0
        ? reader.readBytes(stringTableLength)
        : Uint8List(0);

    // Body
    int currentPage = 0;
    final root = _decodeElement(reader, currentPage, stringTable, 0);
    if (root == null) {
      throw WbxmlException('Empty WBXML document — no root element');
    }

    return WbxmlDocument(
      version: version,
      publicId: publicId,
      charset: charset,
      root: root,
    );
  }

  WbxmlElement? _decodeElement(
    _ByteReader reader,
    int currentPage,
    Uint8List stringTable,
    int depth,
  ) {
    if (depth > maxDepth) {
      throw WbxmlException(
        'Maximum nesting depth ($maxDepth) exceeded',
      );
    }

    while (reader.hasMore) {
      final token = reader.readByte();

      if (token == tokenSwitchPage) {
        currentPage = reader.readByte();
        continue;
      }

      if (token == tokenEnd) {
        return null; // End of parent element
      }

      // It's a tag token
      final hasAttributes = (token & tagHasAttributes) != 0;
      final hasContent = (token & tagHasContent) != 0;
      final tagToken = token & tagTokenMask;

      final codePage = _registry.getByIndex(currentPage);
      if (codePage == null) {
        throw WbxmlException('Unknown code page: $currentPage');
      }

      final tagName = codePage.tokenToTag[tagToken];
      if (tagName == null) {
        throw WbxmlException(
          'Unknown tag token 0x${tagToken.toRadixString(16)} '
          'in code page $currentPage (${codePage.namespace})',
        );
      }

      final element = WbxmlElement(
        namespace: codePage.namespace,
        tag: tagName,
        codePageIndex: currentPage,
      );

      // Skip attributes (EAS doesn't use them, but handle gracefully)
      if (hasAttributes) {
        _skipAttributes(reader);
      }

      if (hasContent) {
        _decodeContent(reader, element, currentPage, stringTable, depth);
      }

      return element;
    }

    return null;
  }

  void _decodeContent(
    _ByteReader reader,
    WbxmlElement element,
    int currentPage,
    Uint8List stringTable,
    int depth,
  ) {
    while (reader.hasMore) {
      final token = reader.peekByte();

      if (token == tokenEnd) {
        reader.readByte(); // consume END
        return;
      }

      if (token == tokenSwitchPage) {
        reader.readByte(); // consume SWITCH_PAGE
        currentPage = reader.readByte();
        continue;
      }

      if (token == tokenStrI) {
        reader.readByte(); // consume STR_I
        element.text = reader.readString();
        continue;
      }

      if (token == tokenOpaque) {
        reader.readByte(); // consume OPAQUE
        final length = reader.readMbUint32();
        if (length > maxOpaqueSize) {
          throw WbxmlException(
            'Opaque data size ($length) exceeds limit ($maxOpaqueSize)',
          );
        }
        element.opaque = reader.readBytes(length);
        continue;
      }

      if (token == tokenStrT) {
        reader.readByte(); // consume STR_T
        final offset = reader.readMbUint32();
        element.text = _readStringFromTable(stringTable, offset);
        continue;
      }

      // Must be a child element tag
      final child = _decodeElement(reader, currentPage, stringTable, depth + 1);
      if (child == null) {
        return; // Got END token
      }
      element.children.add(child);
    }
  }

  void _skipAttributes(_ByteReader reader) {
    // Read until END token (attributes end marker)
    while (reader.hasMore) {
      final b = reader.readByte();
      if (b == tokenEnd) return;
      // Skip attribute values (STR_I, etc.)
      if (b == tokenStrI) {
        reader.readString();
      }
    }
  }

  String _readStringFromTable(Uint8List table, int offset) {
    int end = offset;
    while (end < table.length && table[end] != 0) {
      end++;
    }
    return utf8.decode(table.sublist(offset, end));
  }
}

// ---------------------------------------------------------------------------
// Encoder
// ---------------------------------------------------------------------------

/// Encodes a [WbxmlDocument] into binary WBXML data.
class WbxmlEncoder {
  final CodePageRegistry _registry;

  WbxmlEncoder({CodePageRegistry? registry})
      : _registry = registry ?? CodePageRegistry.instance;

  /// Encode [document] to WBXML bytes.
  Uint8List encode(WbxmlDocument document) {
    final writer = _ByteWriter();

    // Header
    writer.writeByte(document.version);
    writer.writeMbUint32(document.publicId);
    writer.writeMbUint32(document.charset);
    writer.writeMbUint32(0); // string table length (we don't use string table)

    // Body
    int currentPage = -1; // Force first SWITCH_PAGE
    _encodeElement(writer, document.root, currentPage);

    return writer.toBytes();
  }

  int _encodeElement(_ByteWriter writer, WbxmlElement element, int currentPage) {
    final codePage = _registry.getByNamespace(element.namespace);
    if (codePage == null) {
      throw WbxmlException('Unknown namespace: ${element.namespace}');
    }

    final tagToken = codePage.tagToToken[element.tag];
    if (tagToken == null) {
      throw WbxmlException(
        'Unknown tag "${element.tag}" in namespace "${element.namespace}"',
      );
    }

    // Switch code page if needed
    if (codePage.pageIndex != currentPage) {
      writer.writeByte(tokenSwitchPage);
      writer.writeByte(codePage.pageIndex);
      currentPage = codePage.pageIndex;
    }

    // Build tag byte
    int tagByte = tagToken;
    if (element.hasContent) {
      tagByte |= tagHasContent;
    }
    writer.writeByte(tagByte);

    // Content
    if (element.hasContent) {
      currentPage = _encodeContent(writer, element, currentPage);
      writer.writeByte(tokenEnd);
    }

    return currentPage;
  }

  int _encodeContent(
    _ByteWriter writer,
    WbxmlElement element,
    int currentPage,
  ) {
    if (element.text != null) {
      writer.writeByte(tokenStrI);
      writer.writeString(element.text!);
    }

    if (element.opaque != null) {
      writer.writeByte(tokenOpaque);
      writer.writeMbUint32(element.opaque!.length);
      writer.writeBytes(element.opaque!);
    }

    for (final child in element.children) {
      currentPage = _encodeElement(writer, child, currentPage);
    }

    return currentPage;
  }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

class _ByteReader {
  final Uint8List _data;
  int _offset = 0;

  _ByteReader(this._data);

  bool get hasMore => _offset < _data.length;

  int readByte() {
    if (_offset >= _data.length) {
      throw WbxmlException('Unexpected end of data at offset $_offset');
    }
    return _data[_offset++];
  }

  int peekByte() {
    if (_offset >= _data.length) {
      throw WbxmlException('Unexpected end of data at offset $_offset');
    }
    return _data[_offset];
  }

  /// Read a multi-byte unsigned integer (mb_u_int32).
  /// Each byte uses 7 bits for value, bit 7 = continuation.
  /// Maximum 5 bytes per WAP-192-WBXML (sufficient for uint32).
  int readMbUint32() {
    int result = 0;
    int bytesRead = 0;
    int b;
    do {
      b = readByte();
      result = (result << 7) | (b & 0x7F);
      bytesRead++;
      if (bytesRead > 5) {
        throw WbxmlException(
          'mb_u_int32 exceeds 5 bytes at offset $_offset',
        );
      }
    } while ((b & 0x80) != 0);
    return result;
  }

  /// Read a NULL-terminated UTF-8 string.
  String readString() {
    final start = _offset;
    while (_offset < _data.length && _data[_offset] != 0) {
      _offset++;
    }
    final str = utf8.decode(_data.sublist(start, _offset));
    if (_offset < _data.length) {
      _offset++; // skip NULL terminator
    }
    return str;
  }

  /// Read [length] bytes.
  Uint8List readBytes(int length) {
    if (_offset + length > _data.length) {
      throw WbxmlException(
        'Cannot read $length bytes at offset $_offset '
        '(data length: ${_data.length})',
      );
    }
    final bytes = _data.sublist(_offset, _offset + length);
    _offset += length;
    return bytes;
  }
}

class _ByteWriter {
  final BytesBuilder _builder = BytesBuilder();

  void writeByte(int byte) {
    _builder.addByte(byte);
  }

  void writeBytes(Uint8List bytes) {
    _builder.add(bytes);
  }

  /// Write a multi-byte unsigned integer (mb_u_int32).
  void writeMbUint32(int value) {
    if (value == 0) {
      _builder.addByte(0);
      return;
    }

    // Collect 7-bit groups
    final bytes = <int>[];
    var v = value;
    while (v > 0) {
      bytes.insert(0, v & 0x7F);
      v >>= 7;
    }

    // Set continuation bits on all but last byte
    for (int i = 0; i < bytes.length - 1; i++) {
      bytes[i] |= 0x80;
    }

    for (final b in bytes) {
      _builder.addByte(b);
    }
  }

  /// Write a NULL-terminated UTF-8 string.
  void writeString(String str) {
    _builder.add(utf8.encode(str));
    _builder.addByte(0); // NULL terminator
  }

  Uint8List toBytes() {
    return _builder.toBytes();
  }
}
