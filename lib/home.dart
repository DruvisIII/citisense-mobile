import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:citisense/report_issue_overlay.dart';
import 'package:citisense/settings_page.dart';
import 'package:citisense/my_reports.dart';
import 'package:citisense/notification_page.dart';

const Color primaryBlue = Color(0xFF2875ED);
const Color darkBlue = Color(0xFF09204F);
const Color textGrey = Color(0xFF596887);
const Color backgroundColor = Color(0xFFFBFCFF);

class HomePage extends StatefulWidget {
  // ============================================================
  // LOGGED-IN USER INFORMATION
  // ============================================================

  final String userID;
  final String firstName;
  final String lastName;
  final String email;
  final String contactNo;
  final String? profilePic;
  final String barangayID;

  const HomePage({
    super.key,
    required this.userID,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.contactNo,
    this.profilePic,
    required this.barangayID,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // ============================================================
  // VARIABLES
  // ============================================================

  int _selectedIndex = 0;

  // Latest user information
  String _userID = '';
  String _firstName = '';
  String _lastName = '';
  String _email = '';
  String _contactNo = '';
  String? _profilePic;
  String _barangayID = '';
  String _barangayName = '';

  bool _isLoading = true;
  String? _errorMessage;

  // ============================================================
  // ANNOUNCEMENT VARIABLES
  // ============================================================

  List<Map<String, dynamic>> _announcements = [];

  bool _isLoadingAnnouncements = true;

  // ============================================================
  // API URLS
  // ============================================================

  static const String _getProfileUrl =
      // 'http://192.168.1.48/citisense/api/get_profile.php';
      'http://10.127.214.252/citisense/api/get_profile.php';

  static const String _getAnnouncementsUrl =
      // 'http://192.168.1.48/citisense/api/get_announcements.php';
      'http://10.127.214.252/citisense/api/get_announcements.php';

  // ============================================================
  // INIT STATE
  // ============================================================

  @override
  void initState() {
    super.initState();

    // Start with the information received from LoginPage.
    // get_profile.php will then replace these with the latest
    // information from the database.

    _userID = widget.userID;

    _firstName = widget.firstName;
    _lastName = widget.lastName;
    _email = widget.email;
    _contactNo = widget.contactNo;
    _profilePic = widget.profilePic;
    _barangayID = widget.barangayID;

    _loadUserData();
  }

  // ============================================================
  // LOAD USER DATA
  // ============================================================

  Future<void> _loadUserData() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // ----------------------------------------------------------
      // GET LATEST USER INFORMATION FROM DATABASE
      // ----------------------------------------------------------

      final uri = Uri.parse(
        '$_getProfileUrl?userID='
        '${Uri.encodeComponent(widget.userID)}',
      );

      final response = await http
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 15));

      debugPrint('get_profile.php status: ${response.statusCode}');

      debugPrint('get_profile.php response: ${response.body}');

      if (response.statusCode != 200) {
        throw Exception('Server returned status code ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);

      if (decoded['success'] != true) {
        throw Exception(decoded['message'] ?? 'Unable to load your profile.');
      }

      final data = decoded['data'];

      if (data == null) {
        throw Exception('No profile information was returned.');
      }

      final String latestFirstName = data['firstName']?.toString().trim() ?? '';

      final String latestLastName = data['lastName']?.toString().trim() ?? '';

      final String latestEmail = data['email']?.toString().trim() ?? '';

      final String latestContactNo = data['contactNo']?.toString().trim() ?? '';

      final String latestBarangayID =
          data['barangayID']?.toString().trim() ?? '';

      final String latestBarangayName =
          data['barangayName']?.toString().trim() ?? '';

      final String? latestProfilePic = data['profilePic']?.toString();

      if (!mounted) return;

      setState(() {
        _userID = widget.userID;

        _firstName = latestFirstName.isNotEmpty ? latestFirstName : 'User';

        _lastName = latestLastName;

        _email = latestEmail;

        _contactNo = latestContactNo;

        _barangayID = latestBarangayID;

        _barangayName = latestBarangayName;

        _profilePic =
            latestProfilePic != null && latestProfilePic.trim().isNotEmpty
            ? latestProfilePic
            : null;

        _isLoading = false;
        _errorMessage = null;
      });

      // ----------------------------------------------------------
      // LOAD ANNOUNCEMENTS USING THE UPDATED BARANGAY ID
      // ----------------------------------------------------------

      await _loadAnnouncements();
    } catch (e) {
      debugPrint('Error loading user profile: $e');

      if (!mounted) return;

      // If the API cannot be reached, keep the original
      // information received from LoginPage.

      setState(() {
        _userID = widget.userID;

        _firstName = widget.firstName.trim();

        if (_firstName.isEmpty) {
          _firstName = 'User';
        }

        _lastName = widget.lastName;

        _email = widget.email;

        _contactNo = widget.contactNo;

        _profilePic = widget.profilePic;

        _barangayID = widget.barangayID;

        _isLoading = false;

        _errorMessage = 'Unable to load your information.';
      });
    }
  }

  // ============================================================
  // LOAD ANNOUNCEMENTS
  // ============================================================

  Future<void> _loadAnnouncements() async {
    if (!mounted) return;

    setState(() {
      _isLoadingAnnouncements = true;
    });

    try {
      // ----------------------------------------------------------
      // USE THE CURRENT BARANGAY ID
      // ----------------------------------------------------------

      if (_barangayID.trim().isEmpty) {
        if (!mounted) return;

        setState(() {
          _announcements = [];
          _isLoadingAnnouncements = false;
        });

        return;
      }

      // ----------------------------------------------------------
      // GET ANNOUNCEMENTS FOR CURRENT USER'S BARANGAY
      // ----------------------------------------------------------

      final uri = Uri.parse(
        '$_getAnnouncementsUrl?barangayID='
        '${Uri.encodeComponent(_barangayID)}',
      );

      final response = await http.get(
        uri,
        headers: {'Accept': 'application/json'},
      );

      debugPrint('Announcements status: ${response.statusCode}');

      debugPrint('Announcements response: ${response.body}');

      if (response.statusCode != 200) {
        throw Exception('Server returned status code ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);

      if (decoded['success'] != true) {
        throw Exception(decoded['message'] ?? 'Unable to load announcements.');
      }

      final List<dynamic> data = decoded['data'] ?? [];

      final List<Map<String, dynamic>> loadedAnnouncements = data
          .map<Map<String, dynamic>>((item) => Map<String, dynamic>.from(item))
          .toList();

      if (!mounted) return;

      setState(() {
        _announcements = loadedAnnouncements;

        _isLoadingAnnouncements = false;
      });
    } catch (e) {
      debugPrint('Error loading announcements: $e');

      if (!mounted) return;

      setState(() {
        _announcements = [];
        _isLoadingAnnouncements = false;
      });
    }
  }

  // ============================================================
  // REFRESH HOME PAGE
  // ============================================================

  Future<void> _refreshHomePage() async {
    await _loadUserData();
  }

  // ============================================================
  // REPORT ISSUE
  // ============================================================

  void _openReportIssue() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          ReportIssueOverlay(userID: widget.userID, barangayID: _barangayID),
    );
  }

  // ============================================================
  // BOTTOM NAVIGATION
  // ============================================================

  void _onItemTapped(int index) {
    // ----------------------------------------------------------
    // IF USER RETURNS TO HOME, GET THE LATEST PROFILE DATA
    // ----------------------------------------------------------

    if (index == 0 && _selectedIndex != 0) {
      setState(() {
        _selectedIndex = index;
      });

      _loadUserData();
      return;
    }

    setState(() {
      _selectedIndex = index;
    });
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildHomeContent(),

      // ========================================================
      // MY REPORTS
      // ========================================================
      MyReportsPage(
        userID: _userID,
        firstName: _firstName,
        barangayID: _barangayID,
        barangayName: _barangayName,
      ),

      NotificationPage(userID: _userID, barangayID: _barangayID),

      // ========================================================
      // SETTINGS PAGE
      // ========================================================
      SettingsPage(
        userID: widget.userID,
        firstName: _firstName,
        lastName: _lastName,
        email: _email,
        contactNo: _contactNo,
        profilePic: _profilePic,
        barangayID: _barangayID,
      ),
    ];

    return Scaffold(
      backgroundColor: backgroundColor,

      // ========================================================
      // BODY
      // ========================================================
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: primaryBlue))
            : _errorMessage != null
            ? _buildErrorPage()
            : IndexedStack(index: _selectedIndex, children: pages),
      ),

      // ========================================================
      // BOTTOM NAVIGATION
      // ========================================================
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: const Color(0xFF1761E8),
        unselectedItemColor: textGrey,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        selectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontFamily: 'Biennale',
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontFamily: 'Biennale',
        ),
        elevation: 8,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.assignment_outlined),
            activeIcon: Icon(Icons.assignment),
            label: 'My Reports',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications_none),
            activeIcon: Icon(Icons.notifications),
            label: 'Notifications',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  // ============================================================
  // HOME PAGE CONTENT
  // ============================================================

  Widget _buildHomeContent() {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning,'
        : hour < 17
        ? 'Good afternoon,'
        : 'Good evening,';

    return RefreshIndicator(
      onRefresh: _refreshHomePage,
      color: primaryBlue,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 30),
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
                          _barangayName.isNotEmpty
                              ? 'Barangay $_barangayName'
                              : 'Your Barangay',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: darkBlue,
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
                              '${_firstName.isNotEmpty ? _firstName : 'User'}!',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 41,
                                height: 1.12,
                                fontWeight: FontWeight.w900,
                                color: darkBlue,
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
                        child: _buildMascotPlaceholder(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _openReportIssue,
                  borderRadius: BorderRadius.circular(18),
                  child: Ink(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2F7DF2), Color(0xFF246DE7)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF154DAD,
                          ).withValues(alpha: 0.17),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 23,
                        horizontal: 18,
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 86,
                            height: 86,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: .85),
                                width: 1.4,
                                style: BorderStyle.solid,
                              ),
                            ),
                            child: const Icon(
                              Icons.add,
                              size: 52,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Report an Issue',
                            style: TextStyle(
                              fontFamily: 'Biennale',
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 7),
                          const Text(
                            'Tap to report a problem\nin your community',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Biennale',
                              fontSize: 15,
                              height: 1.5,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  SizedBox(
                    width: 86,
                    height: 55,
                    child: Stack(
                      children: [
                        Positioned(
                          left: 0,
                          bottom: 0,
                          child: SizedBox(
                            width: 58,
                            height: 54,
                            child: _buildMascotPlaceholder(),
                          ),
                        ),
                        const Positioned(
                          right: 0,
                          top: 16,
                          child: Icon(
                            Icons.campaign,
                            color: Color(0xFFF2A318),
                            size: 36,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Announcements',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: darkBlue,
                            fontFamily: 'Biennale',
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _barangayName.isNotEmpty
                              ? 'From Barangay $_barangayName'
                              : 'From your barangay',
                          style: const TextStyle(
                            fontSize: 13,
                            color: textGrey,
                            fontFamily: 'Biennale',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildAnnouncements(),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // MASCOT PLACEHOLDER (replace with Image.asset later)
  // ============================================================

  Widget _buildMascotPlaceholder() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFB8D2FA), width: 1.5),
      ),
      alignment: Alignment.center,
      child: const Text(
        'Mascot',
        style: TextStyle(
          color: Color(0xFF1761E8),
          fontSize: 13,
          fontWeight: FontWeight.w600,
          fontFamily: 'Biennale',
        ),
      ),
    );
  }

  // ============================================================
  // ANNOUNCEMENTS
  // ============================================================

  Widget _buildAnnouncements() {
    // ----------------------------------------------------------
    // NO BARANGAY
    // ----------------------------------------------------------

    if (_barangayName.isEmpty) {
      return _buildEmptyCard(
        icon: Icons.location_off_outlined,
        message: 'Select a barangay to view announcements.',
      );
    }

    // ----------------------------------------------------------
    // LOADING
    // ----------------------------------------------------------

    if (_isLoadingAnnouncements) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(10),
            child: CircularProgressIndicator(color: primaryBlue),
          ),
        ),
      );
    }

    // ----------------------------------------------------------
    // NO ANNOUNCEMENTS
    // ----------------------------------------------------------

    if (_announcements.isEmpty) {
      return _buildEmptyCard(
        icon: Icons.campaign_outlined,
        message: 'No announcements available for your barangay.',
      );
    }

    // ----------------------------------------------------------
    // ANNOUNCEMENT LIST
    // ----------------------------------------------------------

    return Column(
      children: List.generate(_announcements.length, (index) {
        final announcement = _announcements[index];

        return Padding(
          padding: EdgeInsets.only(
            bottom: index == _announcements.length - 1 ? 0 : 15,
          ),
          child: _buildAnnouncementCard(announcement),
        );
      }),
    );
  }

  // ============================================================
  // ANNOUNCEMENT CARD
  // ============================================================

  Widget _buildAnnouncementCard(Map<String, dynamic> announcement) {
    final title = announcement['title']?.toString().trim() ?? '';
    final content = announcement['content']?.toString().trim() ?? '';
    final date = _parseAnnouncementDate(announcement['datePosted']);
    // Use an announcement image when the API supplies one; otherwise show an icon.
    final imageUrl =
        (announcement['imageUrl'] ??
                announcement['image'] ??
                announcement['image_url'] ??
                '')
            .toString()
            .trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF17366B).withValues(alpha: .07),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _buildAnnouncementImage(imageUrl),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.isNotEmpty ? title.toUpperCase() : 'ANNOUNCEMENT',
                  style: const TextStyle(
                    fontFamily: 'Biennale',
                    fontSize: 15,
                    height: 1.22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1870E9),
                  ),
                ),
                if (date != null) ...[
                  const SizedBox(height: 9),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 7,
                    runSpacing: 5,
                    children: [
                      const Icon(
                        Icons.calendar_month_outlined,
                        size: 16,
                        color: textGrey,
                      ),
                      Text(
                        _formatDate(date),
                        style: const TextStyle(
                          fontSize: 12,
                          color: textGrey,
                          fontFamily: 'Biennale',
                        ),
                      ),
                      const Text('·', style: TextStyle(color: textGrey)),
                      const Icon(
                        Icons.access_time_outlined,
                        size: 16,
                        color: textGrey,
                      ),
                      Text(
                        _formatTime(date),
                        style: const TextStyle(
                          fontSize: 12,
                          color: textGrey,
                          fontFamily: 'Biennale',
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  content.isNotEmpty
                      ? content
                      : 'No announcement details available.',
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.5,
                    color: darkBlue,
                    fontFamily: 'Biennale',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // PARSE ANNOUNCEMENT DATE
  // ============================================================

  DateTime? _parseAnnouncementDate(dynamic value) {
    if (value is DateTime) {
      return value;
    }

    if (value is String) {
      return DateTime.tryParse(value);
    }

    return null;
  }

  // ============================================================
  // FORMAT ANNOUNCEMENT DATE
  // ============================================================

  String _formatDate(dynamic value) {
    DateTime? date;

    if (value is DateTime) {
      date = value;
    } else if (value is String) {
      date = DateTime.tryParse(value);
    }

    if (date == null) return '';

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

    final String day = date.day.toString().padLeft(2, '0');

    return '${months[date.month - 1]} '
        '$day, ${date.year}';
  }

  // ============================================================
  // FORMAT ANNOUNCEMENT TIME
  // ============================================================

  String _formatTime(dynamic value) {
    DateTime? date;

    if (value is DateTime) {
      date = value;
    } else if (value is String) {
      date = DateTime.tryParse(value);
    }

    if (date == null) return '';

    int hour = date.hour;

    final String minute = date.minute.toString().padLeft(2, '0');

    final String period = hour >= 12 ? 'PM' : 'AM';

    if (hour == 0) {
      hour = 12;
    } else if (hour > 12) {
      hour -= 12;
    }

    final String formattedHour = hour.toString().padLeft(2, '0');

    return '$formattedHour:$minute $period';
  }

  // ============================================================
  // ANNOUNCEMENT IMAGE
  // ============================================================

  Widget _buildAnnouncementImage(String imageUrl) {
    return Container(
      width: 95,
      height: 95,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F5FF),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFE2EAF5), width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl.isNotEmpty
          ? Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(
                  Icons.account_balance,
                  size: 45,
                  color: primaryBlue,
                );
              },
            )
          : const Icon(Icons.account_balance, size: 45, color: primaryBlue),
    );
  }

  // ============================================================
  // EMPTY STATE CARD
  // ============================================================

  Widget _buildEmptyCard({required IconData icon, required String message}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(icon, size: 35, color: Colors.grey),

          const SizedBox(height: 10),

          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.grey,
              fontFamily: 'Biennale',
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // PLACEHOLDER PAGES
  // ============================================================

  Widget _buildPlaceholderPage({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(25),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 65, color: primaryBlue),

            const SizedBox(height: 20),

            Text(
              title,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: darkBlue,
                fontFamily: 'Biennale',
              ),
            ),

            const SizedBox(height: 10),

            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                color: Colors.grey,
                fontFamily: 'Biennale',
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ERROR PAGE
  // ============================================================

  Widget _buildErrorPage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(25),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 55, color: Colors.redAccent),

            const SizedBox(height: 15),

            Text(
              _errorMessage ?? 'Something went wrong.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontFamily: 'Biennale'),
            ),

            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: () {
                _loadUserData();
              },
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}
