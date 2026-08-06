/// Mappls REST wrappers used across the app for India-accurate autosuggest
/// and reverse-geocoding.
///
/// The map *tiles* stay on `flutter_map` + OSM — this file is only about the
/// address strings. Nominatim's Indian coverage is weak (misses hyper-local
/// landmarks, PIN codes, sector-style addresses) so every place where the app
/// converts coordinates to an address label, or converts a typed query to a
/// coordinate, now goes through here.
///
/// Auth: the underlying `mappls_gl` package handles credentials via the
/// `.conf` / `.olf` files bundled in `android/app/`. Nothing to configure at
/// runtime — no keys, no headers.
library;

import 'package:flutter/foundation.dart';
import 'package:mappls_gl/mappls_gl.dart' as mp;

/// A single search suggestion — deliberately flat so screens don't need to
/// know about `ELocation` or any Mappls type.
class PlaceSuggestion {
  final String name;
  final String address;
  final double? lat;
  final double? lng;
  const PlaceSuggestion({
    required this.name,
    required this.address,
    this.lat,
    this.lng,
  });

  /// One-line label for a ListTile — falls back gracefully when one of the
  /// two Mappls fields comes back empty.
  String get display {
    if (name.isNotEmpty && address.isNotEmpty && address != name) {
      return '$name, $address';
    }
    return name.isNotEmpty ? name : address;
  }
}

/// Reverse-geocode result split into "exact" (poi/road/locality/city) and
/// "approx" (locality/city only) — the picker UI exposes both as user choice
/// so we compute them here in one pass.
class ReverseGeocodeResult {
  final String exact;
  final String approx;
  final String? city;
  final String? state;
  final String? pincode;
  const ReverseGeocodeResult({
    required this.exact,
    required this.approx,
    this.city,
    this.state,
    this.pincode,
  });
}

class MapplsService {
  const MapplsService();

  /// Places matching [query]. Passing [nearLat]/[nearLng] biases results
  /// toward the user's current viewport, which is a big deal for common
  /// queries like "medical store" — otherwise Mappls returns nationwide hits.
  Future<List<PlaceSuggestion>> autosuggest(
    String query, {
    double? nearLat,
    double? nearLng,
    int limit = 6,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    try {
      final resp = await mp.MapplsAutoSuggest(
        query: q,
        location: (nearLat != null && nearLng != null)
            ? mp.LatLng(nearLat, nearLng)
            : null,
      ).callAutoSuggest();

      final locations = resp?.suggestedLocations ?? const <mp.ELocation>[];
      final out = <PlaceSuggestion>[];
      for (final e in locations) {
        out.add(PlaceSuggestion(
          name: e.placeName ?? '',
          address: e.placeAddress ?? '',
          lat: e.latitude,
          lng: e.longitude,
        ));
        if (out.length >= limit) break;
      }
      return out;
    } catch (err, stack) {
      debugPrint('[mappls] autosuggest failed: $err\n$stack');
      return const [];
    }
  }

  /// Reverse-geocode a coordinate to an address. Returns null on failure so
  /// callers can show a coordinate-string fallback rather than crashing.
  Future<ReverseGeocodeResult?> reverseGeocode(double lat, double lng) async {
    try {
      final resp = await mp.MapplsReverseGeocode(
        location: mp.LatLng(lat, lng),
      ).callReverseGeocode();

      final place = (resp?.results ?? const []).isNotEmpty
          ? resp!.results!.first
          : null;
      if (place == null) return null;

      // Exact label — most specific first, falling back to formattedAddress.
      final exactParts = <String>[];
      if (_notBlank(place.poi)) exactParts.add(place.poi!);
      if (_notBlank(place.houseNumber)) exactParts.add(place.houseNumber!);
      if (_notBlank(place.street) && place.street != place.poi) {
        exactParts.add(place.street!);
      }
      if (_notBlank(place.subLocality) && place.subLocality != place.street) {
        exactParts.add(place.subLocality!);
      }
      if (_notBlank(place.locality) && place.locality != place.subLocality) {
        exactParts.add(place.locality!);
      }
      if (_notBlank(place.city) && place.city != place.locality) {
        exactParts.add(place.city!);
      }

      String exact = exactParts.isNotEmpty
          ? exactParts.join(', ')
          : (place.formattedAddress ?? '');
      if (exact.isEmpty) {
        exact = 'Lat ${lat.toStringAsFixed(4)}, Lng ${lng.toStringAsFixed(4)}';
      }

      // Approx label — locality + city, degrading gracefully.
      final approxParts = <String>[];
      if (_notBlank(place.locality)) approxParts.add(place.locality!);
      if (_notBlank(place.city) && place.city != place.locality) {
        approxParts.add(place.city!);
      }
      if (approxParts.isEmpty && _notBlank(place.city)) {
        approxParts.add(place.city!);
      }
      if (approxParts.isEmpty && _notBlank(place.state)) {
        approxParts.add(place.state!);
      }
      final approx = approxParts.isNotEmpty ? approxParts.join(', ') : exact;

      return ReverseGeocodeResult(
        exact: exact,
        approx: approx,
        city: place.city,
        state: place.state,
        pincode: place.pincode,
      );
    } catch (err, stack) {
      debugPrint('[mappls] reverseGeocode failed: $err\n$stack');
      return null;
    }
  }
}

bool _notBlank(String? s) => s != null && s.trim().isNotEmpty;

/// Single shared instance — the service is stateless so no need to build a
/// riverpod provider for it.
const mappls = MapplsService();
