/// Utility for generating EAS-compliant Device IDs.
library;

import 'dart:math';

/// Generates random Device IDs per MS-ASHTTP 2.2.1.1.1.2.3.
///
/// The generated ID must be persisted by the caller and reused
/// across all requests from the same device.
abstract final class DeviceIdGenerator {
  /// Generates a random DeviceId of [length] hex characters.
  ///
  /// Default length is 32 (maximum allowed by the spec).
  /// The caller is responsible for persisting the result.
  static String generate({int length = 32}) {
    RangeError.checkValueInInterval(length, 1, 32, 'length');
    final random = Random.secure();
    return List.generate(
      length,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
  }
}
