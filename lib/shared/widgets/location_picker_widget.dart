import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';

/// Simple Location Picker Widget using OpenStreetMap (Free, No API Key)
///
/// Flow:
/// - Tap map = save location (Money Lender pin appears)
/// - See pin = stored location
/// - Tap pin = get directions to that place
class LocationPickerWidget extends StatefulWidget {
  final double? latitude;
  final double? longitude;
  final String? customerName;
  final Function(double latitude, double longitude)? onLocationSelected;
  final bool isReadOnly;
  final bool showDirectionsButton;
  final bool showFullScreenButton;
  final double height;

  const LocationPickerWidget({
    super.key,
    this.latitude,
    this.longitude,
    this.customerName,
    this.onLocationSelected,
    this.isReadOnly = false,
    this.showDirectionsButton = false,
    this.showFullScreenButton = true,
    this.height = 200,
  });

  @override
  State<LocationPickerWidget> createState() => _LocationPickerWidgetState();
}

class _LocationPickerWidgetState extends State<LocationPickerWidget> {
  final MapController _mapController = MapController();
  LatLng? _selectedLocation;
  LatLng _currentCenter = const LatLng(11.0168, 76.9558); // Default: Coimbatore
  bool _isLoading = false;
  bool _isMapReady = false;
  double _currentZoom = 13.0;
  String? _errorMessage; // Track error messages for UI display
  bool _tileError = false; // Track tile loading errors
  // Debounce timer for position changes to improve performance
  Timer? _positionDebounceTimer;

  @override
  void initState() {
    super.initState();
    _initializeLocation();
  }

  @override
  void dispose() {
    _positionDebounceTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _initializeLocation() {
    if (widget.latitude != null && widget.longitude != null) {
      _selectedLocation = LatLng(widget.latitude!, widget.longitude!);
      _currentCenter = _selectedLocation!;
    }
  }

  @override
  void didUpdateWidget(LocationPickerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update location if parent widget passes new values
    if (widget.latitude != oldWidget.latitude || 
        widget.longitude != oldWidget.longitude) {
      if (widget.latitude != null && widget.longitude != null) {
        setState(() {
          _selectedLocation = LatLng(widget.latitude!, widget.longitude!);
          _currentCenter = _selectedLocation!;
        });
        if (_isMapReady) {
          try {
            _mapController.move(_currentCenter, _currentZoom);
          } catch (e) {
            debugPrint('Error moving map: $e');
          }
        }
      }
    }
  }

  /// Get current device location with better error handling
  Future<void> _getCurrentLocation() async {
    if (_isLoading) return;
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showError('Location services are disabled. Please enable GPS.');
        setState(() => _isLoading = false);
        return;
      }

      // Check permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showError('Location permission denied.');
          setState(() => _isLoading = false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showError('Location permissions are permanently denied. Please enable in settings.');
        setState(() => _isLoading = false);
        return;
      }

      // Get current position with timeout
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception('Location request timed out');
        },
      );

      if (!mounted) return;

      setState(() {
        _currentCenter = LatLng(position.latitude, position.longitude);
        _selectedLocation = _currentCenter;
        _isLoading = false;
      });

      // Move map to current location
      if (_isMapReady) {
        try {
          _mapController.move(_currentCenter, 16.0);
        } catch (e) {
          debugPrint('Error moving map: $e');
        }
      }

      // Notify parent - THIS IS THE KEY FOR SAVING
      widget.onLocationSelected?.call(position.latitude, position.longitude);
      
      _showSuccess('Location captured successfully!');
    } catch (e) {
      debugPrint('Error getting location: $e');
      if (mounted) {
        _showError('Could not get current location. Please try again.');
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) {
    setState(() => _errorMessage = message);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showSuccess(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// Open Google Maps for turn-by-turn directions from current GPS location to selected destination
  Future<void> _openDirections() async {
    if (_selectedLocation == null) return;

    final destLat = _selectedLocation!.latitude;
    final destLng = _selectedLocation!.longitude;

    // Show loading indicator
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              SizedBox(width: 12),
              Text('Getting your location for directions...'),
            ],
          ),
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    try {
      // Get current GPS location for source
      Position? currentPosition;
      
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        // Check permissions
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        
        if (permission == LocationPermission.whileInUse || 
            permission == LocationPermission.always) {
          // Get current position
          currentPosition = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium,
          ).timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw Exception('Location timeout'),
          );
        }
      }

      // Hide loading snackbar
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }

      // Build URL with or without source location
      String googleMapsUrl;
      String googleMapsIntentUrl;
      
      if (currentPosition != null) {
        // With source location - Google Maps will show turn-by-turn from current location
        final srcLat = currentPosition.latitude;
        final srcLng = currentPosition.longitude;
        
        // Google Maps URL with origin and destination for turn-by-turn navigation
        googleMapsUrl = 'https://www.google.com/maps/dir/?api=1&origin=$srcLat,$srcLng&destination=$destLat,$destLng&travelmode=driving';
        
        // Google Maps intent with source and destination
        googleMapsIntentUrl = 'google.navigation:q=$destLat,$destLng&mode=d';
      } else {
        // Without source - Google Maps will use device's current location
        googleMapsUrl = 'https://www.google.com/maps/dir/?api=1&destination=$destLat,$destLng&travelmode=driving';
        googleMapsIntentUrl = 'google.navigation:q=$destLat,$destLng&mode=d';
      }

      final googleMapsIntent = Uri.parse(googleMapsIntentUrl);
      final googleMapsUri = Uri.parse(googleMapsUrl);
      
      // Fallback to geo: URI (opens default map app)
      final geoUrl = Uri.parse('geo:$destLat,$destLng?q=$destLat,$destLng');

      // Try Google Maps navigation intent first (starts turn-by-turn immediately)
      if (await canLaunchUrl(googleMapsIntent)) {
        await launchUrl(googleMapsIntent, mode: LaunchMode.externalApplication);
        return;
      }

      // Try Google Maps URL (opens in browser/app with directions)
      if (await canLaunchUrl(googleMapsUri)) {
        await launchUrl(googleMapsUri, mode: LaunchMode.externalApplication);
        return;
      }

      // Try geo: URI (works with most map apps)
      if (await canLaunchUrl(geoUrl)) {
        await launchUrl(geoUrl, mode: LaunchMode.externalApplication);
        return;
      }

      // If nothing works, show helpful error
      _showError('No map app found. Please install Google Maps.');
    } catch (e) {
      debugPrint('Error opening directions: $e');
      _showError('Could not open maps. Please check if a map app is installed.');
    }
  }

  /// Handle map tap to place marker - THIS IS THE KEY FOR SAVING
  void _onMapTap(TapPosition tapPosition, LatLng point) {
    if (widget.isReadOnly) return;

    setState(() {
      _selectedLocation = point;
      _errorMessage = null;
    });

    // Notify parent immediately when location is selected
    widget.onLocationSelected?.call(point.latitude, point.longitude);
    
    // Show feedback
    _showSuccess('Location selected!');
  }

  /// Open full screen map picker
  Future<void> _openFullScreenMap() async {
    final result = await Navigator.push<Map<String, double>>(
      context,
      MaterialPageRoute(
        builder: (context) => LocationPickerScreen(
          initialLatitude: _selectedLocation?.latitude ?? widget.latitude,
          initialLongitude: _selectedLocation?.longitude ?? widget.longitude,
          customerName: widget.customerName,
        ),
      ),
    );

    if (result != null) {
      final lat = result['latitude']!;
      final lng = result['longitude']!;
      
      setState(() {
        _selectedLocation = LatLng(lat, lng);
        _currentCenter = _selectedLocation!;
        _currentZoom = 15.0;
      });
      
      // Notify parent
      widget.onLocationSelected?.call(lat, lng);
      
      // Move map to new location
      if (_isMapReady) {
        _mapController.move(_selectedLocation!, _currentZoom);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _errorMessage != null ? Colors.red.shade300 : Colors.grey.shade300),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Map with error handling
          _buildMap(),

          // Zoom controls
          Positioned(
            left: 10,
            bottom: 60,
            child: Column(
              children: [
                _buildZoomButton(Icons.add, () {
                  if (_isMapReady) {
                    _currentZoom = (_currentZoom + 1).clamp(3.0, 18.0);
                    _mapController.move(_mapController.camera.center, _currentZoom);
                  }
                }),
                const SizedBox(height: 4),
                _buildZoomButton(Icons.remove, () {
                  if (_isMapReady) {
                    _currentZoom = (_currentZoom - 1).clamp(3.0, 18.0);
                    _mapController.move(_mapController.camera.center, _currentZoom);
                  }
                }),
              ],
            ),
          ),

          // Full Screen Button (when not read-only and allowed)
          if (!widget.isReadOnly && widget.showFullScreenButton)
            Positioned(
              left: 10,
              top: 10,
              child: FloatingActionButton.small(
                heroTag: 'fullscreen_btn_${widget.hashCode}',
                onPressed: _openFullScreenMap,
                backgroundColor: Colors.white,
                elevation: 4,
                child: const Icon(Icons.fullscreen, color: Colors.blue),
              ),
            ),

          // Current Location Button
          if (!widget.isReadOnly)
            Positioned(
              right: 10,
              bottom: 10,
              child: FloatingActionButton.small(
                heroTag: 'location_btn_${widget.hashCode}',
                onPressed: _isLoading ? null : _getCurrentLocation,
                backgroundColor: Colors.white,
                elevation: 4,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location, color: Colors.blue),
              ),
            ),

          // Directions Button (when location is selected and in read-only mode)
          if (widget.isReadOnly && _selectedLocation != null)
            Positioned(
              right: 10,
              bottom: 10,
              child: FloatingActionButton.small(
                heroTag: 'directions_btn_${widget.hashCode}',
                onPressed: _openDirections,
                backgroundColor: Colors.green,
                child: const Icon(Icons.directions, color: Colors.white),
              ),
            ),

          // Instructions overlay (when no location selected and not read-only)
          if (_selectedLocation == null && !widget.isReadOnly)
            Positioned(
              top: 10,
              left: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.touch_app, color: Colors.white, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tap on map or use GPS button to select location',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Location saved indicator
          if (_selectedLocation != null && !widget.isReadOnly)
            Positioned(
              top: 10,
              left: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Location: ${_selectedLocation!.latitude.toStringAsFixed(4)}, ${_selectedLocation!.longitude.toStringAsFixed(4)}',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Tap pin for directions hint (read-only mode)
          if (_selectedLocation != null && widget.isReadOnly)
            Positioned(
              top: 10,
              left: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.directions, color: Colors.white, size: 16),
                    SizedBox(width: 8),
                    Text(
                      'Tap pin or button for directions',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildZoomButton(IconData icon, VoidCallback onPressed) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, size: 18),
        onPressed: onPressed,
        padding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildMap() {
    // Wrap in RepaintBoundary for better performance
    return RepaintBoundary(
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _currentCenter,
          initialZoom: _currentZoom,
          minZoom: 3.0,
          maxZoom: 18.0,
          onTap: _onMapTap,
          onMapReady: () {
            setState(() {
              _isMapReady = true;
              _tileError = false; // Reset error on map ready
            });
          },
          // Debounce position changes for better performance
          onPositionChanged: (position, hasGesture) {
            if (hasGesture && position.zoom != null) {
              // Cancel any existing debounce timer
              _positionDebounceTimer?.cancel();
              // Update zoom with debounce to prevent excessive rebuilds
              _positionDebounceTimer = Timer(const Duration(milliseconds: 100), () {
                if (mounted) {
                  _currentZoom = position.zoom!;
                }
              });
            }
          },
          // Performance optimizations
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all,
            enableMultiFingerGestureRace: true,
          ),
        ),
        children: [
          // OpenStreetMap Tiles with robust error handling
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.moneylender.flu_app',
            // Tile performance optimizations
            maxZoom: 18,
            keepBuffer: 2, // Keep fewer tiles in memory
            panBuffer: 1,
            // Use instant display to prevent flickering issues
            tileDisplay: const TileDisplay.instantaneous(),
            // Better error handling for tiles
            errorTileCallback: (tile, error, stackTrace) {
              // Only log first few errors to avoid spam
              if (!_tileError) {
                _tileError = true; // Mark that we've had a tile error
                debugPrint('Tile load error at ${tile.coordinates}: $error');
                // Don't show UI error for individual tile failures
                // The map will continue to work with other tiles
              }
            },
          ),

          // Marker Layer with Money Lender App Icon style
          if (_selectedLocation != null)
            MarkerLayer(
              markers: [
                Marker(
                  point: _selectedLocation!,
                width: 60,
                height: 70,
                child: GestureDetector(
                  onTap: widget.isReadOnly ? _openDirections : null,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Money Lender branded marker
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1565C0), // Money Lender blue
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.currency_rupee, // Money Lender icon
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      // Pin pointer
                      Container(
                        width: 3,
                        height: 12,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1565C0),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      // Pin tip
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1565C0),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
      ],
      ),
    );
  }
}

/// Full Screen Location Picker (for selection flow)
class LocationPickerScreen extends StatefulWidget {
  final double? initialLatitude;
  final double? initialLongitude;
  final String? customerName;

  const LocationPickerScreen({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
    this.customerName,
  });

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  double? _selectedLat;
  double? _selectedLng;
  bool _isSaving = false; // Guard against double-tap

  @override
  void initState() {
    super.initState();
    _selectedLat = widget.initialLatitude;
    _selectedLng = widget.initialLongitude;
  }

  void _saveAndReturn() {
    // Prevent double-tap issues
    if (_isSaving) return;
    
    if (_selectedLat != null && _selectedLng != null) {
      _isSaving = true;
      // Cast to non-nullable Map<String, double> to match Navigator.push type
      final Map<String, double> result = {
        'latitude': _selectedLat!,
        'longitude': _selectedLng!,
      };
      Navigator.of(context).pop(result);
    } else {
      // Show feedback if no location selected
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please tap on the map to select a location first'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Select Location', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            if (widget.customerName != null && widget.customerName!.isNotEmpty)
              Text(
                'for ${widget.customerName}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 2,
        shadowColor: Colors.black26,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Cancel',
        ),
        actions: [
          // Quick save button in app bar too
          if (_selectedLat != null)
            TextButton.icon(
              onPressed: _saveAndReturn,
              icon: const Icon(Icons.check, color: Colors.green, size: 20),
              label: const Text('Save', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
      body: Column(
        children: [
          // Instructions
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: const Color(0xFF1565C0).withValues(alpha: 0.1),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Color(0xFF1565C0), size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tap on the map to select customer location, or use the GPS button to set your current position.',
                    style: TextStyle(color: Color(0xFF1565C0), fontSize: 13),
                  ),
                ),
              ],
            ),
          ),

          // Map (full screen)
          Expanded(
            child: LocationPickerWidget(
              latitude: _selectedLat,
              longitude: _selectedLng,
              height: double.infinity,
              showFullScreenButton: false, // Prevent recursive fullscreen
              onLocationSelected: (lat, lng) {
                setState(() {
                  _selectedLat = lat;
                  _selectedLng = lng;
                });
              },
            ),
          ),

          // Always show save button at bottom
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1565C0).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _selectedLat != null ? Icons.location_pin : Icons.location_off,
                      color: const Color(0xFF1565C0),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _selectedLat != null ? 'Selected Location' : 'No Location Selected',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _selectedLat != null 
                              ? '${_selectedLat!.toStringAsFixed(6)}, ${_selectedLng!.toStringAsFixed(6)}'
                              : 'Tap on map to select',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _saveAndReturn,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Save'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _selectedLat != null ? Colors.green : Colors.grey,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
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
