import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import '../../l10n/app_strings.dart';
import '../../models/need.dart';
import '../../providers/language_provider.dart';
import '../../services/mappls_service.dart';
import '../../services/social_providers.dart';
import '../../services/profiles_api.dart';
import '../../services/translate_api.dart';
import '../../theme/tokens.dart';
import '../needs/need_detail_screen.dart';

class ViewOnMapScreen extends ConsumerStatefulWidget {
  const ViewOnMapScreen({super.key});

  @override
  ConsumerState<ViewOnMapScreen> createState() => _ViewOnMapScreenState();
}

class _ViewOnMapScreenState extends ConsumerState<ViewOnMapScreen>
    with SingleTickerProviderStateMixin {
  late final MapController _mapController;
  final PageController _pageController = PageController(viewportFraction: 0.85);
  final TextEditingController _searchController = TextEditingController();

  late TabController _tabController;

  LatLng _center = const LatLng(12.9716, 77.5946);
  double _radius = 5.0; // in km

  // Active needs (tab 0)
  List<Need> _activeNeeds = [];
  bool _loadingActive = false;

  // Fulfilled needs (tab 1)
  List<Need> _fulfilledNeeds = [];
  bool _loadingFulfilled = false;

  Timer? _fetchDebounce;
  Timer? _searchDebounce;
  Timer? _emptyDismissTimer;

  Need? _selectedNeed;
  List<PlaceSuggestion> _searchResults = const [];
  bool _isSearching = false;
  bool _showSearchResults = false;
  bool _isEmptyStateVisible = true;
  bool _isEmptyStateMinimized = false;
  LatLng? _mapCenter;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    uiLanguageNotifier.addListener(_onLangChange);
    feedLanguageNotifier.addListener(_onFeedLangChange);

    final me = myProfileNotifier.value;
    if (me != null && me.lat != null && me.lng != null) {
      _center = LatLng(me.lat!, me.lng!);
    }
    _mapCenter = _center;
    _fetchActiveNeeds();
    _fetchFulfilledNeeds();
  }

  void _onLangChange() {
    if (mounted) setState(() {});
  }

  void _onFeedLangChange() {
    if (mounted) setState(() {});
    _batchTranslateMapNeeds();
  }

  /// Translates every currently-loaded map need title in one Groq call,
  /// mirroring feed_tab's approach. Populates the shared `translationCache`
  /// so titles displayed here match what the feed shows for the same need.
  Future<void> _batchTranslateMapNeeds({int attempt = 0}) async {
    final lang = feedLanguageNotifier.value;
    if (lang == 'en') return;
    final needs = [..._activeNeeds, ..._fulfilledNeeds];
    final uncached =
        needs.where((n) => translationCache[n.id]?[lang] == null).toList();
    if (uncached.isEmpty) return;
    final titles = uncached.map((n) => n.title).toList();
    final translated = await translateBatch(titles, lang);
    bool anyTranslated = false;
    for (int i = 0; i < uncached.length; i++) {
      if (translated[i] != titles[i]) {
        translationCache.putIfAbsent(uncached[i].id, () => {})[lang] =
            translated[i];
        anyTranslated = true;
      }
    }
    if (mounted && anyTranslated) setState(() {});
    // Best-effort single retry, same pattern as feed_tab — Groq occasionally
    // rate-limits and a 4-second breather usually clears it.
    final stillUntranslated =
        needs.where((n) => translationCache[n.id]?[lang] == null).length;
    if (stillUntranslated > 0 && attempt == 0) {
      await Future.delayed(const Duration(seconds: 4));
      if (mounted) _batchTranslateMapNeeds(attempt: 1);
    }
  }

  /// Read the translated title for a need if one is cached, otherwise the
  /// original — same lookup shape the feed uses so a title translated in one
  /// surface immediately appears translated in the other.
  String _tTitle(Need n) =>
      translationCache[n.id]?[feedLanguageNotifier.value] ?? n.title;

  @override
  void dispose() {
    _fetchDebounce?.cancel();
    _searchDebounce?.cancel();
    _emptyDismissTimer?.cancel();
    _tabController.removeListener(_onTabChanged);
    uiLanguageNotifier.removeListener(_onLangChange);
    feedLanguageNotifier.removeListener(_onFeedLangChange);
    _tabController.dispose();
    _mapController.dispose();
    _pageController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      setState(() {
        _selectedNeed = null;
        _isEmptyStateVisible = true;
        _isEmptyStateMinimized = false;
      });
      _startEmptyDismissTimer();
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
    }
  }

  void _startEmptyDismissTimer() {
    _emptyDismissTimer?.cancel();
    _emptyDismissTimer = Timer(const Duration(seconds: 7), () {
      if (mounted) {
        setState(() => _isEmptyStateMinimized = true);
      }
    });
  }

  List<Need> get _currentNeeds =>
      _tabController.index == 0 ? _activeNeeds : _fulfilledNeeds;

  bool get _currentLoading =>
      _tabController.index == 0 ? _loadingActive : _loadingFulfilled;

  void _triggerFetchDebounce() {
    if (_fetchDebounce?.isActive ?? false) _fetchDebounce!.cancel();
    _fetchDebounce = Timer(const Duration(milliseconds: 400), () {
      _fetchActiveNeeds();
      _fetchFulfilledNeeds();
    });
  }

  Future<void> _fetchActiveNeeds() async {
    if (!mounted) return;
    setState(() => _loadingActive = true);

    try {
      final api = ref.read(needsApiProvider);
      final result = await api.feed(
        lat: _center.latitude,
        lng: _center.longitude,
        distanceKm: _radius,
        sort: 'distance',
        take: 100,
        status: 'OPEN',
      );

      if (mounted) {
        final needs =
            result.needs.where((n) => n.lat != null && n.lng != null).toList();
        setState(() {
          _activeNeeds = needs;
          _loadingActive = false;
          _isEmptyStateVisible = true;
          _isEmptyStateMinimized = false;
        });
        if (needs.isEmpty) _startEmptyDismissTimer();
        _batchTranslateMapNeeds();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingActive = false);
      }
    }
  }

  Future<void> _fetchFulfilledNeeds() async {
    if (!mounted) return;
    setState(() => _loadingFulfilled = true);

    try {
      final api = ref.read(needsApiProvider);
      final result = await api.feed(
        lat: _center.latitude,
        lng: _center.longitude,
        distanceKm: _radius,
        sort: 'distance',
        take: 100,
        status: 'FULFILLED',
      );

      if (mounted) {
        final needs =
            result.needs.where((n) => n.lat != null && n.lng != null).toList();
        setState(() {
          _fulfilledNeeds = needs;
          _loadingFulfilled = false;
          _isEmptyStateVisible = true;
          _isEmptyStateMinimized = false;
        });
        if (needs.isEmpty) _startEmptyDismissTimer();
        _batchTranslateMapNeeds();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingFulfilled = false);
      }
    }
  }

  // ── Search ─────────────────────────────────────────────────────────────────

  Future<void> _searchLocation(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = const [];
        _showSearchResults = false;
      });
      return;
    }

    setState(() => _isSearching = true);
    // Bias suggestions to the current map center — a "medical store" search
    // in Pune should return Pune hits, not the top nationwide chains.
    final results = await mappls.autosuggest(
      query,
      nearLat: _center.latitude,
      nearLng: _center.longitude,
    );
    if (!mounted) return;
    setState(() {
      _isSearching = false;
      _searchResults = results;
      _showSearchResults = results.isNotEmpty;
    });
  }

  void _onLocationSuggestionTap(PlaceSuggestion result) {
    final lat = result.lat;
    final lng = result.lng;
    if (lat != null && lng != null) {
      final newCenter = LatLng(lat, lng);
      setState(() {
        _center = newCenter;
        _mapCenter = newCenter;
        _showSearchResults = false;
        _searchResults = const [];
        _searchController.text = result.display;
        _isEmptyStateVisible = true;
        _isEmptyStateMinimized = false;
      });
      _mapController.move(newCenter, 13.5);
      _fetchActiveNeeds();
      _fetchFulfilledNeeds();
    }
    FocusScope.of(context).unfocus();
  }

  void _selectNeed(Need need) {
    setState(() {
      _selectedNeed = need;
    });

    final needs = _currentNeeds;
    final idx = needs.indexWhere((n) => n.id == need.id);
    if (idx != -1 && _pageController.hasClients) {
      _pageController.animateToPage(
        idx,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }

    if (need.lat != null && need.lng != null) {
      _mapController.move(
          LatLng(need.lat!, need.lng!), _mapController.camera.zoom);
    }
  }

  void _showNeedDetail(Need need) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _NeedDetailSheet(need: need),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final s = S.current;
    final isFulfilledTab = _tabController.index == 1;
    final needs = _currentNeeds;
    final isLoading = _currentLoading;

    // Build markers list for OSM map
    final List<Marker> markers = [
      // 1. Center pin
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
      // 2. Need pins
      ...needs.map((n) {
        final isSelected = _selectedNeed?.id == n.id;
        final color = isFulfilledTab
            ? NeedHubTokens.forest
            : (n.category == 'earn' ? NeedHubTokens.ochre : NeedHubTokens.forest);

        return Marker(
          point: LatLng(n.lat!, n.lng!),
          width: isSelected ? 56 : 46,
          height: isSelected ? 56 : 46,
          alignment: Alignment.center,
          child: GestureDetector(
            onTap: () => _selectNeed(n),
            child: _MarkerAvatarWidget(
              avatarUrl: n.posterAvatarUrl,
              initials: n.authorInitials,
              isSelected: isSelected,
              color: color,
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
          s.exploreOnMap,
          style: GoogleFonts.bricolageGrotesque(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: t.ink,
          ),
        ),
      ),
      body: Stack(
        children: [
          // 1. OSM Map
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
                  _mapCenter = point;
                  _selectedNeed = null;
                  _isEmptyStateVisible = true;
                  _isEmptyStateMinimized = false;
                  _showSearchResults = false;
                });
                _triggerFetchDebounce();
              },
              onPositionChanged: (position, hasGesture) {
                setState(() {
                  _mapCenter = position.center;
                });
                if (hasGesture && _showSearchResults) {
                  setState(() {
                    _showSearchResults = false;
                  });
                  FocusScope.of(context).unfocus();
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.needhub.needhub',
              ),
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: _center,
                    radius: _radius * 1000,
                    useRadiusInMeter: true,
                    color: isFulfilledTab
                        ? NeedHubTokens.forest.withValues(alpha: 0.06)
                        : NeedHubTokens.clay.withValues(alpha: 0.06),
                    borderColor: isFulfilledTab
                        ? NeedHubTokens.forest.withValues(alpha: 0.3)
                        : NeedHubTokens.clay.withValues(alpha: 0.3),
                    borderStrokeWidth: 2,
                  ),
                ],
              ),
              MarkerLayer(markers: markers),
            ],
          ),

          // 2. Search bar overlay
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
                      if (_searchDebounce?.isActive ?? false) {
                        _searchDebounce!.cancel();
                      }
                      _searchDebounce =
                          Timer(const Duration(milliseconds: 600), () {
                        _searchLocation(val);
                      });
                    },
                    decoration: InputDecoration(
                      hintText: s.searchCityOrArea,
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
                                      _searchResults = const [];
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
                      separatorBuilder: (_, __) =>
                          Divider(color: t.rail, height: 1),
                      itemBuilder: (context, index) {
                        final item = _searchResults[index];
                        return ListTile(
                          title: Text(
                            item.display,
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

          // 3. Tab selector
          Positioned(
            top: 78,
            left: 14,
            right: 14,
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: t.paper,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(color: t.rail, width: 1),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: _tabController.index == 0
                      ? NeedHubTokens.clay.withValues(alpha: 0.12)
                      : NeedHubTokens.forest.withValues(alpha: 0.12),
                ),
                dividerColor: Colors.transparent,
                labelPadding: EdgeInsets.zero,
                labelColor: _tabController.index == 0
                    ? NeedHubTokens.clay
                    : NeedHubTokens.forest,
                unselectedLabelColor: t.muted,
                labelStyle: GoogleFonts.hankenGrotesk(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
                unselectedLabelStyle: GoogleFonts.hankenGrotesk(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.campaign_rounded, size: 16),
                        const SizedBox(width: 6),
                        Text(s.activeNeedsTab(_activeNeeds.length)),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_outline_rounded, size: 16),
                        const SizedBox(width: 6),
                        Text(s.fulfilledTab(_fulfilledNeeds.length)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 3.5 Floating "Search this area" button when map center has panned away from query center
          if (_mapCenter != null &&
              ((_mapCenter!.latitude - _center.latitude).abs() > 0.002 ||
               (_mapCenter!.longitude - _center.longitude).abs() > 0.002))
            Positioned(
              top: 136,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _center = _mapCenter!;
                      _selectedNeed = null;
                      _isEmptyStateVisible = true;
                      _isEmptyStateMinimized = false;
                    });
                    _triggerFetchDebounce();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: t.ink,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.refresh_rounded, size: 14, color: Colors.white),
                        const SizedBox(width: 6),
                        Text(
                          s.searchThisArea,
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // 4. Radius slider + locate button
          Positioned(
            left: 14,
            right: 14,
            bottom: needs.isNotEmpty ? 200 : 30,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton(
                  heroTag: 'locate_me',
                  mini: true,
                  backgroundColor: t.paper,
                  foregroundColor: t.ink,
                  onPressed: () {
                    final me = myProfileNotifier.value;
                    if (me != null && me.lat != null && me.lng != null) {
                      final newLoc = LatLng(me.lat!, me.lng!);
                      setState(() {
                        _center = newLoc;
                        _mapCenter = newLoc;
                        _selectedNeed = null;
                        _isEmptyStateVisible = true;
                        _isEmptyStateMinimized = false;
                      });
                      _mapController.move(newLoc, 13.5);
                      _fetchActiveNeeds();
                      _fetchFulfilledNeeds();
                    }
                  },
                  child: const Icon(Icons.my_location_rounded, size: 18),
                ),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                              Icon(Icons.radar_rounded,
                                  color: NeedHubTokens.clay, size: 18),
                              const SizedBox(width: 6),
                              Text(
                                s.searchRadius,
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
                      SliderTheme(
                        data: SliderThemeData(
                          activeTrackColor: NeedHubTokens.clay,
                          inactiveTrackColor: t.rail,
                          thumbColor: NeedHubTokens.clay,
                          overlayColor:
                              NeedHubTokens.clay.withValues(alpha: 0.15),
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

          // 5. Bottom carousel
          if (needs.isNotEmpty)
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              height: 170,
              child: PageView.builder(
                controller: _pageController,
                itemCount: needs.length,
                onPageChanged: (idx) {
                  final need = needs[idx];
                  setState(() {
                    _selectedNeed = need;
                  });
                  if (need.lat != null && need.lng != null) {
                    _mapController.move(
                      LatLng(need.lat!, need.lng!),
                      _mapController.camera.zoom,
                    );
                  }
                },
                itemBuilder: (context, index) {
                  final need = needs[index];
                  final isEarn = need.category == 'earn';
                  final color = isFulfilledTab
                      ? NeedHubTokens.forest
                      : (isEarn ? NeedHubTokens.ochre : NeedHubTokens.forest);

                  return GestureDetector(
                    onTap: () => _showNeedDetail(need),
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      padding: const EdgeInsets.all(14),
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
                              _PosterAvatar(
                                avatarUrl: need.posterAvatarUrl,
                                initials: need.authorInitials,
                                size: 36,
                                color: color,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      need.authorName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.hankenGrotesk(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: t.ink,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${need.distanceLabel} · ${need.timeAgo}',
                                      style: GoogleFonts.hankenGrotesk(
                                        fontSize: 11,
                                        color: t.muted2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isFulfilledTab
                                          ? Icons.check_circle_outline_rounded
                                          : (isEarn
                                              ? Icons.currency_rupee_rounded
                                              : Icons.handshake_rounded),
                                      size: 12,
                                      color: color,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      isFulfilledTab
                                          ? s.fulfilled
                                          : (isEarn ? s.earn : s.connect),
                                      style: GoogleFonts.hankenGrotesk(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: color,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _tTitle(need),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.bricolageGrotesque(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: t.ink,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            s.tapToReadMore,
                            style: GoogleFonts.hankenGrotesk(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

          // 6. Empty state for current tab — auto-dismisses/minimizes after 7s or tap Minimize button
          if (!isLoading && needs.isEmpty && _isEmptyStateVisible)
            Positioned(
              bottom: 30,
              left: 30,
              right: 30,
              child: AnimatedCrossFade(
                firstChild: Container(
                  padding: const EdgeInsets.fromLTRB(20, 14, 14, 18),
                  decoration: BoxDecoration(
                    color: t.paper,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                    border: Border.all(color: t.rail, width: 1),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Minimize button row
                      Align(
                        alignment: Alignment.topRight,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _isEmptyStateMinimized = true;
                                });
                                _emptyDismissTimer?.cancel();
                              },
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: t.rail,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: t.muted),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _isEmptyStateVisible = false;
                                });
                                _emptyDismissTimer?.cancel();
                              },
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: t.rail,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.close_rounded, size: 14, color: t.muted),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        isFulfilledTab
                            ? Icons.check_circle_outline_rounded
                            : Icons.explore_off_rounded,
                        size: 36,
                        color: t.muted2,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        isFulfilledTab
                            ? s.noFulfilledNeedsArea
                            : s.noActiveNeedsArea,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.bricolageGrotesque(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: t.ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        s.dragMapToPick,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 11,
                          color: t.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                secondChild: Center(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _isEmptyStateMinimized = false;
                      });
                      _startEmptyDismissTimer();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: t.paper,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                        border: Border.all(color: t.rail, width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isFulfilledTab
                                ? Icons.check_circle_outline_rounded
                                : Icons.explore_off_rounded,
                            size: 14,
                            color: t.muted,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isFulfilledTab ? s.noFulfilledNeeds : s.noActiveNeeds,
                            style: GoogleFonts.hankenGrotesk(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: t.muted,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.keyboard_arrow_up_rounded, size: 14, color: t.muted),
                        ],
                      ),
                    ),
                  ),
                ),
                crossFadeState: _isEmptyStateMinimized
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 300),
              ),
            ),

          // 7. Loading indicator
          if (isLoading)
            Positioned(
              top: 136,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: t.paper,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
                  ),
                  child: Text(
                    isFulfilledTab
                        ? s.findingFulfilledNeeds
                        : s.searchingNeeds,
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: t.ink,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Marker Avatar Widget for OSM ─────────────────────────────────────────────

class _MarkerAvatarWidget extends StatelessWidget {
  final String? avatarUrl;
  final String initials;
  final bool isSelected;
  final Color color;

  const _MarkerAvatarWidget({
    required this.avatarUrl,
    required this.initials,
    required this.isSelected,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
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
      child: Padding(
        padding: const EdgeInsets.all(2.0),
        child: ClipOval(
          child: avatarUrl != null && avatarUrl!.isNotEmpty
              ? Image.network(
                  avatarUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _InitialsCircle(
                    initials: initials,
                    color: color,
                  ),
                )
              : _InitialsCircle(initials: initials, color: color),
        ),
      ),
    );
  }
}

// ── Poster Avatar Widget ─────────────────────────────────────────────────────

class _PosterAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String initials;
  final double size;
  final Color color;

  const _PosterAvatar({
    required this.avatarUrl,
    required this.initials,
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.4), width: 2),
      ),
      child: ClipOval(
        child: avatarUrl != null && avatarUrl!.isNotEmpty
            ? Image.network(
                avatarUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _InitialsCircle(
                  initials: initials,
                  color: color,
                ),
              )
            : _InitialsCircle(initials: initials, color: color),
      ),
    );
  }
}

class _InitialsCircle extends StatelessWidget {
  final String initials;
  final Color color;

  const _InitialsCircle({required this.initials, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color,
      alignment: Alignment.center,
      child: Text(
        initials,
        style: GoogleFonts.hankenGrotesk(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
      ),
    );
  }
}

// ── Need Detail Bottom Sheet ─────────────────────────────────────────────────

class _NeedDetailSheet extends StatelessWidget {
  final Need need;

  const _NeedDetailSheet({required this.need});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final s = S.current;
    final isEarn = need.category == 'earn';
    final isFulfilled = need.status.toUpperCase() == 'FULFILLED';
    final color = isFulfilled
        ? NeedHubTokens.forest
        : (isEarn ? NeedHubTokens.ochre : NeedHubTokens.forest);

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: t.paper,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 20),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: t.muted2.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  _PosterAvatar(
                    avatarUrl: need.posterAvatarUrl,
                    initials: need.authorInitials,
                    size: 48,
                    color: color,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(need.authorName,
                            style: GoogleFonts.bricolageGrotesque(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: t.ink)),
                        Text(need.location,
                            style: GoogleFonts.hankenGrotesk(
                                fontSize: 12, color: t.muted2)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                translationCache[need.id]?[feedLanguageNotifier.value] ??
                    need.title,
                style: GoogleFonts.bricolageGrotesque(
                    fontSize: 20, fontWeight: FontWeight.w800, color: t.ink),
              ),
              const SizedBox(height: 14),
              Text(
                need.description,
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 14,
                  color: t.muted,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => NeedDetailScreen(need: need)));
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: Text(s.viewFullDetails,
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
