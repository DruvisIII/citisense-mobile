import 'dart:async';
import 'package:citisense/api_config.dart';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:citisense/app_theme.dart';
import 'package:citisense/ui_components.dart';
import 'package:citisense/live_updates.dart';
import 'package:citisense/report_engagement.dart';
import 'package:citisense/mascot.dart';
import 'package:http/http.dart' as http;

// Parses MySQL/PHP date values consistently. Values without an explicit
// timezone are treated as local device time (the usual SQL DATETIME format).
DateTime? _parseReportDateTime(dynamic value) {
  if (value == null) return null;

  final rawValue = value.toString().trim();
  if (rawValue.isEmpty) return null;

  return DateTime.tryParse(rawValue.replaceFirst(' ', 'T'));
}

// The admin-set resolution deadline, or null when the admin has not set
// one yet. Empty values, zero dates (0000-00-00) and deadlines that are not
// after the submission date are treated as "not set".
DateTime? _getAdminTimeline(Map<String, dynamic> report) {
  final timeline = _parseReportDateTime(report['timeline']);
  final dateReported = _parseReportDateTime(report['dateReported']);

  if (timeline == null || timeline.year < 2000) {
    return null;
  }
  if (dateReported != null && !timeline.isAfter(dateReported)) {
    return null;
  }
  return timeline;
}

// A report is overdue only when its deadline is valid, comes after the
// submission date, and has already passed. This prevents an invalid/past
// timeline returned by the API from immediately marking a new report overdue.
String _getEffectiveReportStatusID(Map<String, dynamic> report) {
  final statusID = report['statusID']?.toString() ?? '';

  if (statusID != 'STAT001' && statusID != 'STAT002') {
    return statusID;
  }

  final dateReported = _parseReportDateTime(report['dateReported']);
  final timeline = _parseReportDateTime(report['timeline']);

  if (dateReported == null || timeline == null) {
    return statusID;
  }

  // A resolution deadline should never be earlier than the report itself.
  if (!timeline.isAfter(dateReported)) {
    debugPrint(
      'Invalid report timeline: deadline $timeline is not after '
      'date reported $dateReported for ${report['reportID']}',
    );
    return statusID;
  }

  return DateTime.now().isAfter(timeline) ? 'STAT004' : statusID;
}

// ============================================================
// REPORT CATEGORY, STATUS AND ADDRESS (shared by the list and details)
// ============================================================

/// How a report category looks: its own icon and color, so the type is
/// recognizable by the icon as well as the color.
class ReportCategoryStyle {
  const ReportCategoryStyle({
    required this.label,
    required this.icon,
    required this.color,
    required this.softColor,
  });

  /// Category name without the word "Report" ("Waste Accumulation").
  final String label;
  final IconData icon;
  final Color color;
  final Color softColor;

  static ReportCategoryStyle of(Map<String, dynamic> report) {
    final name = (report['categoryName']?.toString() ?? '').trim();
    final lower = name.toLowerCase();

    if (lower.contains('waste') ||
        lower.contains('garbage') ||
        lower.contains('trash')) {
      return ReportCategoryStyle(
        label: name.isEmpty ? 'Waste Accumulation' : name,
        icon: Icons.delete_outline_rounded,
        color: AppColors.primary,
        softColor: AppColors.primarySoft,
      );
    }
    if (lower.contains('pothole') || lower.contains('road')) {
      return ReportCategoryStyle(
        label: name.isEmpty ? 'Pothole' : name,
        icon: Icons.edit_road_rounded,
        color: AppColors.accent,
        softColor: AppColors.accentSoft,
      );
    }
    return ReportCategoryStyle(
      label: name.isEmpty || lower == 'others' || lower == 'other'
          ? 'Other Issue'
          : name,
      icon: Icons.more_horiz_rounded,
      color: const Color(0xFF64748B),
      softColor: const Color(0xFFEEF1F5),
    );
  }
}

/// Current status label and color ("Pending", "Ongoing", "Resolved").
({String label, Color color}) reportStatusOf(Map<String, dynamic> report) {
  switch (_getEffectiveReportStatusID(report)) {
    case 'STAT001':
      return (label: 'Pending', color: AppColors.warning);
    case 'STAT002':
      return (label: 'Ongoing', color: AppColors.primary);
    case 'STAT003':
      return (label: 'Resolved', color: AppColors.success);
    case 'STAT004':
      return (label: 'Overdue', color: AppColors.danger);
  }
  final shown = report['displayStatus']?.toString().trim() ?? '';
  return (
    label: shown.isEmpty ? 'Unknown' : shown,
    color: AppColors.textSecondary,
  );
}

/// A short place name from a full address, e.g.
/// "To-ong Pardo, 7VQ8+JMW To-ong Pardo, Cebu City, Central Visayas,
/// Philippines" -> "To-ong Pardo, Cebu City".
String shortReportAddress(String? address) {
  final full = address?.trim() ?? '';
  if (full.isEmpty) return 'Location unavailable';

  final plusCode = RegExp(
    r'\b[23456789CFGHJMPQRVWX]{4,8}\+[23456789CFGHJMPQRVWX]{2,3}\b',
  );
  final parts = <String>[];
  for (final raw in full.split(',')) {
    final part = raw.replaceAll(plusCode, '').trim();
    if (part.isEmpty) continue;
    if (parts.any((p) => p.toLowerCase() == part.toLowerCase())) continue;
    parts.add(part);
  }
  if (parts.isEmpty) return full;

  final city = parts
      .skip(1)
      .firstWhere(
        (p) => RegExp(
          r'\b(city|municipality)\b',
          caseSensitive: false,
        ).hasMatch(p),
        orElse: () => parts.length > 1 ? parts[1] : '',
      );
  return city.isEmpty ? parts.first : '${parts.first}, $city';
}

/// "Nov 24, 3:19 AM".
String shortReportDateTime(dynamic value) {
  final date = _parseReportDateTime(value);
  if (date == null) return 'Date unavailable';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final minute = date.minute.toString().padLeft(2, '0');
  final period = date.hour >= 12 ? 'PM' : 'AM';
  final year = date.year == DateTime.now().year ? '' : ' ${date.year}';
  return '${months[date.month - 1]} ${date.day}$year, $hour:$minute $period';
}

class MyReportsPage extends StatefulWidget {
  final String userID;
  final String firstName;
  final String barangayID;
  final String barangayName;

  const MyReportsPage({
    super.key,
    required this.userID,
    required this.firstName,
    required this.barangayID,
    required this.barangayName,
  });

  @override
  State<MyReportsPage> createState() => _MyReportsPageState();
}

class _MyReportsPageState extends State<MyReportsPage> {
  static const String _getReportsUrl =
      // 'http://192.168.1.6/citisense/api/get_my_reports.php';
      '$apiBaseUrl/get_my_reports.php';
  // 'http://10.127.214.252/citisense/api/get_my_reports.php';
  //'http://192.168.83.252/citisense/api/get_my_reports.php';
  int _selectedFilter = 1;
  String _searchQuery = '';
  bool _newestFirst = true;

  bool _isLoading = true;
  String? _errorMessage;

  Timer? _refreshTimer;
  StreamSubscription<RemoteMessage>? _foregroundMessages;
  StreamSubscription<RemoteMessage>? _openedMessages;
  bool _refreshInProgress = false;
  bool _appIsActive = true;

  List<Map<String, dynamic>> _reports = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
    _loadReports(showLoading: true);

    // Poll while the Android app is active. This also works if the admin
    // endpoint updates the database without sending an FCM notification.
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && _appIsActive) {
        _loadReports();
      }
    });

    // A delivered Firebase message triggers an immediate server refresh.
    _foregroundMessages = FirebaseMessaging.onMessage.listen((message) {
      debugPrint('My Reports: foreground FCM ${message.messageId}');
      _loadReports();
    });
    _openedMessages = FirebaseMessaging.onMessageOpenedApp.listen((message) {
      debugPrint('My Reports: notification opened ${message.messageId}');
      _loadReports();
    });

    // New report submitted, status changed, or app resumed.
    LiveUpdates.instance.changes.addListener(_onLiveUpdate);
  }

  void _onLiveUpdate() {
    if (mounted) _loadReports();
  }

  // Using a dedicated observer keeps the state lifecycle handling simple.
  late final WidgetsBindingObserver _lifecycleObserver =
      _MyReportsLifecycleObserver((state) {
        if (!mounted) return;
        _appIsActive = state == AppLifecycleState.resumed;
        if (_appIsActive) _loadReports();
      });

  @override
  void didUpdateWidget(covariant MyReportsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userID != widget.userID) {
      _reports = [];
      _errorMessage = null;
      _loadReports(showLoading: true);
    }
  }

  @override
  void dispose() {
    LiveUpdates.instance.changes.removeListener(_onLiveUpdate);
    _refreshTimer?.cancel();
    _foregroundMessages?.cancel();
    _openedMessages?.cancel();
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    super.dispose();
  }

  Future<void> _loadReports({bool showLoading = false}) async {
    // Avoid overlapping requests when polling, pulling to refresh and
    // receiving a push notification happen at roughly the same time.
    if (!mounted || _refreshInProgress) return;
    _refreshInProgress = true;

    if (showLoading && _reports.isEmpty) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final requestUserID = widget.userID;
      final uri = Uri.parse(
        _getReportsUrl,
      ).replace(queryParameters: {'userID': requestUserID});
      final response = await http
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 10));

      debugPrint('My Reports refresh: HTTP ${response.statusCode}');
      if (response.statusCode != 200) {
        throw Exception('Server returned status code ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['success'] != true) {
        throw Exception('Server could not load reports');
      }

      final rawData = decoded['data'];
      if (rawData is! List) {
        throw const FormatException('Expected a list of reports');
      }
      final loadedReports = rawData
          .map<Map<String, dynamic>>(
            (item) => Map<String, dynamic>.from(item as Map),
          )
          .toList();

      for (final report in loadedReports) {
        debugPrint(
          'REPORT ${report['reportID']} | STATUS ${report['statusID']} | '
          'DATE REPORTED ${report['dateReported']} | '
          'TIMELINE ${report['timeline']}',
        );
      }

      if (!mounted || requestUserID != widget.userID) return;
      setState(() {
        _reports = loadedReports;
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (e) {
      debugPrint('My Reports refresh failed: $e');
      if (!mounted) return;
      // Keep already loaded reports instead of blanking the page during
      // a temporary network interruption.
      setState(() {
        _isLoading = false;
        if (_reports.isEmpty) {
          _errorMessage = 'Unable to load your reports.';
        }
      });
    } finally {
      _refreshInProgress = false;
    }
  }

  String _getEffectiveStatusID(Map<String, dynamic> report) {
    return _getEffectiveReportStatusID(report);
  }

  List<Map<String, dynamic>> get _filteredReports {
    final filtered = _reports.where((report) {
      final status = _getEffectiveStatusID(report);
      final matchesStatus =
          _selectedFilter == 0 ||
          (_selectedFilter == 1 &&
              (status == 'STAT001' ||
                  status == 'STAT002' ||
                  status == 'STAT004')) ||
          (_selectedFilter == 2 && status == 'STAT003');
      final query = _searchQuery.trim().toLowerCase();
      final matchesSearch =
          query.isEmpty ||
          [
            report['title'],
            report['categoryName'],
            report['address'],
            report['reportID'],
            report['description'],
          ].any(
            (value) => (value?.toString() ?? '').toLowerCase().contains(query),
          );
      return matchesStatus && matchesSearch;
    }).toList();
    filtered.sort((a, b) {
      final aDate = _parseReportDateTime(a['dateReported']) ?? DateTime(1970);
      final bDate = _parseReportDateTime(b['dateReported']) ?? DateTime(1970);
      return _newestFirst ? bDate.compareTo(aDate) : aDate.compareTo(bDate);
    });
    return filtered;
  }

  void _showSortOptions() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'Sort reports',
                style: TextStyle(fontWeight: FontWeight.bold, color: darkBlue),
              ),
            ),
            RadioListTile<bool>(
              title: const Text('Newest first'),
              value: true,
              groupValue: _newestFirst,
              onChanged: (value) {
                setState(() => _newestFirst = value!);
                Navigator.pop(sheetContext);
              },
            ),
            RadioListTile<bool>(
              title: const Text('Oldest first'),
              value: false,
              groupValue: _newestFirst,
              onChanged: (value) {
                setState(() => _newestFirst = value!);
                Navigator.pop(sheetContext);
              },
            ),
          ],
        ),
      ),
    );
  }

  String? _getImageUrl(Map<String, dynamic> report) {
    final imagePath = report['imagePath']?.toString().trim();

    if (imagePath == null || imagePath.isEmpty) {
      return null;
    }

    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      return imagePath;
    }

    if (imagePath.startsWith('/')) {
      return '$serverBaseUrl$imagePath';
    }

    return '$serverBaseUrl/$imagePath';
  }

  Future<void> _openReportDetails(Map<String, dynamic> report) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            ReportDetailsPage(report: report, userID: widget.userID),
      ),
    );
    if (mounted) await _loadReports();
  }

  @override
  Widget build(BuildContext context) {
    final filteredReports = _filteredReports;
    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: RefreshIndicator(
          color: primaryBlue,
          onRefresh: _loadReports,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTopSection(),
                const SizedBox(height: 14),
                _buildFilterButtons(),
                const SizedBox(height: 12),
                _buildSearchBar(),
                const SizedBox(height: 10),
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.all(38),
                    child: Center(
                      child: CircularProgressIndicator(color: primaryBlue),
                    ),
                  )
                else if (_errorMessage != null)
                  _buildErrorState()
                else
                  // The list fades into the newly chosen filter.
                  AppMotion.fadeSwitcher(
                    contentKey: _selectedFilter,
                    child: filteredReports.isEmpty
                        ? _buildEmptyState()
                        : Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
                            child: Column(
                              children: filteredReports
                                  .map(
                                    (report) => Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12,
                                      ),
                                      child: _buildReportCard(report),
                                    ),
                                  )
                                  .toList(),
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

  Widget _buildTopSection() {
    // Same header as Home, Notifications and Settings: own title, no
    // greeting or barangay.
    final count = _reports.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, CitiPageHeader.topPadding, 20, 0),
      child: CitiPageHeader(
        eyebrow: _isLoading && count == 0
            ? null
            : count == 1
            ? '1 report'
            : '$count reports',
        title: 'My Reports',
        description: 'Track the status of your submitted reports.',
        mascot: _buildMascot(),
      ),
    );
  }

  Widget _buildMascot() {
    // Mascot writing a report on a clipboard (loops).
    return const CitiMascot(pose: MascotPose.report, backdrop: true);
  }

  Widget _buildFilterButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SlidingToggle(
        labels: const ['All Reports', 'Ongoing', 'Completed'],
        selectedIndex: _selectedFilter,
        onChanged: (index) => setState(() => _selectedFilter = index),
        boxShadow: AppShadows.soft,
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.md),
                boxShadow: AppShadows.soft,
              ),
              child: TextField(
                onChanged: (value) => setState(() => _searchQuery = value),
                style: const TextStyle(
                  fontFamily: appFontFamily,
                  color: darkBlue,
                ),
                decoration: InputDecoration(
                  hintText: 'Search report...',
                  hintStyle: const TextStyle(
                    fontFamily: appFontFamily,
                    color: AppColors.textMuted,
                    fontSize: 14,
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: textGrey,
                    size: 25,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: const BorderSide(
                      color: primaryBlue,
                      width: 1.6,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          InkWell(
            onTap: _showSortOptions,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.md),
                boxShadow: AppShadows.soft,
              ),
              child: const Icon(
                Icons.swap_vert_rounded,
                color: primaryBlue,
                size: 26,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Card: photo with the category icon, status, category name, a short
  // location and the date, so reports of the same type are easy to tell
  // apart.
  Widget _buildReportCard(Map<String, dynamic> report) {
    final imageUrl = _getImageUrl(report);
    final category = ReportCategoryStyle.of(report);
    final status = reportStatusOf(report);
    final reportID = report['reportID']?.toString() ?? '';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: () => _openReportDetails(report),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            boxShadow: AppShadows.card,
            color: Colors.white,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 92,
                height: 92,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        child: imageUrl == null
                            ? _categoryPlaceholder(category)
                            : Image.network(
                                imageUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    _categoryPlaceholder(category),
                              ),
                      ),
                    ),
                    // Category icon (color + its own icon).
                    Positioned(
                      left: -6,
                      top: -6,
                      child: Tooltip(
                        message: category.label,
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: category.color,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: Icon(
                            category.icon,
                            size: 17,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _statusChip(status.label, status.color),
                        const Spacer(),
                        Text(
                          reportID,
                          style: const TextStyle(
                            fontFamily: appFontFamily,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      category.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: appHeadingFontFamily,
                        color: darkBlue,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _cardInfo(
                      Icons.location_on_outlined,
                      shortReportAddress(report['address']?.toString()),
                    ),
                    const SizedBox(height: 4),
                    _cardInfo(
                      Icons.schedule_rounded,
                      shortReportDateTime(report['dateReported']),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(
          fontFamily: appHeadingFontFamily,
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _cardInfo(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 15, color: textGrey),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: appFontFamily,
              color: textGrey,
              fontSize: 12.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _categoryPlaceholder(ReportCategoryStyle category) {
    return Container(
      color: category.softColor,
      alignment: Alignment.center,
      child: Icon(category.icon, size: 36, color: category.color),
    );
  }

  Widget _buildEmptyState() {
    String message;

    if (_selectedFilter == 1) {
      message = 'You have no ongoing reports.';
    } else if (_selectedFilter == 2) {
      message = 'You have no completed reports.';
    } else {
      message = 'You have not submitted any reports yet.';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 50),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: const BoxDecoration(
                color: AppColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.assignment_outlined,
                size: 45,
                color: primaryBlue,
              ),
            ),

            const SizedBox(height: 18),

            const Text(
              'No Reports',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: darkBlue,
                fontFamily: appHeadingFontFamily,
              ),
            ),

            const SizedBox(height: 7),

            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: textGrey,
                fontFamily: appFontFamily,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 50),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.cloud_off_outlined, size: 50, color: textGrey),

            const SizedBox(height: 15),

            const Text(
              'Unable to load reports',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: darkBlue,
                fontFamily: appHeadingFontFamily,
              ),
            ),

            const SizedBox(height: 12),

            ElevatedButton(
              onPressed: _loadReports,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryBlue,
                elevation: 0,
              ),
              child: const Text(
                'Try Again',
                style: TextStyle(
                  color: Colors.white,
                  fontFamily: appFontFamily,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// REPORT DETAILS PAGE
// ============================================================

class ReportDetailsPage extends StatelessWidget {
  final Map<String, dynamic> report;
  final String? userID;

  const ReportDetailsPage({super.key, required this.report, this.userID});

  String? _getImageUrl() {
    final imagePath = report['imagePath']?.toString().trim();

    if (imagePath == null || imagePath.isEmpty) {
      return null;
    }

    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      return imagePath;
    }

    if (imagePath.startsWith('/')) {
      return '$serverBaseUrl$imagePath';
    }

    return '$serverBaseUrl/$imagePath';
  }

  String _formatDate(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Unknown date';
    }

    try {
      final date = DateTime.parse(value).toLocal();

      const months = [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ];

      return '${months[date.month - 1]} '
          '${date.day.toString().padLeft(2, '0')}, '
          '${date.year}';
    } catch (e) {
      return value;
    }
  }

  String _formatTime(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Unknown time';
    }

    try {
      final date = DateTime.parse(value).toLocal();

      int hour = date.hour;
      final minute = date.minute;

      final period = hour >= 12 ? 'PM' : 'AM';

      if (hour == 0) {
        hour = 12;
      } else if (hour > 12) {
        hour -= 12;
      }

      return '$hour:${minute.toString().padLeft(2, '0')} $period';
    } catch (e) {
      return value;
    }
  }

  String _formatTimeline() {
    final date = _getAdminTimeline(report);
    if (date == null) {
      return '';
    }

    return '${_formatDate(date.toIso8601String())}  •  '
        '${_formatTime(date.toIso8601String())}';
  }

  String _getEffectiveStatusID() {
    return _getEffectiveReportStatusID(report);
  }

  /// The report's map position, or null when it has none.
  LatLng? _getPoint() {
    final lat = double.tryParse(report['latitude']?.toString() ?? '');
    final lng = double.tryParse(report['longitude']?.toString() ?? '');
    if (lat == null || lng == null) return null;
    if (lat.abs() > 90 || lng.abs() > 180 || (lat == 0 && lng == 0)) {
      return null;
    }
    return LatLng(lat, lng);
  }

  String _getFullTitle() {
    final title = report['title']?.toString().trim() ?? '';
    if (title.isNotEmpty) return title;
    return '${ReportCategoryStyle.of(report).label} Report';
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = _getImageUrl();
    final status = reportStatusOf(report);
    final point = _getPoint();
    final description = report['description']?.toString().trim() ?? '';

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back, color: darkBlue),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Report Details',
          style: TextStyle(
            color: darkBlue,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            fontFamily: appHeadingFontFamily,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ------------------------------------------------
              // TITLE + STATUS (the title already names the category)
              // ------------------------------------------------
              Text(
                _getFullTitle(),
                style: const TextStyle(
                  fontSize: 24,
                  height: 1.2,
                  fontWeight: FontWeight.w800,
                  color: darkBlue,
                  fontFamily: appHeadingFontFamily,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: status.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status.label,
                  style: TextStyle(
                    color: status.color,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    fontFamily: appHeadingFontFamily,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ------------------------------------------------
              // PHOTO (whole photo, never stretched; tap to enlarge)
              // ------------------------------------------------
              _sectionCard(
                padding: const EdgeInsets.all(8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: SizedBox(
                    width: double.infinity,
                    height: 220,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Container(color: AppColors.surfaceMuted),
                        if (imageUrl != null)
                          GestureDetector(
                            onTap: () => _openPhoto(context, imageUrl),
                            child: Image.network(
                              imageUrl,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) =>
                                  _imagePlaceholder(),
                            ),
                          )
                        else
                          _imagePlaceholder(),
                        if (imageUrl != null)
                          Positioned(
                            left: 10,
                            bottom: 10,
                            child: _overlayChip(
                              Icons.photo_camera_outlined,
                              'Photo attached',
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 18),

              // ------------------------------------------------
              // LOCATION + MAP
              // ------------------------------------------------
              _buildDetailRow(
                icon: Icons.location_on_outlined,
                title: 'Location',
                value: report['address']?.toString().trim().isNotEmpty == true
                    ? report['address'].toString()
                    : 'Address unavailable',
              ),
              if (point != null) ...[
                const SizedBox(height: 12),
                _buildMapPreview(context, point),
              ],

              const SizedBox(height: 18),

              // ------------------------------------------------
              // DATE AND TIME (separate rows)
              // ------------------------------------------------
              _buildDetailRow(
                icon: Icons.calendar_today_outlined,
                title: 'Date reported',
                value: _formatDate(report['dateReported']?.toString()),
              ),
              const SizedBox(height: 14),
              _buildDetailRow(
                icon: Icons.access_time_outlined,
                title: 'Time reported',
                value: _formatTime(report['dateReported']?.toString()),
              ),

              // ------------------------------------------------
              // RESOLUTION TIMELINE (only after the admin sets it)
              // ------------------------------------------------
              if (_getAdminTimeline(report) != null) ...[
                const SizedBox(height: 14),
                _buildDetailRow(
                  icon: Icons.event_available_outlined,
                  title: 'Resolution timeline',
                  value: _formatTimeline(),
                ),
              ],

              const SizedBox(height: 22),

              // ------------------------------------------------
              // DESCRIPTION
              // ------------------------------------------------
              const Text(
                'Description',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: darkBlue,
                  fontFamily: appHeadingFontFamily,
                ),
              ),
              const SizedBox(height: 8),
              _sectionCard(
                padding: const EdgeInsets.all(16),
                child: Text(
                  description.isEmpty
                      ? 'No description provided.'
                      : description,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.6,
                    color: description.isEmpty ? AppColors.textMuted : darkBlue,
                    fontFamily: appFontFamily,
                  ),
                ),
              ),

              const SizedBox(height: 22),

              // ------------------------------------------------
              // REPORT ID
              // ------------------------------------------------
              _buildDetailRow(
                icon: Icons.tag,
                title: 'Report ID',
                value: report['reportID']?.toString() ?? '',
              ),

              // ------------------------------------------------
              // FEEDBACK (after resolved) + UPDATES
              // ------------------------------------------------
              ReportEngagementSection(
                userID: userID ?? report['userID']?.toString() ?? '',
                reportID: report['reportID']?.toString() ?? '',
                isResolved: _getEffectiveStatusID() == 'STAT003',
                dateReported: _parseReportDateTime(report['dateReported']),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionCard({
    required Widget child,
    EdgeInsetsGeometry padding = EdgeInsets.zero,
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.divider),
      ),
      child: child,
    );
  }

  Widget _overlayChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.ink.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              fontFamily: appHeadingFontFamily,
            ),
          ),
        ],
      ),
    );
  }

  /// Small map with the report's pin; tap to open a map you can move.
  Widget _buildMapPreview(BuildContext context, LatLng point) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: SizedBox(
        height: 180,
        width: double.infinity,
        child: Stack(
          children: [
            _reportMap(point, interactive: false),
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(onTap: () => _openMap(context, point)),
              ),
            ),
            Positioned(
              right: 10,
              bottom: 10,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: AppShadows.soft,
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.map_outlined, size: 15, color: Colors.white),
                      SizedBox(width: 5),
                      Text(
                        'View map',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          fontFamily: appHeadingFontFamily,
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

  Widget _reportMap(LatLng point, {required bool interactive}) {
    return FlutterMap(
      options: MapOptions(
        initialCenter: point,
        initialZoom: interactive ? 17 : 16,
        interactionOptions: InteractionOptions(
          flags: interactive ? InteractiveFlag.all : InteractiveFlag.none,
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
              width: 46,
              height: 54,
              alignment: Alignment.topCenter,
              child: const Icon(
                Icons.location_on,
                size: 46,
                color: AppColors.danger,
                shadows: [Shadow(color: Colors.black26, blurRadius: 6)],
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _openMap(BuildContext context, LatLng point) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Report location')),
          body: _reportMap(point, interactive: true),
        ),
      ),
    );
  }

  void _openPhoto(BuildContext context, String url) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
          body: InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            child: Center(child: Image.network(url, fit: BoxFit.contain)),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            color: AppColors.primarySoft,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: primaryBlue, size: 20),
        ),

        const SizedBox(width: 13),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  color: textGrey,
                  fontFamily: appFontFamily,
                ),
              ),

              const SizedBox(height: 3),

              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                  color: darkBlue,
                  fontFamily: appFontFamily,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _imagePlaceholder() {
    final category = ReportCategoryStyle.of(report);
    return Container(
      color: category.softColor,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(category.icon, size: 46, color: category.color),
          const SizedBox(height: 6),
          const Text(
            'No photo attached',
            style: TextStyle(
              fontFamily: appFontFamily,
              fontSize: 12.5,
              color: textGrey,
            ),
          ),
        ],
      ),
    );
  }
}

// Relays Android application lifecycle changes to the My Reports screen.
class _MyReportsLifecycleObserver extends WidgetsBindingObserver {
  _MyReportsLifecycleObserver(this.onChanged);
  final void Function(AppLifecycleState) onChanged;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    onChanged(state);
  }
}
