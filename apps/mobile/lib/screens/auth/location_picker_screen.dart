import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import '../../services/mappls_service.dart';
import '../../theme/tokens.dart';

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

  double get latitude => lat;
  double get longitude => lng;
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  late final MapController _mapController;
  LatLng _center = const LatLng(12.9716, 77.5946);
  bool _exactLocation = true;
  String _currentLabel = 'Locating...';
  bool _isGeocoding = false;
  Timer? _debounce;

  final _searchController = TextEditingController();
  List<PlaceSuggestion> _searchResults = const [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    if (widget.initial != null) _center = widget.initial!;
    _reverseGeocode(_center);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _mapController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  String _exactLabel = '';
  String _approxLabel = '';

  Future<void> _reverseGeocode(LatLng pos) async {
    setState(() => _isGeocoding = true);
    final result = await mappls.reverseGeocode(pos.latitude, pos.longitude);
    if (!mounted) return;
    setState(() {
      _isGeocoding = false;
      if (result != null) {
        _exactLabel = result.exact;
        _approxLabel = '${result.approx} (2km Radius)';
        _currentLabel = _exactLocation ? _exactLabel : _approxLabel;
      } else {
        _currentLabel =
            'Lat ${pos.latitude.toStringAsFixed(3)}, Lon ${pos.longitude.toStringAsFixed(3)}';
      }
    });
  }

  void _onPositionChanged(MapCamera position, bool hasGesture) {
    setState(() => _center = position.center);
    if (hasGesture) {
      if (_debounce?.isActive ?? false) _debounce!.cancel();
      _debounce = Timer(const Duration(milliseconds: 800), () {
        _reverseGeocode(_center);
      });
    }
  }

  Future<void> _searchLocation(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _searchResults = const []);
      return;
    }
    setState(() => _isSearching = true);
    // Bias autosuggest to the current map center so common queries
    // ("chemist", "atm") return the nearest hits, not nationwide chains.
    final results = await mappls.autosuggest(
      query,
      nearLat: _center.latitude,
      nearLng: _center.longitude,
    );
    if (!mounted) return;
    setState(() {
      _isSearching = false;
      _searchResults = results;
    });
  }

  void _confirm() {
    final label = _exactLocation ? (_exactLabel.isNotEmpty ? _exactLabel : _currentLabel) : (_approxLabel.isNotEmpty ? _approxLabel : '$_currentLabel (Approx)');
    final result = LocationPickResult(
      lat: _center.latitude,
      lng: _center.longitude,
      label: label,
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
              onPositionChanged: _onPositionChanged,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.needhub.needhub',
              ),
            ],
          ),
          const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.location_pin, color: NeedHubTokens.clay, size: 44),
                SizedBox(height: 22),
              ],
            ),
          ),
          
          // Search Bar Overlay
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: t.paper,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: TextField(
                    controller: _searchController,
                    onSubmitted: _searchLocation,
                    style: GoogleFonts.hankenGrotesk(color: t.ink),
                    decoration: InputDecoration(
                      hintText: 'Search for an area...',
                      hintStyle: GoogleFonts.hankenGrotesk(color: t.muted),
                      prefixIcon: Icon(Icons.search, color: t.muted),
                      suffixIcon: _isSearching
                          ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                          : IconButton(
                              icon: Icon(Icons.clear, color: t.muted),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchResults = []);
                              },
                            ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                ),
                if (_searchResults.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      color: t.paper,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, 4)),
                      ],
                    ),
                    constraints: const BoxConstraints(maxHeight: 250),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _searchResults.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: t.rail),
                      itemBuilder: (context, index) {
                        final item = _searchResults[index];
                        return ListTile(
                          title: Text(
                            item.display,
                            style: GoogleFonts.hankenGrotesk(fontSize: 14, color: t.ink),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () {
                            final lat = item.lat;
                            final lng = item.lng;
                            if (lat == null || lng == null) return;
                            final newPos = LatLng(lat, lng);
                            _mapController.move(newPos, 14);
                            setState(() {
                              _center = newPos;
                              _searchResults = const [];
                              _searchController.clear();
                            });
                            _reverseGeocode(newPos);
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          // Coordinate label at the bottom
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined, color: NeedHubTokens.clay, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _isGeocoding ? 'Locating...' : _currentLabel,
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: t.ink,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment<bool>(
                              value: true,
                              label: Text('Exact'),
                              icon: Icon(Icons.my_location, size: 16),
                            ),
                            ButtonSegment<bool>(
                              value: false,
                              label: Text('2km Radius'),
                              icon: Icon(Icons.blur_circular, size: 16),
                            ),
                          ],
                          selected: {_exactLocation},
                          onSelectionChanged: (Set<bool> newSelection) {
                            setState(() {
                              _exactLocation = newSelection.first;
                              if (_exactLabel.isNotEmpty && _approxLabel.isNotEmpty) {
                                _currentLabel = _exactLocation ? _exactLabel : _approxLabel;
                              }
                            });
                          },
                          style: ButtonStyle(
                            backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
                              if (states.contains(WidgetState.selected)) {
                                return NeedHubTokens.clay.withOpacity(0.15);
                              }
                              return Colors.transparent;
                            }),
                            foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
                              if (states.contains(WidgetState.selected)) {
                                return NeedHubTokens.clay;
                              }
                              return t.muted;
                            }),
                            textStyle: WidgetStateProperty.all(
                              GoogleFonts.hankenGrotesk(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed: _confirm,
                        style: TextButton.styleFrom(
                          backgroundColor: NeedHubTokens.clay,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                          'Confirm',
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
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

