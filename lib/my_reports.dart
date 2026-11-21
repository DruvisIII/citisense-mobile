import 'dart:async';
import 'package:citisense/api_config.dart';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:citisense/app_theme.dart';
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
      '$serverBaseUrl/api/get_my_reports.php';
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

  String _getCategoryName(Map<String, dynamic> report) {
    final category = report['categoryName']?.toString() ?? '';

    if (category.isEmpty) {
      return 'OTHER';
    }

    return category.toUpperCase();
  }

  String _getTitle(Map<String, dynamic> report) {
    final title = report['title']?.toString() ?? '';

    if (title.isEmpty) {
      return 'Report';
    }

    return title;
  }

  String _getAddress(Map<String, dynamic> report) {
    final address = report['address']?.toString() ?? '';

    if (address.isEmpty) {
      return 'Address unavailable';
    }

    return address;
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

  String _getStatusText(Map<String, dynamic> report) {
    final statusID = _getEffectiveStatusID(report);

    switch (statusID) {
      case 'STAT001':
        return 'PENDING';

      case 'STAT002':
        return 'IN PROGRESS';

      case 'STAT003':
        return 'COMPLETE';

      case 'STAT004':
        return 'OVERDUE';

      default:
        return report['displayStatus']?.toString().toUpperCase() ?? 'UNKNOWN';
    }
  }

  Color _getStatusColor(Map<String, dynamic> report) {
    final statusID = _getEffectiveStatusID(report);

    switch (statusID) {
      case 'STAT001':
        return AppColors.warning;

      case 'STAT002':
        return primaryBlue;

      case 'STAT003':
        return AppColors.success;

      case 'STAT004':
        return AppColors.danger;

      default:
        return textGrey;
    }
  }

  Future<void> _openReportDetails(Map<String, dynamic> report) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReportDetailsPage(report: report),
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
                const SizedBox(height: 18),
                _buildReportsHeading(),
                const SizedBox(height: 18),
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
                else if (filteredReports.isEmpty)
                  _buildEmptyState()
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
                    child: Column(
                      children: filteredReports
                          .map(
                            (report) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _buildReportCard(report),
                            ),
                          )
                          .toList(),
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
    // Keep the header sizing and positioning identical to HomePage.
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning,'
        : hour < 17
        ? 'Good afternoon,'
        : 'Good evening,';

    return LayoutBuilder(
      builder: (context, constraints) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on, color: primaryBlue, size: 32),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.barangayName.isNotEmpty
                            ? 'Barangay ${widget.barangayName}'
                            : 'Your Barangay',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                          fontFamily: appFontFamily,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Cebu City',
                        style: TextStyle(
                          fontSize: 16,
                          color: textGrey,
                          fontFamily: appFontFamily,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            SizedBox(
              height: 190,
              width: double.infinity,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    top: 12,
                    right: 0,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          greeting,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: textGrey,
                            fontFamily: appFontFamily,
                          ),
                        ),
                        const SizedBox(height: 1),
                        SizedBox(
                          width: constraints.maxWidth * .53,
                          child: Text(
                            '${widget.firstName.isNotEmpty ? widget.firstName : 'User'}!',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 41,
                              height: 1.12,
                              fontWeight: FontWeight.w900,
                              color: AppColors.ink,
                              fontFamily: appFontFamily,
                            ),
                          ),
                        ),
                        const SizedBox(height: 13),
                        SizedBox(
                          width: constraints.maxWidth * .46,
                          child: const Text(
                            'Let’s work together for a safer and cleaner community.',
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.55,
                              color: textGrey,
                              fontFamily: appFontFamily,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    right: -10,
                    bottom: -4,
                    child: SizedBox(
                      width: constraints.maxWidth * .40,
                      height: 188,
                      child: _buildMascot(),
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

  Widget _buildMascot() {
    // Mascot writing a report on a clipboard (loops).
    return const CitiMascot(pose: MascotPose.report);
  }

  Widget _buildReportsHeading() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Container(
            width: 57,
            height: 57,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.primaryBorder),
            ),
            child: const Icon(
              Icons.assignment_outlined,
              size: 31,
              color: primaryBlue,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'My Reports',
                  style: TextStyle(
                    fontFamily: appFontFamily,
                    color: darkBlue,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Track the status of your submitted reports.',
                  style: TextStyle(
                    fontFamily: appFontFamily,
                    color: textGrey,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterButtons() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadows.soft,
      ),
      child: Row(
        children: [
          _buildFilterButton(label: 'All Reports', index: 0),
          _buildFilterButton(label: 'Ongoing', index: 1),
          _buildFilterButton(label: 'Completed', index: 2),
        ],
      ),
    );
  }

  Widget _buildFilterButton({required String label, required int index}) {
    final selected = _selectedFilter == index;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _selectedFilter = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 2),
          decoration: BoxDecoration(
            color: selected ? primaryBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            label,
            maxLines: 1,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: appFontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : textGrey,
            ),
          ),
        ),
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
                style: const TextStyle(fontFamily: appFontFamily, color: darkBlue),
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
                    borderSide: const BorderSide(color: primaryBlue, width: 1.6),
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

  Widget _buildReportCard(Map<String, dynamic> report) {
    final imageUrl = _getImageUrl(report);
    final statusColor = _getStatusColor(report);
    final category = _getCategoryName(report);
    final categoryIsPothole = category.toLowerCase().contains('pothole');
    final categoryColor = categoryIsPothole
        ? AppColors.accent
        : primaryBlue;
    return InkWell(
      onTap: () => _openReportDetails(report),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: AppShadows.card,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: SizedBox(
                width: 104,
                height: 144,
                child: imageUrl == null
                    ? _buildImagePlaceholder()
                    : Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _buildImagePlaceholder(),
                      ),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: categoryColor.withValues(alpha: .09),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            category,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: appFontFamily,
                              color: categoryColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: .11),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _getStatusText(report),
                          maxLines: 1,
                          style: TextStyle(
                            fontFamily: appFontFamily,
                            color: statusColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _getTitle(report),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: appFontFamily,
                      color: darkBlue,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 17,
                        color: textGrey,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          _getAddress(report),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: appFontFamily,
                            color: textGrey,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_month_outlined,
                        size: 16,
                        color: textGrey,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          '${_formatDate(report['dateReported']?.toString())}  •  ${_formatTime(report['dateReported']?.toString())}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: appFontFamily,
                            color: textGrey,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Row(
                    children: [
                      Text(
                        'View Details',
                        style: TextStyle(
                          fontFamily: appFontFamily,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: primaryBlue,
                        ),
                      ),
                      SizedBox(width: 7),
                      Icon(Icons.arrow_forward, color: primaryBlue, size: 18),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePlaceholder() {
    return Container(
      color: AppColors.primarySoft,
      child: const Center(
        child: Icon(Icons.image_outlined, size: 38, color: primaryBlue),
      ),
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
                fontFamily: appFontFamily,
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
                fontFamily: appFontFamily,
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
                style: TextStyle(color: Colors.white, fontFamily: appFontFamily),
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

  const ReportDetailsPage({super.key, required this.report});

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

  String _getStatusText() {
    switch (_getEffectiveStatusID()) {
      case 'STAT001':
        return 'PENDING';

      case 'STAT002':
        return 'IN PROGRESS';

      case 'STAT003':
        return 'COMPLETE';

      case 'STAT004':
        return 'OVERDUE';

      default:
        return report['displayStatus']?.toString().toUpperCase() ?? 'UNKNOWN';
    }
  }

  Color _getStatusColor() {
    switch (_getEffectiveStatusID()) {
      case 'STAT001':
        return AppColors.warning;

      case 'STAT002':
        return primaryBlue;

      case 'STAT003':
        return AppColors.success;

      case 'STAT004':
        return AppColors.danger;

      default:
        return textGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = _getImageUrl();
    final statusColor = _getStatusColor();

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: darkBlue),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: const Text(
          'Report Details',
          style: TextStyle(
            color: darkBlue,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            fontFamily: appFontFamily,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ------------------------------------------------
              // IMAGE
              // ------------------------------------------------
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: SizedBox(
                  width: double.infinity,
                  height: 230,
                  child: imageUrl != null
                      ? Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return _imagePlaceholder();
                          },
                        )
                      : _imagePlaceholder(),
                ),
              ),

              const SizedBox(height: 20),

              // ------------------------------------------------
              // STATUS
              // ------------------------------------------------
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _getStatusText(),
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    fontFamily: appFontFamily,
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // ------------------------------------------------
              // CATEGORY
              // ------------------------------------------------
              Text(
                report['categoryName']?.toString().toUpperCase() ?? 'OTHER',
                style: const TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w600,
                  color: textGrey,
                  fontFamily: appFontFamily,
                ),
              ),

              const SizedBox(height: 6),

              // ------------------------------------------------
              // TITLE
              // ------------------------------------------------
              Text(
                report['title']?.toString() ?? 'Report',
                style: const TextStyle(
                  fontSize: 23,
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                  color: darkBlue,
                  fontFamily: appFontFamily,
                ),
              ),

              const SizedBox(height: 20),

              // ------------------------------------------------
              // ADDRESS
              // ------------------------------------------------
              _buildDetailRow(
                icon: Icons.location_on_outlined,
                title: 'Location',
                value: report['address']?.toString() ?? 'Address unavailable',
              ),

              const SizedBox(height: 15),

              // ------------------------------------------------
              // DATE
              // ------------------------------------------------
              _buildDetailRow(
                icon: Icons.calendar_today_outlined,
                title: 'Date Reported',
                value: _formatDate(report['dateReported']?.toString()),
              ),

              const SizedBox(height: 15),

              // ------------------------------------------------
              // TIME
              // ------------------------------------------------
              _buildDetailRow(
                icon: Icons.access_time_outlined,
                title: 'Time Reported',
                value: _formatTime(report['dateReported']?.toString()),
              ),

              const SizedBox(height: 15),

              // ------------------------------------------------
              // RESOLUTION TIMELINE (only after the admin sets it)
              // ------------------------------------------------
              if (_getAdminTimeline(report) != null) ...[
                _buildDetailRow(
                  icon: Icons.event_available_outlined,
                  title: 'Resolution Timeline',
                  value: _formatTimeline(),
                ),
                const SizedBox(height: 25),
              ] else
                const SizedBox(height: 10),

              // ------------------------------------------------
              // DESCRIPTION
              // ------------------------------------------------
              const Text(
                'Description',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: darkBlue,
                  fontFamily: appFontFamily,
                ),
              ),

              const SizedBox(height: 10),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(17),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Text(
                  (report['description']?.toString().trim().isEmpty ?? true)
                      ? 'No description provided.'
                      : report['description'].toString(),
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.6,
                    color: textGrey,
                    fontFamily: appFontFamily,
                  ),
                ),
              ),

              const SizedBox(height: 25),

              // ------------------------------------------------
              // REPORT ID
              // ------------------------------------------------
              _buildDetailRow(
                icon: Icons.tag,
                title: 'Report ID',
                value: report['reportID']?.toString() ?? '',
              ),
            ],
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
    return Container(
      color: AppColors.primarySoft,
      child: const Center(
        child: Icon(Icons.image_outlined, size: 55, color: primaryBlue),
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
