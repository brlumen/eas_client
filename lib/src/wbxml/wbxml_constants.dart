/// WBXML global tokens and constants per WAP-192-WBXML specification.
///
/// Reference: MS-ASWBXML section 2.2
library;

/// WBXML version 1.3 (used by EAS).
const int wbxmlVersion13 = 0x03;

/// Public identifier: Unknown / string table.
const int wbxmlPublicIdUnknown = 0x01;

/// Charset UTF-8 (IANA MIBenum 106).
const int wbxmlCharsetUtf8 = 0x6A;

// --- Global tokens ---

/// Switch to code page (followed by page index byte).
const int tokenSwitchPage = 0x00;

/// End of element.
const int tokenEnd = 0x01;

/// Inline string (NULL-terminated UTF-8).
const int tokenStrI = 0x03;

/// Opaque data (followed by mb_uint32 length, then raw bytes).
const int tokenOpaque = 0xC3;

/// String table reference (followed by mb_uint32 offset).
const int tokenStrT = 0x83;

// --- Tag bit masks ---

/// Bit 6: element has attributes.
const int tagHasAttributes = 0x80;

/// Bit 7: element has content (children or text).
const int tagHasContent = 0x40;

/// Mask to extract tag token (bits 0-5).
const int tagTokenMask = 0x3F;

/// Minimum tag token value (0x05). Values 0x00-0x04 are reserved.
const int tagTokenMin = 0x05;
