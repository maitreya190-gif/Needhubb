import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import '../../theme/tokens.dart';

/// Full-screen map picker. Push this screen and await the result:
///   final result = await Navigator.push<LocationPickResult>(...)
/// Returns null if the user cancels.
class LocationPickerScreen extends StatefulWidget {
  final LatLng? initial;

  const LocationPickerScreen({super.key, this.initial});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class LocationPickResult {
  final double lat;
  final double lng;
  final String label;
  const LocationPickResult({required this.lat, required this.lng, required this.label});
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  late final MapController _mapController;
  LatLng _center = const LatLng(12.9716, 77.5946); // Bangalore default

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    if (widget.initial != null) _center = widget.initial!;
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _confirm() {
    final result = LocationPickResult(
      lat: _center.latitude,
      lng: _center.longitude,
      label:
          'Lat ${_center.latitude.toStringAsFixed(3)}, Lon ${_center.longitude.toStringAsFixed(3)}',
    );
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(
        backgroundColor: t.paper,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: t.ink),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Pick your location',
          style: GoogleFonts.bricolageGrotesque(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: t.ink,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: _confirm,
              child: Text(
                'Confirm',
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: NeedHubTokens.clay,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 13,
              onPositionChanged: (position, _) {
                if (position.center != null) {
                  setState(() => _center = position.center!);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.needhub.needhub',
              ),
            ],
          ),

          // Fixed crosshair pin in the center
          const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.location_pin, color: NeedHubTokens.clay, size: 44),
                SizedBox(height: 22), // offset so pin tip sits at exact center
              ],
            ),
          ),

          // Coordinate label at the bottom
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: t.paper,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(Icons.location_on_outlined,
                      color: NeedHubTokens.clay, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Lat ${_center.latitude.toStringAsFixed(4)},  '
                      'Lon ${_center.longitude.toStringAsFixed(4)}',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: t.ink,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _confirm,
                    style: TextButton.styleFrom(
                      backgroundColor: NeedHubTokens.clay,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'Use this',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
