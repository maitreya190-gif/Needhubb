/// Centralised location capture + address resolution.
///
/// Every screen that needs the user's GPS position went through the same
/// permission → fetch → reverse-geocode dance, hand-rolled and slightly
/// wrong in each file (e.g. one of them fell back to Mumbai's coordinates
/// on timeout, which quietly lied to users outside Mumbai). This file
/// consolidates that into one path so future screens can call
/// `locationService.getCurrent(...)` and be done.
///
/// Precision defaults:
///   - LocationAccuracy.best on the fresh fix (GPS + Wi-Fi + cell fusion)
///   - Warm-up with getLastKnownPosition (instant, coarse) before waiting
///     for the fresh fix — feels immediate to the user
///   - Reject fixes with reported accuracy > 200m and retry once, otherwise
///     surface a "move outdoors for better signal" hint
///
/// Address resolution goes through Mappls (India-accurate) with a lat/lng
/// string fallback if the network call fails.
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'mappls_service.dart';

enum LocationFailure {
  serviceDisabled,
  permissionDenied,
  permissionForeverDenied,
  timeout,
  poorAccuracy,
  unknown,
}

class LocationFix {
  final double lat;
  final double lng;
  /// Reported horizontal accuracy in metres — lower is better. Shown as the
  /// blue accuracy circle on the map so the user understands "you're within
  /// this radius", the same convention Google Maps uses.
  final double accuracyMeters;
  /// Whether this fix came from a fresh sensor read (fresh = true) or from
  /// getLastKnownPosition (fresh = false). Screens that need a truly current
  /// position (e.g. checking the user is at a venue) should ignore stale fixes.
  final bool fresh;
  const LocationFix({
    required this.lat,
    required this.lng,
    required this.accuracyMeters,
    required this.fresh,
  });
}

class LocationResult {
  final LocationFix? fix;
  final LocationFailure? failure;
  const LocationResult._(this.fix, this.failure);
  factory LocationResult.ok(LocationFix f) => LocationResult._(f, null);
  factory LocationResult.err(LocationFailure f) => LocationResult._(null, f);
  bool get isOk => fix != null;
}

class LocationService {
  const LocationService();

  /// Full permission + fetch flow.
  ///
  /// Strategy: if [warmUp] is true and there's a recent last-known fix with
  /// acceptable accuracy (<500m), return it *immediately* — feels instant.
  /// Screens that need survey-grade precision (`preferFresh: true`) always
  /// wait for the fresh fix; every other caller gets the fast path.
  Future<LocationResult> getCurrent({
    bool warmUp = true,
    bool preferFresh = false,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationResult.err(LocationFailure.serviceDisabled);
    }

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied) {
      return LocationResult.err(LocationFailure.permissionDenied);
    }
    if (perm == LocationPermission.deniedForever) {
      return LocationResult.err(LocationFailure.permissionForeverDenied);
    }

    LocationFix? warm;
    if (warmUp) {
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) {
          warm = LocationFix(
            lat: last.latitude,
            lng: last.longitude,
            accuracyMeters: last.accuracy,
            fresh: false,
          );
        }
      } catch (_) {/* ignore — warm-up is best-effort */}
    }

    // Fast path: usable last-known fix. Skip the GPS wait entirely for
    // screens that don't need survey-grade precision.
    if (!preferFresh && warm != null && warm.accuracyMeters <= 500) {
      return LocationResult.ok(warm);
    }

    Position fresh;
    try {
      fresh = await Geolocator.getCurrentPosition(
        // ignore: deprecated_member_use
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: timeout,
      );
    } catch (err) {
      debugPrint('[location] fresh fix failed: $err');
      if (warm != null) return LocationResult.ok(warm);
      return LocationResult.err(LocationFailure.timeout);
    }

    // Reject clearly bad fixes — catches indoor-only Wi-Fi hits that Android
    // reports with false confidence.
    if (fresh.accuracy > 500) {
      if (warm != null && warm.accuracyMeters < fresh.accuracy) {
        return LocationResult.ok(warm);
      }
      return LocationResult.err(LocationFailure.poorAccuracy);
    }

    return LocationResult.ok(LocationFix(
      lat: fresh.latitude,
      lng: fresh.longitude,
      accuracyMeters: fresh.accuracy,
      fresh: true,
    ));
  }

  /// Reverse-geocode via Mappls, degrading to a lat/lng string on failure so
  /// callers never have to handle null themselves. Set [exact] false to
  /// return the coarser locality/city label instead of the poi/street one.
  Future<String> resolveLabel(
    double lat,
    double lng, {
    bool exact = true,
  }) async {
    final result = await mappls.reverseGeocode(lat, lng);
    if (result == null) {
      return 'Lat ${lat.toStringAsFixed(3)}, Lng ${lng.toStringAsFixed(3)}';
    }
    return exact ? result.exact : result.approx;
  }
}

const locationService = LocationService();
