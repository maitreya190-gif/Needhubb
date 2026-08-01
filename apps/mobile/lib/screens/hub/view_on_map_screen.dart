import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import '../../models/need.dart';
import '../../services/social_providers.dart';
import '../../services/profiles_api.dart';
import '../../theme/tokens.dart';
import '../needs/need_detail_screen.dart';

class ViewOnMapScreen extends ConsumerStatefulWidget {
  const ViewOnMapScreen({super.key});

  @override
  ConsumerState<ViewOnMapScreen> createState() => _ViewOnMapScreenState();
}

class _ViewOnMapScreenState extends ConsumerState<ViewOnMapScreen> {
  final MapController _mapController = MapController();
  final PageController _pageController = PageController(viewportFraction: 0.85);
  final TextEditingController _searchController = TextEditingController();
  final Dio _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)));

  LatLng _center = const LatLng(12.9716, 77.5946); // Default Bangalore/Indiranagar
  double _radius = 5.0; // in km
  List<Need> _needs = [];
  bool _loading = false;
  Timer? _fetchDebounce;
  Timer? _searchDebounce;

  Need? _selectedNeed;
  List<dynamic> _searchResults = [];
  bool _isSearching = false;
  bool _showSearchResults = false;

  @override
  void initState() {
    super.initState();
    // Start at current user location if available
    final me = myProfileNotifier.value;
    if (me != null && me.lat != null && me.lng != null) {
      _center = LatLng(me.lat!, me.lng!);
    }
    _fetchNeeds();
  }

  @override
  void dispose() {
    _fetchDebounce?.cancel();
    _searchDebounce?.cancel();
    _mapController.dispose();
    _pageController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // Debounced needs fetch to prevent UI lag on map interaction/slider change
  void _triggerFetchDebounce() {
    if (_fetchDebounce?.isActive ?? false) _fetchDebounce!.cancel();
    _fetchDebounce = Timer(const Duration(milliseconds: 400), () {
      _fetchNeeds();
    });
  }

  Future<void> _fetchNeeds() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final api = ref.read(needsApiProvider);
      final result = await api.feed(
        lat: _center.latitude,
        lng: _center.longitude,
        distanceKm: _radius,
        sort: 'distance',
        take: 100,
      );

      if (mounted) {
        setState(() {
          // Filter out needs without lat/lng coordinates
          _needs = result.needs.where((n) => n.lat != null && n.lng != null).toList();
          _loading = false;
          _selectedNeed = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load local needs')),
        );
      }
    }
  }

  Future<void> _searchLocation(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _showSearchResults = false;
      });
      return;
    }

    setState(() => _isSearching = true);
    try {
      final res = await _dio.get(
        'https://nominatim.openstreetmap.org/search',
        queryParameters: {
          'format': 'json',
          'q': query,
          'limit': 5,
        },
        options: Options(headers: {'User-Agent': 'NeedhubApp/1.0'}),
      );

      if (mounted && res.data != null) {
        setState(() {
          _searchResults = res.data as List<dynamic>;
          _showSearchResults = true;
        });
      }
    } catch (e) {
      debugPrint('Search error: $e');
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _onLocationSuggestionTap(dynamic result) {
    final lat = double.tryParse(result['lat'] ?? '');
    final lon = double.tryParse(result['lon'] ?? '');
    if (lat != null && lon != null) {
      final newCenter = LatLng(lat, lon);
      setState(() {
        _center = newCenter;
        _showSearchResults = false;
        _searchResults = [];
        _searchController.text = result['display_name'] ?? '';
      });
      _mapController.move(newCenter, 13.5);
      _fetchNeeds();
    }
    FocusScope.of(context).unfocus();
  }

  void _selectNeed(Need need) {
    setState(() {
      _selectedNeed = need;
    });

    // Find index of selected need in the list to scroll PageView
    final idx = _needs.indexWhere((n) => n.id == need.id);
    if (idx != -1) {
      _pageController.animateToPage(
        idx,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }

    if (need.lat != null && need.lng != null) {
      _mapController.move(LatLng(need.lat!, need.lng!), _mapController.camera.zoom);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    // Build markers list
    final List<Marker> markers = [
      // 1. Center / Search Origin Pin
      Marker(
        point: _center,
        width: 60,
        height: 60,
        alignment: Alignment.center,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: NeedHubTokens.clay.withValues(alpha: 0.2),
            border: Border.all(color: NeedHubTokens.clay, width: 2),
          ),
          child: const Center(
            child: Icon(
              Icons.location_searching_rounded,
              color: NeedHubTokens.clay,
              size: 22,
            ),
          ),
        ),
      ),
      // 2. Needs Pins
      ..._needs.map((n) {
        final isSelected = _selectedNeed?.id == n.id;
        final color = n.category == 'earn' ? NeedHubTokens.ochre : NeedHubTokens.forest;

        return Marker(
          point: LatLng(n.lat!, n.lng!),
          width: isSelected ? 48 : 38,
          height: isSelected ? 48 : 38,
          alignment: Alignment.center,
          child: GestureDetector(
            onTap: () => _selectNeed(n),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(
                  color: color,
                  width: isSelected ? 4 : 2,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 6,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Center(
                child: Icon(
                  n.category == 'earn' ? Icons.currency_rupee_rounded : Icons.handshake_rounded,
                  color: color,
                  size: isSelected ? 22 : 18,
                ),
              ),
            ),
          ),
        );
      }),
    ];

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(
        backgroundColor: t.paper,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: t.ink),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'View on Map',
          style: GoogleFonts.bricolageGrotesque(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: t.ink,
          ),
        ),
      ),
      body: Stack(
        children: [
          // 1. The Map View
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 13.5,
              maxZoom: 18,
              minZoom: 9,
              onTap: (tapPosition, point) {
                setState(() {
                  _center = point;
                  _selectedNeed = null;
                });
                _triggerFetchDebounce();
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.needhub.needhub',
              ),
              // Search Radius Circle boundary overlay
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: _center,
                    radius: _radius * 1000, // convert km to meters
                    useRadiusInMeter: true,
                    color: NeedHubTokens.clay.withValues(alpha: 0.08),
                    borderColor: NeedHubTokens.clay.withValues(alpha: 0.4),
                    borderStrokeWidth: 1.5,
                  ),
                ],
              ),
              MarkerLayer(markers: markers),
            ],
          ),

          // 2. Search overlay UI
          Positioned(
            top: 14,
            left: 14,
            right: 14,
            child: Column(
              children: [
                Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: t.paper,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                    border: Border.all(color: t.rail, width: 1),
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: GoogleFonts.hankenGrotesk(color: t.ink),
                    onChanged: (val) {
                      if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
                      _searchDebounce = Timer(const Duration(milliseconds: 600), () {
                        _searchLocation(val);
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'Search for a city or area...',
                      hintStyle: GoogleFonts.hankenGrotesk(color: t.muted),
                      prefixIcon: Icon(Icons.search_rounded, color: t.muted),
                      suffixIcon: _isSearching
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: Icon(Icons.clear_rounded, color: t.muted),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {
                                      _searchResults = [];
                                      _showSearchResults = false;
                                    });
                                  },
                                )
                              : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                if (_showSearchResults && _searchResults.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    constraints: const BoxConstraints(maxHeight: 220),
                    decoration: BoxDecoration(
                      color: t.paper,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                      border: Border.all(color: t.rail, width: 1),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: _searchResults.length,
                      separatorBuilder: (_, __) => Divider(color: t.rail, height: 1),
                      itemBuilder: (context, index) {
                        final item = _searchResults[index];
                        return ListTile(
                          title: Text(
                            item['display_name'] ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.hankenGrotesk(
                              color: t.ink,
                              fontSize: 14,
                            ),
                          ),
                          onTap: () => _onLocationSuggestionTap(item),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          // 3. Floating Radius controller Panel (Mid bottom)
          Positioned(
            left: 14,
            right: 14,
            bottom: _needs.isNotEmpty ? 190 : 30,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Quick locate button
                FloatingActionButton(
                  mini: true,
                  backgroundColor: t.paper,
                  foregroundColor: t.ink,
                  onPressed: () {
                    final me = myProfileNotifier.value;
                    if (me != null && me.lat != null && me.lng != null) {
                      final newLoc = LatLng(me.lat!, me.lng!);
                      setState(() {
                        _center = newLoc;
                        _selectedNeed = null;
                      });
                      _mapController.move(newLoc, 13.5);
                      _fetchNeeds();
                    }
                  },
                  child: const Icon(Icons.my_location_rounded, size: 18),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: t.paper,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 16,
                        offset: const Offset(0, -4),
                      ),
                    ],
                    border: Border.all(color: t.rail, width: 1),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.radar_rounded, color: NeedHubTokens.clay, size: 18),
                              const SizedBox(width: 6),
                              Text(
                                'Search Radius',
                                style: GoogleFonts.hankenGrotesk(
                                  fontWeight: FontWeight.w700,
                                  color: t.ink,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '${_radius.toStringAsFixed(1)} km',
                            style: GoogleFonts.hankenGrotesk(
                              fontWeight: FontWeight.w800,
                              color: NeedHubTokens.clay,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SliderTheme(
                        data: SliderThemeData(
                          activeTrackColor: NeedHubTokens.clay,
                          inactiveTrackColor: t.rail,
                          thumbColor: NeedHubTokens.clay,
                          overlayColor: NeedHubTokens.clay.withValues(alpha: 0.15),
                        ),
                        child: Slider(
                          value: _radius,
                          min: 1.0,
                          max: 50.0,
                          divisions: 49,
                          onChanged: (val) {
                            setState(() {
                              _radius = val;
                            });
                            _triggerFetchDebounce();
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 4. Horizontal Needs Carousel (Bottom overlay)
          if (_needs.isNotEmpty)
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              height: 156,
              child: PageView.builder(
                controller: _pageController,
                itemCount: _needs.length,
                onPageChanged: (idx) {
                  setState(() {
                    _selectedNeed = _needs[idx];
                  });
                  if (_selectedNeed!.lat != null && _selectedNeed!.lng != null) {
                    _mapController.move(
                      LatLng(_selectedNeed!.lat!, _selectedNeed!.lng!),
                      _mapController.camera.zoom,
                    );
                  }
                },
                itemBuilder: (context, index) {
                  final need = _needs[index];
                  final isEarn = need.category == 'earn';
                  final color = isEarn ? NeedHubTokens.ochre : NeedHubTokens.forest;

                  return GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => NeedDetailScreen(need: need),
                        ),
                      );
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: t.paper,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                        border: Border.all(
                          color: _selectedNeed?.id == need.id ? color : t.rail,
                          width: _selectedNeed?.id == need.id ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isEarn ? Icons.currency_rupee_rounded : Icons.handshake_rounded,
                                      size: 13,
                                      color: color,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      isEarn ? 'Earn' : 'Connect',
                                      style: GoogleFonts.hankenGrotesk(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: color,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              if (need.distanceKm != null)
                                Text(
                                  need.distanceLabel,
                                  style: GoogleFonts.hankenGrotesk(
                                    fontSize: 12,
                                    color: t.muted2,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            need.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.bricolageGrotesque(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: t.ink,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            need.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.hankenGrotesk(
                              fontSize: 12,
                              color: t.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

          // 5. Shimmer/Loading Indicator overlay
          if (_loading)
            Positioned(
              top: 80,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: t.paper,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Searching needs...',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: t.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
