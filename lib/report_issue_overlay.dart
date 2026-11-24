import 'dart:async';
import 'package:citisense/api_config.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:citisense/app_theme.dart';
import 'package:citisense/mascot.dart';
import 'package:citisense/app_settings.dart';
import 'package:exif/exif.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:citisense/friendly_errors.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';

// ============================================================
// AI CLASSIFICATION BACKEND
// ============================================================

const String aiClassificationUrl = '$apiBaseUrl/classify_image.php';

// ============================================================
// REPORT SUBMISSION BACKEND
// ============================================================

const String submitReportUrl = '$apiBaseUrl/submit_report.php';

// ============================================================
// REPORT ISSUE OVERLAY
// ============================================================

class ReportIssueOverlay extends StatefulWidget {
  final String userID;
  final String barangayID;

  const ReportIssueOverlay({
    super.key,
    required this.userID,
    required this.barangayID,
  });

  @override
  State<ReportIssueOverlay> createState() => _ReportIssueOverlayState();
}

class _ReportIssueOverlayState extends State<ReportIssueOverlay> {
  final ImagePicker _picker = ImagePicker();

  final TextEditingController _descriptionController = TextEditingController();

  // ============================================================
  // SELECTED IMAGE
  // ============================================================

  Uint8List? _selectedImageBytes;

  // Remembers whether the image came from the camera or gallery.
  ImageSource? _selectedImageSource;

  String? _selectedCategory;

  LatLng? _selectedLocation;

  // ============================================================
  // SELECTED ADDRESS
  // ============================================================

  String? _selectedAddress;

  bool _isAnalyzing = false;
  bool _isSubmitting = false;

  String? _aiMessage;

  // Short note shown under the Location button (e.g. no GPS in photo).
  String? _locationNote;
  bool _isLocating = false;

  // Mirrors Settings > AI Insights.
  bool _aiEnabled = true;

  // Turns on red highlights for missing fields after a submit attempt.
  bool _showMissingFields = false;

  // "Others" says nothing about the problem, so it needs a description.
  bool get _descriptionRequired => _selectedCategory == 'Others';

  String? get _descriptionError =>
      _showMissingFields &&
          _descriptionRequired &&
          _descriptionController.text.trim().isEmpty
      ? 'Add a description'
      : null;

  @override
  void initState() {
    super.initState();
    AiInsightsPreference.isEnabled().then((enabled) {
      if (mounted) setState(() => _aiEnabled = enabled);
    });
  }

  final List<String> _categories = [
    'Waste Accumulation',
    'Blocked Drainage',
    'Road Potholes',
    'Others',
  ];

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _descriptionController.dispose();

    super.dispose();
  }

  // ============================================================
  // PHOTO PICKER
  // ============================================================

  Future<void> _pickImage(ImageSource source) async {
    try {
      // Gallery: Android hides the GPS data inside photos unless the app
      // has "media location" access, so ask for it before picking.
      if (source == ImageSource.gallery) {
        await _requestMediaLocationAccess();
      }

      final XFile? image = await _picker.pickImage(
        source: source,
        // Keep the original image so gallery EXIF GPS metadata is not
        // discarded by image-picker compression before we read it.
        imageQuality: null,
        requestFullMetadata: true,
      );

      if (image == null || !mounted) return;

      final Uint8List imageBytes = await image.readAsBytes();
      if (!mounted) return;

      setState(() {
        _selectedImageBytes = imageBytes;
        _selectedImageSource = source;
        _selectedCategory = null;
        _selectedLocation = null;
        _selectedAddress = null;
        _aiMessage = null;
        _locationNote = null;
        _showMissingFields = false;
      });

      // AI Insights on: analyze the photo and auto-select the category.
      // AI Insights off: skip it; the user picks the category.
      final bool aiEnabled = await AiInsightsPreference.isEnabled();
      if (!mounted) return;
      setState(() => _aiEnabled = aiEnabled);

      final Future<void> analysis = aiEnabled
          ? _analyzeImage(imageBytes)
          : Future<void>.value();

      if (source == ImageSource.camera) {
        // CAMERA: pin the user's live location automatically.
        // Give Android a moment to bring the app back from the camera
        // before showing the permission prompt.
        await Future<void>.delayed(const Duration(milliseconds: 400));

        setState(() => _isLocating = true);
        final LatLng? liveLocation = await _getCurrentDeviceLocation();
        if (!mounted) return;
        setState(() => _isLocating = false);

        if (liveLocation != null) {
          await _setSuggestedLocation(liveLocation);
          if (mounted) {
            setState(() => _locationNote = 'Pinned to your current location.');
          }
        } else {
          setState(() {
            _locationNote =
                'Your location could not be found. '
                'Tap "Set Location on Map" to pin it.';
          });
        }
      } else {
        // GALLERY: use the GPS coordinates saved inside the photo.
        final LatLng? photoLocation = await _getGpsLocationFromExif(imageBytes);
        if (!mounted) return;

        if (photoLocation != null) {
          await _setSuggestedLocation(photoLocation);
          if (mounted) {
            setState(
              () => _locationNote = 'Pinned using the photo\'s location.',
            );
          }
        } else {
          // No GPS in the photo: the user pins it manually. The map will
          // open at their live location.
          setState(() {
            _locationNote =
                'This photo has no location data. '
                'Tap "Set Location on Map" to pin it.';
          });
        }
      }

      await analysis;
    } catch (e) {
      debugPrint('Image selection error: $e');
      if (mounted) setState(() => _isLocating = false);
      _showMessage('Unable to select the photo.');
    }
  }

  // ============================================================
  // MEDIA LOCATION ACCESS (needed to read GPS from gallery photos)
  // ============================================================

  Future<void> _requestMediaLocationAccess() async {
    try {
      final status = await Permission.accessMediaLocation.request();
      debugPrint('Media location permission: $status');
    } catch (e) {
      // Older Android versions do not have this permission; that's fine.
      debugPrint('Media location permission not available: $e');
    }
  }

  // ============================================================
  // EXIF GPS EXTRACTION (GALLERY PHOTOS)
  // ============================================================

  double _ratioToDouble(Ratio ratio) {
    if (ratio.denominator == 0) return 0;
    return ratio.numerator / ratio.denominator;
  }

  double _degreesMinutesSecondsToDecimal(IfdRatios values) {
    final ratios = values.ratios;
    if (ratios.length < 3) {
      throw const FormatException('Incomplete EXIF GPS coordinate.');
    }

    final degrees = _ratioToDouble(ratios[0]);
    final minutes = _ratioToDouble(ratios[1]);
    final seconds = _ratioToDouble(ratios[2]);

    return degrees + (minutes / 60) + (seconds / 3600);
  }

  Future<LatLng?> _getGpsLocationFromExif(Uint8List imageBytes) async {
    try {
      final Map<String, IfdTag> exifData = await readExifFromBytes(imageBytes);

      final latitudeTag = exifData['GPS GPSLatitude'];
      final latitudeRefTag = exifData['GPS GPSLatitudeRef'];
      final longitudeTag = exifData['GPS GPSLongitude'];
      final longitudeRefTag = exifData['GPS GPSLongitudeRef'];

      if (latitudeTag == null ||
          latitudeRefTag == null ||
          longitudeTag == null ||
          longitudeRefTag == null ||
          latitudeTag.values is! IfdRatios ||
          longitudeTag.values is! IfdRatios) {
        debugPrint('No GPS EXIF metadata found in selected gallery image.');
        return null;
      }

      double latitude = _degreesMinutesSecondsToDecimal(
        latitudeTag.values as IfdRatios,
      );
      double longitude = _degreesMinutesSecondsToDecimal(
        longitudeTag.values as IfdRatios,
      );

      if (latitudeRefTag.printable.trim().toUpperCase() == 'S') {
        latitude = -latitude;
      }
      if (longitudeRefTag.printable.trim().toUpperCase() == 'W') {
        longitude = -longitude;
      }

      if (latitude < -90 ||
          latitude > 90 ||
          longitude < -180 ||
          longitude > 180) {
        debugPrint('EXIF GPS coordinates are outside valid ranges.');
        return null;
      }

      debugPrint('EXIF latitude: $latitude');
      debugPrint('EXIF longitude: $longitude');

      return LatLng(latitude, longitude);
    } catch (e) {
      debugPrint('Unable to read EXIF GPS metadata: $e');
      return null;
    }
  }

  // ============================================================
  // GET CURRENT DEVICE LOCATION
  // ============================================================

  Future<LatLng?> _getCurrentDeviceLocation() async {
    try {
      // ----------------------------------------------------------
      // 1. LOCATION (GPS) MUST BE ON
      // ----------------------------------------------------------
      if (!await Geolocator.isLocationServiceEnabled()) {
        final openSettings = await _showLocationProblem(
          title: 'Turn on Location',
          message:
              'Your phone\'s Location (GPS) is off. Turn it on so '
              'CitiSense can pin where the issue is.',
          actionLabel: 'Turn On',
        );
        if (!openSettings) return null;

        await Geolocator.openLocationSettings();
        await _waitForAppResume();

        if (!await Geolocator.isLocationServiceEnabled()) {
          _showMessage('Location is still off.');
          return null;
        }
      }

      // ----------------------------------------------------------
      // 2. PERMISSION
      // "Ask every time" -> checkPermission returns denied, and
      // requestPermission shows Android's permission prompt.
      // ----------------------------------------------------------
      LocationPermission permission = await Geolocator.checkPermission();
      debugPrint('Location permission status: $permission');

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        debugPrint('Location permission after request: $permission');
      }

      // "Don't allow" -> Android will not show the prompt anymore, so ask
      // the user to turn it on in the app's settings page.
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        final openSettings = await _showLocationProblem(
          title: 'Allow location access',
          message:
              'CitiSense needs your location to pin the issue. In Settings, '
              'tap Permissions > Location and choose '
              '"Allow only while using the app" or "Ask every time".',
          actionLabel: 'Open Settings',
        );
        if (!openSettings) return null;

        await Geolocator.openAppSettings();
        await _waitForAppResume();

        permission = await Geolocator.checkPermission();
        debugPrint('Location permission after settings: $permission');

        // "Ask every time" chosen in Settings still needs the prompt.
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }

        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          _showMessage('Location permission was not allowed.');
          return null;
        }
      }

      // ----------------------------------------------------------
      // 3. GET THE LIVE POSITION
      // ----------------------------------------------------------
      try {
        final Position position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 20),
          ),
        );
        return LatLng(position.latitude, position.longitude);
      } on TimeoutException {
        // Indoors the GPS can be slow; fall back to the last known fix.
        final Position? lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          return LatLng(lastKnown.latitude, lastKnown.longitude);
        }
        _showMessage('Getting your current location took too long.');
        return null;
      }
    } catch (e) {
      debugPrint('Current location error: $e');
      await _showLocationProblem(
        title: 'Unable to get your location',
        message:
            'Your phone could not find your location right now. Move to an '
            'open area and try again, or tap "Set Location on Map" to pin '
            'it yourself.',
      );
      return null;
    }
  }

  // Waits until the user comes back from a Settings screen.
  Future<void> _waitForAppResume() async {
    final completer = Completer<void>();
    final listener = AppLifecycleListener(
      onResume: () {
        if (!completer.isCompleted) completer.complete();
      },
    );
    try {
      await completer.future.timeout(const Duration(minutes: 2));
    } on TimeoutException {
      // User never came back; continue with whatever state we have.
    } finally {
      listener.dispose();
    }
    // Let Android finish applying the new setting.
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  // Shown as a dialog (not a snackbar) because this screen is itself a
  // dialog, and snackbars appear behind it where they can't be seen.
  // Returns true when the user taps the action button.
  Future<bool> _showLocationProblem({
    required String title,
    required String message,
    String? actionLabel,
  }) async {
    if (!mounted) return false;

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(
          Icons.location_on_outlined,
          color: AppColors.primary,
          size: 32,
        ),
        title: Text(title, textAlign: TextAlign.center),
        content: Text(message, textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              actionLabel == null ? 'OK' : 'Not Now',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          if (actionLabel != null)
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(actionLabel),
            ),
        ],
      ),
    );

    return result ?? false;
  }

  // ============================================================
  // SAVE SUGGESTED LOCATION AND REVERSE GEOCODE IT
  // ============================================================

  Future<void> _setSuggestedLocation(LatLng location) async {
    if (!mounted) return;

    setState(() {
      _selectedLocation = location;
      _selectedAddress = null;
    });

    final String? address = await _getAddressFromCoordinates(
      location.latitude,
      location.longitude,
    );

    if (!mounted) return;

    setState(() {
      _selectedAddress = address;
    });
  }

  // ============================================================
  // IMAGE SOURCE OPTIONS
  // ============================================================

  Future<void> _showImageSourceOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Wrap(
            children: [
              // --------------------------------------------------
              // GALLERY
              // --------------------------------------------------
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(sheetContext);

                  _pickImage(ImageSource.gallery);
                },
              ),

              // --------------------------------------------------
              // CAMERA
              // --------------------------------------------------
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Take a Photo'),
                onTap: () {
                  Navigator.pop(sheetContext);

                  _pickImage(ImageSource.camera);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // AI IMAGE CLASSIFICATION
  // ============================================================

  Future<void> _analyzeImage(Uint8List imageBytes) async {
    if (!mounted) return;

    setState(() {
      _isAnalyzing = true;
      _aiMessage = 'AI is analyzing the photo...';
    });

    try {
      // Create multipart request to the PHP Roboflow backend.
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(aiClassificationUrl),
      );

      // Attach the selected image.
      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          imageBytes,
          filename: 'report_image.jpg',
        ),
      );

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 120),
      );

      final response = await http.Response.fromStream(streamedResponse);

      debugPrint('Roboflow HTTP Status: ${response.statusCode}');
      debugPrint('Roboflow Response: ${response.body}');

      // Decode the PHP response.
      final dynamic decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        throw Exception('Invalid response from the AI server.');
      }

      // Check both HTTP status and backend success.
      if (response.statusCode != 200 || decoded['success'] != true) {
        final message =
            decoded['message']?.toString() ?? 'Image classification failed.';
        throw Exception(message);
      }

      // Read Roboflow's suggested category.
      final String predictedCategory = (decoded['category'] ?? '')
          .toString()
          .trim();

      // Match the returned category with CitiSense categories.
      // Keep the legacy "Potholes" alias for response compatibility.
      final String normalizedCategory;

      if (predictedCategory == 'Potholes') {
        normalizedCategory = 'Road Potholes';
      } else if (_categories.contains(predictedCategory)) {
        normalizedCategory = predictedCategory;
      } else {
        normalizedCategory = 'Others';
      }

      final String reason = decoded['reason']?.toString().trim() ?? '';

      if (!mounted) return;

      setState(() {
        _selectedCategory = normalizedCategory;
        _aiMessage = reason.isNotEmpty
            ? 'AI suggestion: $normalizedCategory\n$reason'
            : 'AI suggestion: $normalizedCategory';
      });
    } on TimeoutException {
      debugPrint('Roboflow classification timed out.');

      if (!mounted) return;

      setState(() {
        _aiMessage =
            'AI analysis took too long. Please select a category manually.';
      });
    } catch (e) {
      debugPrint('Roboflow classification error: $e');

      if (!mounted) return;

      setState(() {
        _aiMessage =
            'Unable to analyze the photo. Please select a category manually.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
        });
      }
    }
  }

  // ============================================================
  // GET ADDRESS FROM COORDINATES
  // ============================================================

  Future<String?> _getAddressFromCoordinates(
    double latitude,
    double longitude,
  ) async {
    try {
      final List<Placemark> placemarks = await placemarkFromCoordinates(
        latitude,
        longitude,
      );

      if (placemarks.isEmpty) {
        return null;
      }

      final Placemark place = placemarks.first;

      final List<String> addressParts = [
        if (place.name != null && place.name!.trim().isNotEmpty)
          place.name!.trim(),

        if (place.street != null &&
            place.street!.trim().isNotEmpty &&
            place.street!.trim() != place.name?.trim())
          place.street!.trim(),

        if (place.subLocality != null && place.subLocality!.trim().isNotEmpty)
          place.subLocality!.trim(),

        if (place.locality != null && place.locality!.trim().isNotEmpty)
          place.locality!.trim(),

        if (place.administrativeArea != null &&
            place.administrativeArea!.trim().isNotEmpty)
          place.administrativeArea!.trim(),

        if (place.country != null && place.country!.trim().isNotEmpty)
          place.country!.trim(),
      ];

      if (addressParts.isEmpty) {
        return null;
      }

      return addressParts.join(', ');
    } catch (e) {
      debugPrint('Address lookup error: $e');

      return null;
    }
  }

  // ============================================================
  // LIVE GPS LOCATION AND MAP PICKER
  // ============================================================

  Future<void> _openMapPicker() async {
    // If the image already supplied a suggested location (camera GPS or
    // gallery EXIF), open the map at that location. Otherwise use current
    // GPS only as the map's starting point; the user must tap to place a pin.
    LatLng? mapCenter = _selectedLocation;

    if (mapCenter == null) {
      setState(() => _isLocating = true);
      mapCenter = await _getCurrentDeviceLocation();
      if (!mounted) return;
      setState(() => _isLocating = false);
    }

    if (!mounted) return;

    final bool requireManualPin = _selectedLocation == null;

    final LatLng? result = await showDialog<LatLng>(
      context: context,
      builder: (dialogContext) {
        return MapLocationPicker(
          initialLocation: mapCenter,
          requireMapTap: requireManualPin,
          hasLiveLocation: mapCenter != null,
        );
      },
    );

    if (result == null || !mounted) return;

    await _setSuggestedLocation(result);
    if (mounted) setState(() => _locationNote = 'Location pinned on the map.');

    if (_selectedAddress == null || _selectedAddress!.trim().isEmpty) {
      _showMessage(
        'Location pinned, but the address could not be determined. '
        'Please try selecting the location again.',
      );
    }
  }

  // ============================================================
  // GET CATEGORY ID
  // ============================================================

  String _getCategoryId(String category) {
    switch (category) {
      case 'Waste Accumulation':
        return 'CATE001';

      case 'Blocked Drainage':
        return 'CATE002';

      case 'Road Potholes':
        return 'CATE003';

      case 'Others':
        return 'CATE004';

      default:
        return 'CATE004';
    }
  }

  // ============================================================
  // SUBMIT REPORT
  // ============================================================

  Future<void> _submitReport() async {
    // ----------------------------------------------------------
    // CHECK IMAGE
    // ----------------------------------------------------------

    if (_selectedImageBytes == null) {
      await _showFormPrompt(
        icon: Icons.add_a_photo_outlined,
        title: 'Add a photo',
        message: 'Please take or upload a photo of the issue first.',
      );

      return;
    }

    // ----------------------------------------------------------
    // CHECK CATEGORY + LOCATION (prompt for whichever is missing)
    // ----------------------------------------------------------

    final bool missingCategory = _selectedCategory == null;
    final bool missingLocation = _selectedLocation == null;

    if (missingCategory || missingLocation) {
      setState(() => _showMissingFields = true);

      final String title;
      final String message;
      final IconData icon;

      if (missingCategory && missingLocation) {
        title = 'Select a category and location';
        message =
            'Please choose the issue category and pin the location of the '
            'issue on the map before submitting.';
        icon = Icons.checklist_rounded;
      } else if (missingCategory) {
        title = 'Select a category';
        message =
            'Please choose the issue category before submitting your report.';
        icon = Icons.category_outlined;
      } else {
        title = 'Select a location';
        message =
            'Please pin the location of the issue on the map before '
            'submitting your report.';
        icon = Icons.location_on_outlined;
      }

      final bool pinNow = await _showFormPrompt(
        icon: icon,
        title: title,
        message: message,
        actionLabel: missingLocation ? 'Pin Location' : null,
      );

      if (pinNow && mounted) {
        await _openMapPicker();
      }

      return;
    }

    // ----------------------------------------------------------
    // CHECK ADDRESS
    // ----------------------------------------------------------

    if (_selectedAddress == null || _selectedAddress!.trim().isEmpty) {
      final bool pinAgain = await _showFormPrompt(
        icon: Icons.wrong_location_outlined,
        title: 'Address not found',
        message:
            'We could not determine the address of the pinned location. '
            'Please pin the location again.',
        actionLabel: 'Pin Again',
      );

      if (pinAgain && mounted) {
        await _openMapPicker();
      }

      return;
    }

    // ----------------------------------------------------------
    // CHECK DESCRIPTION
    // ----------------------------------------------------------

    final String description = _descriptionController.text.trim();

    if (_descriptionRequired && description.isEmpty) {
      // Shown under the description field ("Add a description").
      setState(() => _showMissingFields = true);
      return;
    }

    if (description.length > 300) {
      await _showFormPrompt(
        icon: Icons.notes_rounded,
        title: 'Description too long',
        message: 'Please keep the description within 300 characters.',
      );

      return;
    }

    // ----------------------------------------------------------
    // PREVENT MULTIPLE SUBMISSIONS
    // ----------------------------------------------------------

    if (_isSubmitting) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      // --------------------------------------------------------
      // GET CATEGORY ID
      // --------------------------------------------------------

      final String categoryID = _getCategoryId(_selectedCategory!);

      // --------------------------------------------------------
      // CREATE MULTIPART REQUEST
      // --------------------------------------------------------

      final request = http.MultipartRequest('POST', Uri.parse(submitReportUrl));

      // --------------------------------------------------------
      // ADD USER INFORMATION
      // --------------------------------------------------------

      request.fields['userID'] = widget.userID;

      request.fields['barangayID'] = widget.barangayID;

      // --------------------------------------------------------
      // ADD CATEGORY
      // --------------------------------------------------------

      request.fields['categoryID'] = categoryID;

      // --------------------------------------------------------
      // ADD DESCRIPTION
      // --------------------------------------------------------

      request.fields['description'] = description;

      // --------------------------------------------------------
      // ADD LOCATION
      // --------------------------------------------------------

      request.fields['latitude'] = _selectedLocation!.latitude.toString();

      request.fields['longitude'] = _selectedLocation!.longitude.toString();

      // --------------------------------------------------------
      // ADD ADDRESS
      // --------------------------------------------------------

      request.fields['address'] = _selectedAddress!.trim();

      // --------------------------------------------------------
      // ADD IMAGE
      // --------------------------------------------------------

      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          _selectedImageBytes!,
          filename: 'report_image.jpg',
        ),
      );

      // --------------------------------------------------------
      // DEBUG INFORMATION
      // --------------------------------------------------------

      debugPrint('Submitting report...');

      debugPrint('userID: ${widget.userID}');

      debugPrint('barangayID: ${widget.barangayID}');

      debugPrint('categoryID: $categoryID');

      debugPrint('latitude: ${_selectedLocation!.latitude}');

      debugPrint('longitude: ${_selectedLocation!.longitude}');

      debugPrint('address: ${_selectedAddress!.trim()}');

      // --------------------------------------------------------
      // SEND REQUEST
      // --------------------------------------------------------

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 60),
      );

      final response = await http.Response.fromStream(streamedResponse);

      debugPrint(
        'Submit report status: '
        '${response.statusCode}',
      );

      debugPrint(
        'Submit report response: '
        '${response.body}',
      );

      // --------------------------------------------------------
      // CHECK HTTP RESPONSE
      // --------------------------------------------------------

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          'Submit report HTTP ${response.statusCode}: ${response.body}',
        );
        throw Exception(
          FriendlyErrors.fromResponse(
            response,
            fallback: 'Your report could not be sent. Please try again.',
          ),
        );
      }

      // --------------------------------------------------------
      // DECODE JSON
      // --------------------------------------------------------

      final dynamic decoded;

      try {
        decoded = jsonDecode(response.body);
      } catch (e) {
        throw Exception(FriendlyErrors.server);
      }

      if (decoded is! Map<String, dynamic>) {
        throw Exception(FriendlyErrors.server);
      }

      // --------------------------------------------------------
      // CHECK SUCCESS
      // --------------------------------------------------------

      final bool success = decoded['success'] == true;

      if (!success) {
        throw Exception(
          FriendlyErrors.fromMessage(
            decoded['message']?.toString(),
            fallback: 'Your report could not be sent. Please try again.',
          ),
        );
      }

      // --------------------------------------------------------
      // GET REPORT ID
      // --------------------------------------------------------

      String reportID = '';

      final dynamic data = decoded['data'];

      if (data is Map<String, dynamic>) {
        reportID = data['reportID']?.toString() ?? '';
      }

      if (!mounted) {
        return;
      }

      // --------------------------------------------------------
      // CLOSE REPORT OVERLAY
      // --------------------------------------------------------

      Navigator.of(context).pop();

      // --------------------------------------------------------
      // SHOW SUCCESS MESSAGE
      // --------------------------------------------------------

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            reportID.isNotEmpty
                ? 'Report $reportID submitted successfully.'
                : 'Report submitted successfully.',
          ),
        ),
      );
    } on TimeoutException {
      if (!mounted) {
        return;
      }

      _showMessage(
        'The request took too long. '
        'Please check your connection and try again.',
      );
    } catch (e) {
      debugPrint('Submit report error: $e');

      if (!mounted) {
        return;
      }

      _showMessage(FriendlyErrors.fromException(e));
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  // ============================================================
  // SHOW MESSAGE
  // ============================================================

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ============================================================
  // FORM PROMPT (visible on top of this dialog, unlike snackbars)
  // Returns true when the user taps the action button.
  // ============================================================

  Future<bool> _showFormPrompt({
    required IconData icon,
    required String title,
    required String message,
    String? actionLabel,
  }) async {
    if (!mounted) return false;

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(icon, color: AppColors.primary, size: 32),
        title: Text(title, textAlign: TextAlign.center),
        content: Text(message, textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              actionLabel == null ? 'OK' : 'Later',
              style: TextStyle(
                color: actionLabel == null
                    ? AppColors.primary
                    : AppColors.textSecondary,
              ),
            ),
          ),
          if (actionLabel != null)
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(actionLabel),
            ),
        ],
      ),
    );

    return result ?? false;
  }

  // ============================================================
  // LOCATION PREVIEW (small map shown after a location is pinned)
  // ============================================================

  Widget _buildLocationPreview() {
    final LatLng point = _selectedLocation!;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: SizedBox(
        height: 150,
        width: double.infinity,
        child: Stack(
          children: [
            // Key on the coordinates so the map re-centres when the pin moves.
            FlutterMap(
              key: ValueKey('${point.latitude},${point.longitude}'),
              options: MapOptions(
                initialCenter: point,
                initialZoom: 16,
                // Preview only: no panning or zooming inside the form.
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.none,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.citisense',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: point,
                      width: 44,
                      height: 52,
                      alignment: Alignment.topCenter,
                      child: const Icon(
                        Icons.location_on,
                        size: 44,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // Tap anywhere on the preview to adjust the pin.
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _isSubmitting || _isLocating ? null : _openMapPicker,
                ),
              ),
            ),

            Positioned(
              right: 8,
              bottom: 8,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: AppShadows.soft,
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.edit_location_alt_outlined,
                        size: 14,
                        color: AppColors.primary,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Tap to adjust',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // CATEGORY ICON
  // ============================================================

  IconData _categoryIcon(String? category) {
    switch (category) {
      case 'Waste Accumulation':
        return Icons.delete_outline;
      case 'Blocked Drainage':
        return Icons.water_drop_outlined;
      case 'Road Potholes':
        return Icons.warning_amber_rounded;
      case 'Others':
        return Icons.more_horiz_rounded;
      default:
        return Icons.category_outlined;
    }
  }

  // ============================================================
  // SECTION TITLE
  // ============================================================

  Widget _buildSectionTitle(String number, String title) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: primaryBlue,
            shape: BoxShape.circle,
          ),
          child: Text(
            number,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),

        const SizedBox(width: 12),

        Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: darkBlue,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // FIELD DECORATION
  // ============================================================

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: const BorderSide(color: AppColors.border),
      ),
    );
  }

  // ============================================================
  // BUILD REPORT OVERLAY
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    const fieldBlue = AppColors.primary;
    const navy = AppColors.ink;
    const muted = AppColors.textSecondary;
    const borderBlue = AppColors.border;

    Widget sectionHeading(String number, String name, {Widget? trailing}) {
      return Row(
        children: [
          Container(
            width: 27,
            height: 27,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: fieldBlue,
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                color: navy,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      );
    }

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 620,
          maxHeight: screen.height - 36,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: AppColors.shadow.withValues(alpha: 0.13),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          // Inside the blue frame: the header and the form are two separate
          // rounded panels with a small gap, so the header reads as its own
          // group instead of being glued onto the form.
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Report an Issue',
                              style: TextStyle(
                                color: fieldBlue,
                                fontSize: 24,
                                height: 1.15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Help us keep our community safe and clean!',
                              style: TextStyle(
                                color: navy,
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: 8),
                      // Mascot taking a photo with a phone (loops).
                      SizedBox(
                        width: 96,
                        height: 104,
                        child: CitiMascot(pose: MascotPose.camera),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 9),
                Flexible(
                  child: Container(
                    width: double.infinity,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          sectionHeading('1', 'Upload Photo'),
                          const SizedBox(height: 12),
                          InkWell(
                            onTap: _isSubmitting || _isAnalyzing
                                ? null
                                : _showImageSourceOptions,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            child: Container(
                              width: double.infinity,
                              height: 165,
                              clipBehavior: Clip.antiAlias,
                              decoration: BoxDecoration(
                                color: AppColors.primarySoft,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.md,
                                ),
                                border: Border.all(
                                  color: AppColors.primaryBorder,
                                ),
                              ),
                              child: _selectedImageBytes != null
                                  ? Image.memory(
                                      _selectedImageBytes!,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                    )
                                  : const Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.add_a_photo_outlined,
                                          color: fieldBlue,
                                          size: 38,
                                        ),
                                        SizedBox(height: 9),
                                        Text(
                                          'Tap to upload a photo',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: navy,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                          if (_isAnalyzing || _aiMessage != null) ...[
                            const SizedBox(height: 9),
                            if (_isAnalyzing)
                              const Row(
                                children: [
                                  SizedBox(
                                    width: 15,
                                    height: 15,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'AI is analyzing the photo...',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: muted,
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            else
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.accentSoft,
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.sm,
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.auto_awesome,
                                      size: 16,
                                      color: AppColors.accent,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _aiMessage!,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          height: 1.4,
                                          color: navy,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                          const SizedBox(height: 26),
                          sectionHeading(
                            '2',
                            'Issue Category',
                            trailing: !_aiEnabled
                                ? null
                                : Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.accentSoft,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.auto_awesome,
                                          size: 14,
                                          color: AppColors.accent,
                                        ),
                                        SizedBox(width: 5),
                                        Text(
                                          'AI Suggestion',
                                          style: TextStyle(
                                            color: AppColors.accent,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: _selectedCategory,
                            isExpanded: true,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: AppColors.surfaceMuted,
                              prefixIcon: Icon(
                                _categoryIcon(_selectedCategory),
                                color: fieldBlue,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 16,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  AppRadius.sm,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  AppRadius.sm,
                                ),
                                borderSide: const BorderSide(color: borderBlue),
                              ),
                              errorText:
                                  _showMissingFields &&
                                      _selectedCategory == null
                                  ? 'Please select a category.'
                                  : null,
                            ),
                            hint: const Text(
                              'Select category',
                              style: TextStyle(color: muted),
                            ),
                            items: _categories
                                .map(
                                  (category) => DropdownMenuItem<String>(
                                    value: category,
                                    child: Text(
                                      category,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: navy,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: _isSubmitting || _isAnalyzing
                                ? null
                                : (value) {
                                    setState(() => _selectedCategory = value);
                                  },
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _aiEnabled
                                ? 'You can change the category if needed.'
                                : 'AI Insights is off. Please choose a category.',
                            style: const TextStyle(color: muted, fontSize: 12),
                          ),
                          const SizedBox(height: 26),
                          sectionHeading('3', 'Location'),
                          const SizedBox(height: 12),
                          if (_selectedLocation != null) ...[
                            _buildLocationPreview(),
                            const SizedBox(height: 10),
                          ],
                          OutlinedButton(
                            onPressed: _isSubmitting || _isLocating
                                ? null
                                : _openMapPicker,
                            style: OutlinedButton.styleFrom(
                              backgroundColor: AppColors.surfaceMuted,
                              minimumSize: const Size(double.infinity, 57),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 15,
                              ),
                              side: BorderSide(
                                color:
                                    _showMissingFields &&
                                        _selectedLocation == null
                                    ? AppColors.danger
                                    : borderBlue,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppRadius.sm,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                _isLocating
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.4,
                                        ),
                                      )
                                    : Icon(
                                        _selectedLocation == null
                                            ? Icons.location_on_outlined
                                            : Icons.where_to_vote_rounded,
                                        color: _selectedLocation == null
                                            ? fieldBlue
                                            : AppColors.success,
                                        size: 27,
                                      ),
                                const SizedBox(width: 13),
                                Expanded(
                                  child: Text(
                                    _isLocating
                                        ? 'Getting your location...'
                                        : _selectedLocation == null
                                        ? 'Set Location on Map'
                                        : 'Location pinned (tap to change)',
                                    style: const TextStyle(
                                      color: navy,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const Icon(Icons.chevron_right, color: navy),
                              ],
                            ),
                          ),
                          if (_selectedLocation != null) ...[
                            if (_selectedAddress != null &&
                                _selectedAddress!.trim().isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.place_outlined,
                                    size: 16,
                                    color: AppColors.success,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      _selectedAddress!,
                                      style: const TextStyle(
                                        color: navy,
                                        fontSize: 12,
                                        height: 1.4,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 6),
                            Text(
                              'Latitude: ${_selectedLocation!.latitude.toStringAsFixed(6)}  '
                              'Longitude: ${_selectedLocation!.longitude.toStringAsFixed(6)}',
                              style: const TextStyle(
                                color: muted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            _showMissingFields && _selectedLocation == null
                                ? 'Please pin the location of the issue.'
                                : _locationNote ??
                                      'Tap to pin the exact location of the issue.',
                            style: TextStyle(
                              color:
                                  _showMissingFields &&
                                      _selectedLocation == null
                                  ? AppColors.danger
                                  : _selectedLocation == null &&
                                        _locationNote != null
                                  ? AppColors.warning
                                  : muted,
                              fontSize: 12,
                              fontWeight:
                                  _locationNote != null ||
                                      (_showMissingFields &&
                                          _selectedLocation == null)
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                          const SizedBox(height: 26),
                          sectionHeading(
                            '4',
                            _descriptionRequired
                                ? 'Description (required)'
                                : 'Description',
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _descriptionController,
                            enabled: !_isSubmitting,
                            maxLength: 300,
                            maxLines: 5,
                            minLines: 4,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              hintText: _descriptionRequired
                                  ? 'Describe the issue (required for "Others")'
                                  : 'Please describe the issue...',
                              hintStyle: const TextStyle(color: muted),
                              filled: true,
                              fillColor: AppColors.surfaceMuted,
                              counterText: '',
                              contentPadding: const EdgeInsets.all(16),
                              errorText: _descriptionError,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  AppRadius.sm,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  AppRadius.sm,
                                ),
                                borderSide: const BorderSide(color: borderBlue),
                              ),
                              errorBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  AppRadius.sm,
                                ),
                                borderSide: const BorderSide(
                                  color: AppColors.danger,
                                  width: 1.4,
                                ),
                              ),
                              focusedErrorBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  AppRadius.sm,
                                ),
                                borderSide: const BorderSide(
                                  color: AppColors.danger,
                                  width: 1.8,
                                ),
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              '${_descriptionController.text.length}/300',
                              style: const TextStyle(
                                color: muted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(height: 22),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _isSubmitting
                                      ? null
                                      : () => Navigator.of(context).pop(),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(0, 54),
                                    side: const BorderSide(color: fieldBlue),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        AppRadius.sm,
                                      ),
                                    ),
                                  ),
                                  child: const Text(
                                    'Cancel',
                                    style: TextStyle(
                                      color: fieldBlue,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _isSubmitting || _isAnalyzing
                                      ? null
                                      : _submitReport,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: fieldBlue,
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size(0, 54),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        AppRadius.sm,
                                      ),
                                    ),
                                  ),
                                  child: _isSubmitting
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text(
                                          'Submit Report',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// MAP LOCATION PICKER
// ============================================================

class MapLocationPicker extends StatefulWidget {
  final LatLng? initialLocation;
  final bool requireMapTap;
  final bool hasLiveLocation;

  const MapLocationPicker({
    super.key,
    this.initialLocation,
    this.requireMapTap = false,
    this.hasLiveLocation = true,
  });

  @override
  State<MapLocationPicker> createState() => _MapLocationPickerState();
}

class _MapLocationPickerState extends State<MapLocationPicker> {
  static const LatLng _defaultLocation = LatLng(10.3157, 123.8854);

  LatLng? _selectedLocation;

  late LatLng _currentLocation;

  late final MapController _mapController;

  @override
  void initState() {
    super.initState();

    _currentLocation = widget.initialLocation ?? _defaultLocation;

    // When manual pinning is required, do not preselect the map center.
    // This prevents the phone's current position from being submitted
    // accidentally as the issue location.
    _selectedLocation = widget.requireMapTap
        ? null
        : (widget.initialLocation ?? _currentLocation);

    _mapController = MapController();
  }

  // ==========================================================
  // RECENTER MAP
  // ==========================================================

  void _recenterMap() {
    _mapController.move(_currentLocation, 16);
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,

      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,

        child: Column(
          children: [
            // ==================================================
            // HEADER
            // ==================================================
            Padding(
              padding: const EdgeInsets.all(16),

              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Pin Issue Location',

                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                  ),

                  IconButton(
                    onPressed: () => Navigator.pop(context),

                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),

            // ==================================================
            // INSTRUCTIONS
            // ==================================================
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),

              child: Text(
                widget.hasLiveLocation
                    ? 'The map starts at your current location. '
                          'Tap the map to pin the exact place where '
                          'the issue was found.'
                    : 'Your current location is unavailable, so the map '
                          'starts at Cebu City. Tap the map to pin the '
                          'exact place where the issue was found.',
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: AppColors.textSecondary,
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ==================================================
            // MAP
            // ==================================================
            Expanded(
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,

                    options: MapOptions(
                      initialCenter: _currentLocation,

                      initialZoom: 16,

                      onTap: (tapPosition, point) {
                        setState(() {
                          _selectedLocation = point;
                        });
                      },
                    ),

                    children: [
                      // ----------------------------------------
                      // OPENSTREETMAP
                      // ----------------------------------------
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',

                        userAgentPackageName: 'com.example.citisense',
                      ),

                      // ----------------------------------------
                      // SELECTED LOCATION MARKER
                      // ----------------------------------------
                      MarkerLayer(
                        markers: [
                          // Blue dot: the user's live location.
                          if (widget.hasLiveLocation)
                            Marker(
                              point: _currentLocation,
                              width: 22,
                              height: 22,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 3,
                                  ),
                                  boxShadow: AppShadows.soft,
                                ),
                              ),
                            ),
                          if (_selectedLocation != null)
                            Marker(
                              point: _selectedLocation!,
                              width: 50,
                              height: 60,
                              child: const Icon(
                                Icons.location_on,
                                size: 48,
                                color: AppColors.primary,
                              ),
                            ),
                        ],
                      ),

                      // ----------------------------------------
                      // ATTRIBUTION
                      // ----------------------------------------
                      RichAttributionWidget(
                        attributions: [
                          TextSourceAttribution('© OpenStreetMap contributors'),
                        ],
                      ),
                    ],
                  ),

                  // ==================================================
                  // RECENTER BUTTON
                  // ==================================================
                  Positioned(
                    right: 15,
                    bottom: 25,

                    child: FloatingActionButton.small(
                      heroTag: 'recenterLocation',

                      backgroundColor: Colors.white,

                      foregroundColor: AppColors.primary,

                      onPressed: _recenterMap,

                      child: const Icon(Icons.my_location),
                    ),
                  ),
                ],
              ),
            ),

            // ==================================================
            // COORDINATES + CONFIRM
            // ==================================================
            Padding(
              padding: const EdgeInsets.all(16),

              child: Column(
                children: [
                  Text(
                    _selectedLocation == null
                        ? 'Tap the map to pin the issue location.'
                        : 'Latitude: '
                              '${_selectedLocation!.latitude.toStringAsFixed(6)}\n'
                              'Longitude: '
                              '${_selectedLocation!.longitude.toStringAsFixed(6)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),

                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _selectedLocation == null
                          ? null
                          : () {
                              Navigator.pop(context, _selectedLocation);
                            },
                      child: const Text('Confirm Location'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
