/// AirSyncBase Location (MS-ASAIRS 2.2.2.28, EAS 16.0+).
library;

import '../wbxml/wbxml_document.dart';
import 'wbxml_helpers.dart';

/// Structured event location (`airsyncbase:Location`).
class EasLocation {
  final String? displayName;
  final String? annotation;
  final String? street;
  final String? city;
  final String? state;
  final String? country;
  final String? postalCode;
  final double? latitude;
  final double? longitude;
  final double? accuracy;
  final double? altitude;
  final double? altitudeAccuracy;
  final String? locationUri;

  const EasLocation({
    this.displayName,
    this.annotation,
    this.street,
    this.city,
    this.state,
    this.country,
    this.postalCode,
    this.latitude,
    this.longitude,
    this.accuracy,
    this.altitude,
    this.altitudeAccuracy,
    this.locationUri,
  });

  factory EasLocation.fromElement(WbxmlElement el) {
    String? s(String tag) => el.str('AirSyncBase', tag);
    double? d(String tag) => el.dbl('AirSyncBase', tag);
    return EasLocation(
      displayName: s('DisplayName'),
      annotation: s('Annotation'),
      street: s('Street'),
      city: s('City'),
      state: s('State'),
      country: s('Country'),
      postalCode: s('PostalCode'),
      latitude: d('Latitude'),
      longitude: d('Longitude'),
      accuracy: d('Accuracy'),
      altitude: d('Altitude'),
      altitudeAccuracy: d('AltitudeAccuracy'),
      locationUri: s('LocationUri'),
    );
  }

  /// `airsyncbase:Location` of [parent], or `null`.
  static EasLocation? of(WbxmlElement parent) {
    final el = parent.findChild('AirSyncBase', 'Location');
    return el == null ? null : EasLocation.fromElement(el);
  }

  /// `airsyncbase:Location` element. An all-null location produces an
  /// empty element, which removes the location from the item.
  WbxmlElement toElement() {
    final c = <WbxmlElement>[]
      ..addText('AirSyncBase', 'DisplayName', displayName)
      ..addText('AirSyncBase', 'Annotation', annotation)
      ..addText('AirSyncBase', 'Street', street)
      ..addText('AirSyncBase', 'City', city)
      ..addText('AirSyncBase', 'State', state)
      ..addText('AirSyncBase', 'Country', country)
      ..addText('AirSyncBase', 'PostalCode', postalCode)
      ..addText('AirSyncBase', 'Latitude', latitude)
      ..addText('AirSyncBase', 'Longitude', longitude)
      ..addText('AirSyncBase', 'Accuracy', accuracy)
      ..addText('AirSyncBase', 'Altitude', altitude)
      ..addText('AirSyncBase', 'AltitudeAccuracy', altitudeAccuracy)
      ..addText('AirSyncBase', 'LocationUri', locationUri);
    return containerEl('AirSyncBase', 'Location', c);
  }

  @override
  String toString() => 'EasLocation($displayName)';
}
