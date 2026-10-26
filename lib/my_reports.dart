import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const Color primaryBlue = Color(0xFF0757F2);
const Color darkBlue = Color(0xFF101D59);
const Color textGrey = Color(0xFF596887);
const Color backgroundColor = Color(0xFFF7F9FD);

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
      // 'http://192.168.1.48/citisense/api/get_my_reports.php';
      'http://10.127.214.252/citisense/api/get_my_reports.php';

  int _selectedFilter = 1;
  String _searchQuery = '';
  bool _newestFirst = true;

  bool _isLoading = true;
  String? _errorMessage;

  List<Map<String, dynamic>> _reports = [];

  @override
  void initState() {
    super.initState();

    _loadReports();
  }

  Future<void> _loadReports() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final uri = Uri.parse(
        '$_getReportsUrl?userID=${Uri.encodeComponent(widget.userID)}',
      );

      final response = await http.get(
        uri,
        headers: {'Accept': 'application/json'},
      );

      debugPrint('My Reports status: ${response.statusCode}');
      debugPrint('My Reports response: ${response.body}');

      if (response.statusCode != 200) {
        throw Exception('Server returned status code ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);

      if (decoded['success'] != true) {
        throw Exception(decoded['message'] ?? 'Unable to load reports.');
      }

      final List<dynamic> data = decoded['data'] ?? [];

      final loadedReports = data
          .map<Map<String, dynamic>>((item) => Map<String, dynamic>.from(item))
          .toList();

      if (!mounted) return;

      setState(() {
        _reports = loadedReports;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading reports: $e');

      if (!mounted) return;

      setState(() {
        _reports = [];
        _isLoading = false;
        _errorMessage = 'Unable to load your reports.';
      });
    }
  }

  List<Map<String, dynamic>> get _filteredReports {
    final filtered = _reports.where((report) {
      final status = report['statusID']?.toString() ?? '';
      final matchesStatus =
          _selectedFilter == 0 ||
          (_selectedFilter == 1 && status == 'STAT001') ||
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
      final aDate =
          DateTime.tryParse(a['dateReported']?.toString() ?? '') ??
          DateTime(1970);
      final bDate =
          DateTime.tryParse(b['dateReported']?.toString() ?? '') ??
          DateTime(1970);
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
      return 'http://192.168.1.48/citisense$imagePath';
    }

    return 'http://192.168.1.48/citisense/$imagePath';
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
    final statusID = report['statusID']?.toString() ?? '';

    switch (statusID) {
      case 'STAT001':
        return 'PENDING';

      case 'STAT002':
        return 'IN PROGRESS';

      case 'STAT003':
        return 'COMPLETE';

      default:
        return report['displayStatus']?.toString().toUpperCase() ?? 'UNKNOWN';
    }
  }

  Color _getStatusColor(Map<String, dynamic> report) {
    final statusID = report['statusID']?.toString() ?? '';

    switch (statusID) {
      case 'STAT001':
        return const Color(0xFFE59B24);

      case 'STAT002':
        return primaryBlue;

      case 'STAT003':
        return const Color(0xFF2CA45A);

      default:
        return textGrey;
    }
  }

  void _openReportDetails(Map<String, dynamic> report) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReportDetailsPage(report: report),
      ),
    );
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
                          color: Color(0xFF09204F),
                          fontFamily: 'Biennale',
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Cebu City',
                        style: TextStyle(
                          fontSize: 16,
                          color: textGrey,
                          fontFamily: 'Biennale',
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
                            fontFamily: 'Biennale',
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
                              color: Color(0xFF09204F),
                              fontFamily: 'Biennale',
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
                              fontFamily: 'Biennale',
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
    // Replace this container with Image.asset('assets/your_mascot.png') later.
    return Container(
      width: 145,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFE8F1FF),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFC4D8FF)),
      ),
      child: const Text(
        'Mascot\nplaceholder',
        textAlign: TextAlign.center,
        style: TextStyle(fontFamily: 'Biennale', color: textGrey, fontSize: 13),
      ),
    );
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
              color: const Color(0xFFEAF1FF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFD0DEFF)),
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
                    fontFamily: 'Biennale',
                    color: primaryBlue,
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Track the status of your submitted reports.',
                  style: TextStyle(
                    fontFamily: 'Biennale',
                    color: textGrey,
                    fontSize: 12,
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
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.045),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
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
        borderRadius: BorderRadius.circular(18),
        onTap: () => setState(() => _selectedFilter = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 2),
          decoration: BoxDecoration(
            color: selected ? primaryBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(17),
          ),
          child: Text(
            label,
            maxLines: 1,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Biennale',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : primaryBlue,
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
                borderRadius: BorderRadius.circular(17),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(.035),
                    blurRadius: 9,
                  ),
                ],
              ),
              child: TextField(
                onChanged: (value) => setState(() => _searchQuery = value),
                style: const TextStyle(fontFamily: 'Biennale', color: darkBlue),
                decoration: InputDecoration(
                  hintText: 'Search report...',
                  hintStyle: const TextStyle(
                    fontFamily: 'Biennale',
                    color: textGrey,
                    fontSize: 14,
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: textGrey,
                    size: 25,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(17),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          InkWell(
            onTap: _showSortOptions,
            borderRadius: BorderRadius.circular(17),
            child: Container(
              width: 55,
              height: 55,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(17),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(.04),
                    blurRadius: 9,
                  ),
                ],
              ),
              child: const Icon(
                Icons.filter_alt_outlined,
                color: textGrey,
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
        ? const Color(0xFF7825B3)
        : primaryBlue;
    return InkWell(
      onTap: () => _openReportDetails(report),
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.05),
              blurRadius: 11,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 105,
                height: 148,
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
                            color: categoryColor.withOpacity(.09),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            category,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Biennale',
                              color: categoryColor,
                              fontSize: 9,
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
                          color: statusColor.withOpacity(.11),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _getStatusText(report),
                          maxLines: 1,
                          style: TextStyle(
                            fontFamily: 'Biennale',
                            color: statusColor,
                            fontSize: 9,
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
                      fontFamily: 'Biennale',
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
                            fontFamily: 'Biennale',
                            color: textGrey,
                            fontSize: 11,
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
                            fontFamily: 'Biennale',
                            color: textGrey,
                            fontSize: 10,
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
                          fontFamily: 'Biennale',
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
      color: const Color(0xFFE8F0FF),
      child: const Center(
        child: Icon(Icons.image_outlined, size: 38, color: primaryBlue),
      ),
    );
  }

  Widget _buildEmptyState() {
    String message;

    if (_selectedFilter == 1) {
      message = 'You have no pending reports.';
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
                color: Color(0xFFE8F0FF),
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
                fontFamily: 'Biennale',
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
                fontFamily: 'Biennale',
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
                fontFamily: 'Biennale',
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
                style: TextStyle(color: Colors.white, fontFamily: 'Biennale'),
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
      return 'http://192.168.1.48/citisense$imagePath';
    }

    return 'http://192.168.1.48/citisense/$imagePath';
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

  String _getStatusText() {
    switch (report['statusID']?.toString()) {
      case 'STAT001':
        return 'PENDING';

      case 'STAT002':
        return 'IN PROGRESS';

      case 'STAT003':
        return 'COMPLETE';

      default:
        return report['displayStatus']?.toString().toUpperCase() ?? 'UNKNOWN';
    }
  }

  Color _getStatusColor() {
    switch (report['statusID']?.toString()) {
      case 'STAT001':
        return const Color(0xFFE59B24);

      case 'STAT002':
        return primaryBlue;

      case 'STAT003':
        return const Color(0xFF2CA45A);

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
            fontFamily: 'Biennale',
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
                borderRadius: BorderRadius.circular(22),
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
                  color: statusColor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  _getStatusText(),
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Biennale',
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
                  fontSize: 10,
                  letterSpacing: 0.5,
                  fontWeight: FontWeight.w600,
                  color: textGrey,
                  fontFamily: 'Biennale',
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
                  fontFamily: 'Biennale',
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

              const SizedBox(height: 25),

              // ------------------------------------------------
              // DESCRIPTION
              // ------------------------------------------------
              const Text(
                'Description',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: darkBlue,
                  fontFamily: 'Biennale',
                ),
              ),

              const SizedBox(height: 10),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(17),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  (report['description']?.toString().trim().isEmpty ?? true)
                      ? 'No description provided.'
                      : report['description'].toString(),
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.6,
                    color: textGrey,
                    fontFamily: 'Biennale',
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
            color: Color(0xFFE8F0FF),
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
                  fontSize: 11,
                  color: textGrey,
                  fontFamily: 'Biennale',
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
                  fontFamily: 'Biennale',
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
      color: const Color(0xFFE8F0FF),
      child: const Center(
        child: Icon(Icons.image_outlined, size: 55, color: primaryBlue),
      ),
    );
  }
}
