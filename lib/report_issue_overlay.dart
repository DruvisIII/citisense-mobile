import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:exif/exif.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

// ============================================================
// AI CLASSIFICATION BACKEND
// ============================================================
//
// Replace this later with your actual YOLOv11 backend URL.
//
// Example:
// const String aiClassificationUrl =
//     'http://192.168.1.48:5000/classify';
//
const String aiClassificationUrl =
    'http://192.168.1.20/citisense/api/classify_image.php';

// ============================================================
// REPORT SUBMISSION BACKEND
// ============================================================

const String submitReportUrl =
    'http://192.168.1.20/citisense/api/submit_report.php';
//'http://192.168.1.48/citisense/api/submit_report.php';
//'http://10.127.214.252/citisense/api/submit_report.php';
//'http://192.168.83.252/citisense/api/submit_report.php';
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
  //
  // Uint8List works on:
  //
  // Android
  // iOS
  // Web
  // Desktop
  //
  Uint8List? _selectedImageBytes;

  // Remembers whether the image came from the camera or gallery.
  ImageSource? _selectedImageSource;

  String? _selectedCategory;

  LatLng? _selectedLocation;

  // ============================================================
  // SELECTED ADDRESS
  // ============================================================
  //
  // This is automatically obtained from the selected
  // latitude and longitude using reverse geocoding.
  //
  String? _selectedAddress;

  bool _isAnalyzing = false;
  bool _isSubmitting = false;

  String? _aiMessage;

  static const Color primaryBlue = Color(0xFF2563D9);
  static const Color darkBlue = Color(0xFF173D78);

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
      final XFile? image = await _picker.pickImage(
        source: source,
        // Keep the original image so gallery EXIF GPS metadata is not
        // discarded by image-picker compression before we read it.
        imageQuality: null,
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
      });

      // Camera photos use the phone's current GPS position.
      // Gallery photos use GPS coordinates embedded in EXIF, if available.
      LatLng? suggestedLocation;

      if (source == ImageSource.camera) {
        suggestedLocation = await _getCurrentDeviceLocation();
        if (suggestedLocation == null && mounted) {
          _showMessage(
            'Photo selected, but current location could not be obtained. '
            'Please pin the issue location manually.',
          );
        }
      } else {
        suggestedLocation = await _getGpsLocationFromExif(imageBytes);
        if (suggestedLocation == null && mounted) {
          _showMessage(
            'This photo has no GPS location data. '
            'Please pin the issue location manually.',
          );
        }
      }

      if (suggestedLocation != null && mounted) {
        await _setSuggestedLocation(suggestedLocation);
      }

      await _analyzeImage(imageBytes);
    } catch (e) {
      debugPrint('Image selection error: $e');
      _showMessage('Unable to select the photo.');
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
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showMessage('Please turn on your device location services.');
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showMessage(
          'Location permission is unavailable. '
          'Please pin the issue location manually.',
        );
        return null;
      }

      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );

      return LatLng(position.latitude, position.longitude);
    } on TimeoutException {
      _showMessage('Getting your current location took too long.');
      return null;
    } catch (e) {
      debugPrint('Current location error: $e');
      return null;
    }
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
      // Create multipart request to the PHP Gemini backend.
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

      debugPrint('Gemini HTTP Status: ${response.statusCode}');
      debugPrint('Gemini Response: ${response.body}');

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

      // Read Gemini's predicted category.
      final String predictedCategory = (decoded['category'] ?? '')
          .toString()
          .trim();

      // Match Gemini's category names with CitiSense categories.
      // PHP returns "Potholes"; CitiSense uses "Road Potholes".
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
      debugPrint('Gemini classification timed out.');

      if (!mounted) return;

      setState(() {
        _aiMessage =
            'AI analysis took too long. Please select a category manually.';
      });
    } catch (e) {
      debugPrint('Gemini classification error: $e');

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
      mapCenter = await _getCurrentDeviceLocation();
    }

    if (!mounted) return;

    final bool requireManualPin = _selectedLocation == null;

    final LatLng? result = await showDialog<LatLng>(
      context: context,
      builder: (dialogContext) {
        return MapLocationPicker(
          initialLocation: mapCenter,
          requireMapTap: requireManualPin,
        );
      },
    );

    if (result == null || !mounted) return;

    await _setSuggestedLocation(result);

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
      _showMessage('Please upload a photo first.');

      return;
    }

    // ----------------------------------------------------------
    // CHECK CATEGORY
    // ----------------------------------------------------------

    if (_selectedCategory == null) {
      _showMessage('Please select an issue category.');

      return;
    }

    // ----------------------------------------------------------
    // CHECK LOCATION
    // ----------------------------------------------------------

    if (_selectedLocation == null) {
      _showMessage('Please pin the issue location on the map.');

      return;
    }

    // ----------------------------------------------------------
    // CHECK ADDRESS
    // ----------------------------------------------------------

    if (_selectedAddress == null || _selectedAddress!.trim().isEmpty) {
      _showMessage(
        'Unable to determine the address. '
        'Please pin the location again.',
      );

      return;
    }

    // ----------------------------------------------------------
    // CHECK DESCRIPTION
    // ----------------------------------------------------------

    final String description = _descriptionController.text.trim();

    if (description.length > 300) {
      _showMessage('Description must not exceed 300 characters.');

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
      //
      // This is the address obtained from the selected
      // GPS coordinates.
      //

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
        throw Exception(
          'Server returned HTTP '
          '${response.statusCode}.',
        );
      }

      // --------------------------------------------------------
      // DECODE JSON
      // --------------------------------------------------------

      final dynamic decoded;

      try {
        decoded = jsonDecode(response.body);
      } catch (e) {
        throw Exception('The server returned an invalid response.');
      }

      if (decoded is! Map<String, dynamic>) {
        throw Exception('Invalid server response.');
      }

      // --------------------------------------------------------
      // CHECK SUCCESS
      // --------------------------------------------------------

      final bool success = decoded['success'] == true;

      if (!success) {
        final String message =
            decoded['message']?.toString() ?? 'Failed to submit the report.';

        throw Exception(message);
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

      _showMessage(e.toString().replaceFirst('Exception: ', ''));
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

      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),

      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),

        borderSide: const BorderSide(color: Color(0xFFB9D1F0)),
      ),
    );
  }

  // ============================================================
  // BUILD REPORT OVERLAY
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    const fieldBlue = Color(0xFF2875E9);
    const navy = Color(0xFF102852);
    const muted = Color(0xFF60738D);
    const borderBlue = Color(0xFFBDD5E8);

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
            color: const Color(0xFF216BDD),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.13),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Blue frame around the rounded white introduction area.
              Padding(
                padding: const EdgeInsets.fromLTRB(9, 11, 9, 0),
                child: Container(
                  height: 174,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF9FBFF),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(29),
                    ),
                  ),
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 28, 125, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Report an Issue',
                              maxLines: 2,
                              style: TextStyle(
                                color: fieldBlue,
                                fontSize: 24,
                                height: 1.1,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 14),
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
                      // Replace this container with Image.asset later.
                      Positioned(
                        right: 15,
                        bottom: 10,
                        child: Container(
                          width: 105,
                          height: 112,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE6F2FF),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: borderBlue),
                          ),
                          child: const Text(
                            'Mascot\nplaceholder',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: muted),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Flexible(
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(31),
                      bottom: Radius.circular(30),
                    ),
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
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            width: double.infinity,
                            height: 165,
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F6FC),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: borderBlue),
                            ),
                            child: _selectedImageBytes != null
                                ? Image.memory(
                                    _selectedImageBytes!,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                  )
                                : const Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
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
                                  child: Text('AI is analyzing the photo...'),
                                ),
                              ],
                            )
                          else
                            Text(
                              _aiMessage!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: muted,
                              ),
                            ),
                        ],
                        const SizedBox(height: 26),
                        sectionHeading(
                          '2',
                          'Issue Category',
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF4FF),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.auto_awesome,
                                  size: 14,
                                  color: fieldBlue,
                                ),
                                SizedBox(width: 5),
                                Text(
                                  'AI Suggestion',
                                  style: TextStyle(
                                    color: fieldBlue,
                                    fontSize: 11,
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
                            fillColor: const Color(0xFFF3F7FD),
                            prefixIcon: const Icon(
                              Icons.delete_outline,
                              color: fieldBlue,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 16,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(13),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(13),
                              borderSide: const BorderSide(color: borderBlue),
                            ),
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
                        const Text(
                          'You can change the category if needed.',
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                        const SizedBox(height: 26),
                        sectionHeading('3', 'Location'),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: _isSubmitting ? null : _openMapPicker,
                          style: OutlinedButton.styleFrom(
                            backgroundColor: const Color(0xFFF7FAFE),
                            minimumSize: const Size(double.infinity, 57),
                            padding: const EdgeInsets.symmetric(horizontal: 15),
                            side: const BorderSide(color: borderBlue),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(13),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.location_on_outlined,
                                color: fieldBlue,
                                size: 27,
                              ),
                              const SizedBox(width: 13),
                              Expanded(
                                child: Text(
                                  _selectedLocation == null
                                      ? 'Set Location on Map'
                                      : 'Location pinned',
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
                          const SizedBox(height: 7),
                          Text(
                            'Latitude: ${_selectedLocation!.latitude.toStringAsFixed(6)}  '
                            'Longitude: ${_selectedLocation!.longitude.toStringAsFixed(6)}',
                            style: const TextStyle(color: muted, fontSize: 11),
                          ),
                        ],
                        const SizedBox(height: 8),
                        const Text(
                          'Tap to pin the exact location of the issue.',
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                        const SizedBox(height: 26),
                        sectionHeading('4', 'Description'),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _descriptionController,
                          enabled: !_isSubmitting,
                          maxLength: 300,
                          maxLines: 5,
                          minLines: 4,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Please describe the issue...',
                            hintStyle: const TextStyle(color: muted),
                            filled: true,
                            fillColor: const Color(0xFFF6F9FE),
                            counterText: '',
                            contentPadding: const EdgeInsets.all(16),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(13),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(13),
                              borderSide: const BorderSide(color: borderBlue),
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            '${_descriptionController.text.length}/300',
                            style: const TextStyle(color: muted, fontSize: 12),
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
                                    borderRadius: BorderRadius.circular(15),
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
                                    borderRadius: BorderRadius.circular(15),
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
    );
  }
}

// ============================================================
// MAP LOCATION PICKER
// ============================================================

class MapLocationPicker extends StatefulWidget {
  final LatLng? initialLocation;
  final bool requireMapTap;

  const MapLocationPicker({
    super.key,
    this.initialLocation,
    this.requireMapTap = false,
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
                        fontWeight: FontWeight.bold,
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
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),

              child: Text(
                'The map starts at your current location. '
                'Tap the map to pin the exact place where '
                'the issue was found.',
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
                        markers: _selectedLocation == null
                            ? []
                            : [
                                Marker(
                                  point: _selectedLocation!,
                                  width: 50,
                                  height: 60,
                                  child: const Icon(
                                    Icons.location_on,
                                    size: 48,
                                    color: Color(0xFF2563D9),
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

                      foregroundColor: const Color(0xFF2563D9),

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
                  ),

                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
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
