import 'dart:async';
import 'dart:convert';
import 'package:citisense/api_config.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:citisense/app_theme.dart';
import 'package:citisense/live_updates.dart';
import 'package:citisense/mascot.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'notification_preference.dart';

import 'app_settings.dart';

const String baseUrl = apiBaseUrl;
// 'http://192.168.1.6/citisense/api';

class SettingsPage extends StatefulWidget {
  final String userID;
  final String firstName;
  final String lastName;
  final String email;
  final String contactNo;
  final String? profilePic;
  final String barangayID;

  const SettingsPage({
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
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _notificationsEnabled = true;

  Future<void> _loadNotificationPreference() async {
    final enabled = await NotificationPreference.isEnabled();
    if (!mounted) return;
    setState(() => _notificationsEnabled = enabled);
  }

  Future<void> _changeNotificationPreference(bool enabled) async {
    await NotificationPreference.setEnabled(enabled);
    if (!mounted) return;
    setState(() => _notificationsEnabled = enabled);
  }

  late String _firstName;
  late String _lastName;
  late String _email;
  late String _contactNo;
  late String _barangayID;
  String? _profilePic;

  @override
  void initState() {
    super.initState();
    _loadNotificationPreference();
    _loadAiInsightsPreference();

    _firstName = widget.firstName;
    _lastName = widget.lastName;
    _email = widget.email;
    _contactNo = widget.contactNo;
    _barangayID = widget.barangayID;
    _profilePic = widget.profilePic;
  }

  String get _fullName {
    return '$_firstName $_lastName'.trim();
  }

  String? _getProfileImageUrl(String? profilePic) {
    final value = profilePic?.trim();

    if (value == null || value.isEmpty) {
      return null;
    }

    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }

    if (value.startsWith('/')) {
      return '$serverBaseUrl$value';
    }

    return '$serverBaseUrl/$value';
  }

  Future<void> _openPersonalDetails() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PersonalDetailsPage(
          userID: widget.userID,
          firstName: _firstName,
          lastName: _lastName,
          email: _email,
          contactNo: _contactNo,
          profilePic: _profilePic,
          barangayID: _barangayID,
        ),
      ),
    );

    if (result != null && result is Map<String, dynamic>) {
      setState(() {
        _firstName = result['firstName'] ?? _firstName;
        _lastName = result['lastName'] ?? _lastName;
        _email = result['email'] ?? _email;
        _contactNo = result['contactNo'] ?? _contactNo;
        _barangayID = result['barangayID'] ?? _barangayID;
        _profilePic = result['profilePic'] ?? _profilePic;
      });
    }
  }

  // Saved on this device; read by the Report an Issue screen.
  bool _aiInsightsEnabled = true;

  Future<void> _loadAiInsightsPreference() async {
    final enabled = await AiInsightsPreference.isEnabled();
    if (mounted) setState(() => _aiInsightsEnabled = enabled);
  }

  Future<void> _setAiInsights(bool enabled) async {
    setState(() => _aiInsightsEnabled = enabled);
    await AiInsightsPreference.setEnabled(enabled);
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          enabled
              ? 'AI Insights on: photos will be analyzed automatically.'
              : 'AI Insights off: you will choose the category yourself.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildProfileCard(),
              ),
              const SizedBox(height: 28),
              _buildSectionTitle('PREFERENCES'),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildPreferencesCard(),
              ),
              const SizedBox(height: 28),
              _buildSectionTitle('ACCESSIBILITY'),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildFontSizeTile(),
              ),
              const SizedBox(height: 28),
              _buildSectionTitle('SUPPORT'),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildAppFeedbackCard(),
              ),
              const SizedBox(height: 28),
              _buildSectionTitle('ACCOUNT'),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildLogoutCard(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Shared header geometry for Notifications and Settings.
  // Keep these measurements identical in both pages.
  Widget _buildHeader() {
    return SizedBox(
      width: double.infinity,
      height: 222,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            Positioned(
              left: 22,
              right: 22,
              top: 38,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Settings',
                    maxLines: 1,
                    softWrap: false,
                    style: const TextStyle(
                      fontFamily: appFontFamily,
                      fontSize: 37,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 22,
              top: 109,
              width: (constraints.maxWidth - 44) * 0.55,
              child: Text(
                'Manage your account and app preferences.',
                style: const TextStyle(
                  fontFamily: appFontFamily,
                  fontSize: 16,
                  height: 1.5,
                  color: textGrey,
                ),
              ),
            ),
            // Mascot (static pose for this page).
            Positioned(
              right: 18,
              top: 84,
              bottom: 6,
              width: (constraints.maxWidth - 44) * 0.40,
              child: const CitiMascot(
                pose: MascotPose.settings,
                backdrop: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration() => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(AppRadius.lg),
    boxShadow: AppShadows.card,
  );

  // White card whose tap ripple is visible (drawn above the card colour).
  Widget _tappableCard({
    required VoidCallback onTap,
    required EdgeInsetsGeometry padding,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      decoration: _cardDecoration(),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }

  Widget _buildProfileCard() {
    final imageUrl = _getProfileImageUrl(_profilePic);
    return _tappableCard(
      onTap: _openPersonalDetails,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          ClipOval(
            child: SizedBox(
              width: 64,
              height: 64,
              child: imageUrl == null
                  ? _defaultProfileIcon()
                  : Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) =>
                          _defaultProfileIcon(),
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _fullName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: appFontFamily,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: darkBlue,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _email,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: appFontFamily,
                    fontSize: 13,
                    color: textGrey,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: textGrey, size: 28),
        ],
      ),
    );
  }

  Widget _defaultProfileIcon() => Container(
    color: AppColors.primarySoft,
    child: const Icon(Icons.person_rounded, color: primaryBlue, size: 42),
  );

  Widget _buildSectionTitle(String title) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24),
    child: Text(title, style: AppText.sectionLabel),
  );

  Widget _buildIconCircle(IconData icon, Color bg, Color color) => Container(
    width: 46,
    height: 46,
    decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
    child: Icon(icon, color: color, size: 24),
  );

  Widget _buildPreferencesCard() => Container(
    decoration: _cardDecoration(),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 15),
          child: Row(
            children: [
              _buildIconCircle(
                Icons.auto_awesome,
                AppColors.accentSoft,
                AppColors.accent,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'AI Insights',
                      style: TextStyle(
                        fontFamily: appFontFamily,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: darkBlue,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Analyze report photos and pick the issue category automatically.',
                      style: TextStyle(
                        fontFamily: appFontFamily,
                        fontSize: 12.5,
                        height: 1.4,
                        color: textGrey,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _aiInsightsEnabled,
                activeTrackColor: AppColors.primary,
                onChanged: _setAiInsights,
              ),
            ],
          ),
        ),
        const Divider(
          height: 1,
          thickness: 1,
          indent: 60,
          color: AppColors.divider,
        ),
        InkWell(
          onTap: () => _changeNotificationPreference(!_notificationsEnabled),
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              children: [
                _buildIconCircle(
                  Icons.notifications_none_rounded,
                  AppColors.primarySoft,
                  AppColors.primary,
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Notifications',
                        style: TextStyle(
                          fontFamily: appFontFamily,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: darkBlue,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Choose whether CitiSense shows notification alerts.',
                        style: TextStyle(
                          fontFamily: appFontFamily,
                          fontSize: 12.5,
                          height: 1.4,
                          color: textGrey,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: _notificationsEnabled,
                  activeTrackColor: AppColors.primary,
                  onChanged: _changeNotificationPreference,
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildFontSizeTile() => Container(
    decoration: _cardDecoration(),
    padding: const EdgeInsets.all(16),
    child: Row(
      children: [
        _buildIconCircle(
          Icons.text_fields_rounded,
          AppColors.successSoft,
          AppColors.success,
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Font Size',
                style: TextStyle(
                  fontFamily: appFontFamily,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: darkBlue,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Adjust the text size in the app.',
                style: TextStyle(
                  fontFamily: appFontFamily,
                  fontSize: 12,
                  height: 1.4,
                  color: textGrey,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        ValueListenableBuilder<double>(
          valueListenable: appFontScale,
          builder: (context, scale, child) {
            final selected = scale <= 0.85
                ? 'Small'
                : scale >= 1.15
                ? 'Large'
                : 'Medium';
            return Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _fontOption('Small', selected),
                  _fontOption('Medium', selected),
                  _fontOption('Large', selected),
                ],
              ),
            );
          },
        ),
      ],
    ),
  );

  Widget _buildAppFeedbackCard() => _tappableCard(
    onTap: () {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AppFeedbackPage(userID: widget.userID),
        ),
      );
    },
    padding: const EdgeInsets.all(16),
    child: Row(
      children: [
        _buildIconCircle(
          Icons.rate_review_outlined,
          AppColors.primarySoft,
          AppColors.primary,
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Send App Feedback',
                style: TextStyle(
                  fontFamily: appFontFamily,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: darkBlue,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Share suggestions or report a problem with the app.',
                style: TextStyle(
                  fontFamily: appFontFamily,
                  fontSize: 12.5,
                  color: textGrey,
                ),
              ),
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded, color: textGrey, size: 28),
      ],
    ),
  );

  Widget _buildLogoutCard() => _tappableCard(
    onTap: _logout,
    padding: const EdgeInsets.all(16),
    child: Row(
      children: [
        _buildIconCircle(
          Icons.logout_rounded,
          AppColors.dangerSoft,
          AppColors.danger,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Log Out',
                style: TextStyle(
                  fontFamily: appFontFamily,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.danger,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Sign out of your account.',
                style: TextStyle(
                  fontFamily: appFontFamily,
                  fontSize: 12.5,
                  color: textGrey,
                ),
              ),
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded, color: textGrey, size: 28),
      ],
    ),
  );

  Widget _fontOption(String label, String selected) {
    final isSelected = label == selected;

    return GestureDetector(
      onTap: () {
        double newScale;

        if (label == 'Small') {
          newScale = 0.8;
        } else if (label == 'Large') {
          newScale = 1.2;
        } else {
          newScale = 1.0;
        }

        appFontScale.value = newScale;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.shadow.withValues(alpha: 0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? darkBlue : textGrey,
            fontFamily: appFontFamily,
          ),
        ),
      ),
    );
  }

  void _logout() {
    showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text(
            'Log Out',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: darkBlue,
              fontFamily: appFontFamily,
            ),
          ),
          content: const Text(
            'Are you sure you want to log out?',
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: textGrey,
              fontFamily: appFontFamily,
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(15, 0, 15, 15),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: textGrey,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontFamily: appFontFamily,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text(
                'Log Out',
                style: TextStyle(
                  color: AppColors.danger,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  fontFamily: appFontFamily,
                ),
              ),
            ),
          ],
        );
      },
    ).then((confirmed) {
      if (confirmed == true && mounted) {
        // Stop automatic refreshing.
        LiveUpdates.instance.stop();
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
    });
  }
}

// ============================================================
// PERSONAL DETAILS PAGE
// ============================================================

class PersonalDetailsPage extends StatefulWidget {
  final String userID;
  final String firstName;
  final String lastName;
  final String email;
  final String contactNo;
  final String? profilePic;
  final String barangayID;

  const PersonalDetailsPage({
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
  State<PersonalDetailsPage> createState() => _PersonalDetailsPageState();
}

class _PersonalDetailsPageState extends State<PersonalDetailsPage> {
  final ImagePicker _imagePicker = ImagePicker();

  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _emailController;
  late TextEditingController _contactController;

  String? _selectedBarangayID;
  String? _selectedBarangayName;

  String? _profilePic;
  XFile? _selectedImage;

  bool _isEditing = false;
  bool _isSaving = false;

  List<Map<String, dynamic>> _barangays = [];

  @override
  void initState() {
    super.initState();

    _firstNameController = TextEditingController(text: widget.firstName);

    _lastNameController = TextEditingController(text: widget.lastName);

    _emailController = TextEditingController(text: widget.email);

    _contactController = TextEditingController(text: widget.contactNo);

    _selectedBarangayID = widget.barangayID;
    _profilePic = widget.profilePic;

    _loadBarangays();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  Future<void> _loadBarangays() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/get_barangays.php'),
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode != 200) {
        return;
      }

      final decoded = jsonDecode(response.body);

      if (decoded['success'] != true) {
        return;
      }

      final List<dynamic> data = decoded['data'] ?? [];

      final barangays = data.map<Map<String, dynamic>>((item) {
        return {
          'barangayID': item['barangayID'].toString(),
          'barangayName': item['barangayName'].toString(),
        };
      }).toList();

      if (!mounted) {
        return;
      }

      setState(() {
        _barangays = barangays;

        for (final barangay in _barangays) {
          if (barangay['barangayID'] == _selectedBarangayID) {
            _selectedBarangayName = barangay['barangayName'];
            break;
          }
        }
      });
    } catch (e) {
      // Keep the current barangay if the request fails.
    }
  }

  String? _getProfileImageUrl(String? profilePic) {
    final value = profilePic?.trim();

    if (value == null || value.isEmpty) {
      return null;
    }

    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }

    if (value.startsWith('/')) {
      return '$serverBaseUrl$value';
    }

    return '$serverBaseUrl/$value';
  }

  Future<void> _changeProfilePicture() async {
    if (!_isEditing) {
      return;
    }

    final XFile? image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1000,
      maxHeight: 1000,
    );

    if (image == null) {
      return;
    }

    setState(() {
      _selectedImage = image;
    });
  }

  Future<void> _selectBarangay() async {
    if (!_isEditing) {
      return;
    }

    if (_barangays.isEmpty) {
      await _loadBarangays();
    }

    if (!mounted) {
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 15),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Select Barangay',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: darkBlue,
                      fontFamily: appFontFamily,
                    ),
                  ),
                ),

                const SizedBox(height: 15),

                if (_barangays.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(color: primaryBlue),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _barangays.length,
                      itemBuilder: (context, index) {
                        final barangay = _barangays[index];

                        final id = barangay['barangayID'].toString();

                        final name = barangay['barangayName'].toString();

                        final isSelected = id == _selectedBarangayID;

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 5,
                          ),
                          leading: Container(
                            width: 42,
                            height: 42,
                            decoration: const BoxDecoration(
                              color: AppColors.primarySoft,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.location_on_outlined,
                              color: primaryBlue,
                            ),
                          ),
                          title: Text(
                            name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: darkBlue,
                              fontFamily: appFontFamily,
                            ),
                          ),
                          trailing: isSelected
                              ? const Icon(
                                  Icons.check_circle,
                                  color: primaryBlue,
                                )
                              : null,
                          onTap: () {
                            setState(() {
                              _selectedBarangayID = id;
                              _selectedBarangayName = name;
                            });

                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _saveChanges() async {
    if (_isSaving) {
      return;
    }

    final firstName = _firstNameController.text.trim();

    final lastName = _lastNameController.text.trim();

    final email = _emailController.text.trim();

    final contactNo = _contactController.text.trim();

    if (firstName.isEmpty ||
        lastName.isEmpty ||
        email.isEmpty ||
        contactNo.isEmpty ||
        _selectedBarangayID == null ||
        _selectedBarangayID!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete all required fields.')),
      );

      return;
    }

    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email address.')),
      );

      return;
    }

    // ------------------------------------------------------
    // NEW EMAIL: check it is not used, then verify it with a code
    // ------------------------------------------------------
    final bool emailChanged =
        email.toLowerCase() != widget.email.trim().toLowerCase();

    if (emailChanged) {
      final bool verified = await _verifyNewEmail(email, firstName);
      if (!verified || !mounted) {
        return;
      }
    }

    setState(() {
      _isSaving = true;
    });

    try {
      http.Response response;

      // ------------------------------------------------------
      // IF A NEW PROFILE PICTURE WAS SELECTED
      // ------------------------------------------------------

      if (_selectedImage != null) {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('$baseUrl/update_profile.php'),
        );

        request.fields['userID'] = widget.userID;
        request.fields['firstName'] = firstName;
        request.fields['lastName'] = lastName;
        request.fields['email'] = email;
        request.fields['contactNo'] = contactNo;
        request.fields['barangayID'] = _selectedBarangayID!;

        request.files.add(
          await http.MultipartFile.fromPath(
            'profilePicture',
            _selectedImage!.path,
          ),
        );

        final streamedResponse = await request.send();

        response = await http.Response.fromStream(streamedResponse);
      }
      // ------------------------------------------------------
      // IF NO NEW PROFILE PICTURE WAS SELECTED
      // ------------------------------------------------------
      else {
        response = await http.post(
          Uri.parse('$baseUrl/update_profile.php'),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Accept': 'application/json',
          },
          body: {
            'userID': widget.userID,
            'firstName': firstName,
            'lastName': lastName,
            'email': email,
            'contactNo': contactNo,
            'barangayID': _selectedBarangayID!,
          },
        );
      }

      if (response.statusCode != 200) {
        throw Exception('Server returned ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);

      if (decoded['success'] != true) {
        throw Exception(decoded['message'] ?? 'Failed to update profile.');
      }

      final updatedUser = decoded['data'] ?? {};

      final updatedProfilePic = updatedUser['profilePic'] ?? _profilePic;

      if (!mounted) {
        return;
      }

      setState(() {
        _isEditing = false;
        _isSaving = false;

        _profilePic = updatedProfilePic?.toString();

        _selectedImage = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Personal details updated successfully.')),
      );

      // Return updated information to SettingsPage.
      Navigator.pop(context, {
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'contactNo': contactNo,
        'barangayID': _selectedBarangayID!,
        'profilePic': updatedProfilePic?.toString(),
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isSaving = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update details: $e')));
    }
  }

  // Sends a code to the new email (the server rejects emails that are
  // already used), then opens the code screen. Returns true once verified.
  Future<bool> _verifyNewEmail(String newEmail, String firstName) async {
    setState(() => _isSaving = true);

    final EmailCodeResult sent = await EmailChangeApi.sendCode(
      userID: widget.userID,
      firstName: firstName,
      newEmail: newEmail,
    );

    if (!mounted) {
      return false;
    }
    setState(() => _isSaving = false);

    if (!sent.success) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: Icon(
            sent.emailTaken
                ? Icons.alternate_email_rounded
                : Icons.mark_email_unread_outlined,
            color: AppColors.danger,
            size: 32,
          ),
          title: Text(
            sent.emailTaken ? 'Email already in use' : 'Could not send code',
            textAlign: TextAlign.center,
          ),
          content: Text(sent.message, textAlign: TextAlign.center),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return false;
    }

    final bool? verified = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EmailChangeVerificationPage(
          userID: widget.userID,
          firstName: firstName,
          newEmail: newEmail,
        ),
      ),
    );

    if (verified == true) {
      return true;
    }

    // The user went back: keep the current email. Other edits stay in the
    // form so they can still be saved.
    if (mounted) {
      setState(() => _emailController.text = widget.email);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Email change cancelled. Your email is still ${widget.email}.',
          ),
        ),
      );
    }

    return false;
  }

  Widget _buildProfilePicture() {
    // Newly selected image.
    if (_selectedImage != null) {
      return ClipOval(
        child: Image.file(
          File(_selectedImage!.path),
          width: 120,
          height: 120,
          fit: BoxFit.cover,
        ),
      );
    }

    // Existing image from database.
    final imageUrl = _getProfileImageUrl(_profilePic);

    if (imageUrl != null) {
      return ClipOval(
        child: Image.network(
          imageUrl,
          width: 120,
          height: 120,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _defaultProfilePicture();
          },
        ),
      );
    }

    return _defaultProfilePicture();
  }

  Widget _defaultProfilePicture() {
    return Container(
      width: 120,
      height: 120,
      decoration: const BoxDecoration(
        color: AppColors.primarySoft,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.person, size: 65, color: primaryBlue),
    );
  }

  Widget _buildEditableField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    TextInputType? keyboardType,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        enabled: _isEditing,
        keyboardType: keyboardType,
        style: const TextStyle(
          fontSize: 15,
          color: darkBlue,
          fontFamily: appFontFamily,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
            color: textGrey,
            fontFamily: appFontFamily,
          ),
          prefixIcon: Icon(icon, color: primaryBlue),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 15,
            vertical: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            borderSide: const BorderSide(color: primaryBlue, width: 1.5),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildBarangayField() {
    return GestureDetector(
      onTap: _isEditing ? _selectBarangay : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          children: [
            const Icon(Icons.location_on_outlined, color: primaryBlue),

            const SizedBox(width: 15),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Barangay',
                    style: TextStyle(
                      fontSize: 12,
                      color: textGrey,
                      fontFamily: appFontFamily,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    _selectedBarangayName ??
                        _selectedBarangayID ??
                        'Not provided',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: darkBlue,
                      fontFamily: appFontFamily,
                    ),
                  ),
                ],
              ),
            ),

            if (_isEditing) const Icon(Icons.chevron_right, color: textGrey),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fullName = '${widget.firstName} ${widget.lastName}'.trim();

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: darkBlue),
          onPressed: _isSaving
              ? null
              : () {
                  Navigator.pop(context);
                },
        ),
        title: const Text(
          'Personal Details',
          style: TextStyle(
            color: darkBlue,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            fontFamily: appFontFamily,
          ),
        ),
        centerTitle: true,
        actions: [
          if (!_isEditing)
            TextButton(
              onPressed: () {
                setState(() {
                  _isEditing = true;
                });
              },
              child: const Text(
                'Edit',
                style: TextStyle(
                  color: primaryBlue,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  fontFamily: appFontFamily,
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
          child: Column(
            children: [
              const SizedBox(height: 15),

              // PROFILE PICTURE
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  _buildProfilePicture(),

                  if (_isEditing)
                    GestureDetector(
                      onTap: _changeProfilePicture,
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: primaryBlue,
                          shape: BoxShape.circle,
                          border: Border.all(color: backgroundColor, width: 4),
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 15),

              Text(
                _isEditing
                    ? '${_firstNameController.text} '
                          '${_lastNameController.text}'
                    : fullName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  color: darkBlue,
                  fontFamily: appFontFamily,
                ),
              ),

              const SizedBox(height: 5),

              Text(
                _emailController.text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: textGrey,
                  fontFamily: appFontFamily,
                ),
              ),

              const SizedBox(height: 30),

              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Personal Information',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: darkBlue,
                    fontFamily: appFontFamily,
                  ),
                ),
              ),

              const SizedBox(height: 13),

              // FIRST NAME
              _buildEditableField(
                label: 'First Name',
                controller: _firstNameController,
                icon: Icons.person_outline,
              ),

              // LAST NAME
              _buildEditableField(
                label: 'Last Name',
                controller: _lastNameController,
                icon: Icons.person_outline,
              ),

              // EMAIL
              _buildEditableField(
                label: 'Email',
                controller: _emailController,
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
              ),

              // CONTACT
              _buildEditableField(
                label: 'Contact Number',
                controller: _contactController,
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
              ),

              // BARANGAY
              _buildBarangayField(),

              const SizedBox(height: 10),

              // SAVE BUTTON
              if (_isEditing)
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveChanges,
                    style: ElevatedButton.styleFrom(
                      disabledBackgroundColor: primaryBlue.withValues(
                        alpha: 0.5,
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 23,
                            height: 23,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Save Changes',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              fontFamily: appFontFamily,
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
// EMAIL CHANGE VERIFICATION
// ------------------------------------------------------------
// Server endpoints (in api/):
//   send_email_change_otp.php   POST userID, firstName, newEmail
//     -> {success, message, code}  code = "EMAIL_TAKEN" if already used
//   verify_email_change_otp.php POST userID, newEmail, otp
//     -> {success, message}        updates the email on success
//   cancel_email_change_otp.php POST userID
//     -> {success, message}        voids unused codes (email unchanged)
// ============================================================

class EmailCodeResult {
  const EmailCodeResult(this.success, this.message, {this.emailTaken = false});

  final bool success;
  final String message;
  final bool emailTaken;
}

class EmailChangeApi {
  EmailChangeApi._();

  static Future<EmailCodeResult> sendCode({
    required String userID,
    required String firstName,
    required String newEmail,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/send_email_change_otp.php'),
            headers: {'Accept': 'application/json'},
            body: {
              'userID': userID,
              'firstName': firstName,
              'newEmail': newEmail,
            },
          )
          .timeout(const Duration(seconds: 30));

      final decoded = jsonDecode(response.body);
      final bool ok = response.statusCode == 200 && decoded['success'] == true;
      final bool taken = decoded['code']?.toString() == 'EMAIL_TAKEN';

      return EmailCodeResult(
        ok,
        decoded['message']?.toString() ??
            (ok ? 'Verification code sent.' : 'Failed to send the code.'),
        emailTaken: taken,
      );
    } on TimeoutException {
      return const EmailCodeResult(
        false,
        'The server took too long to respond. Please try again.',
      );
    } catch (e) {
      debugPrint('Send email change code error: $e');
      return const EmailCodeResult(
        false,
        'Unable to send the verification code. Check your connection.',
      );
    }
  }

  // Invalidates any unused code so it can no longer change the email.
  static Future<void> cancel({required String userID}) async {
    try {
      await http
          .post(
            Uri.parse('$baseUrl/cancel_email_change_otp.php'),
            headers: {'Accept': 'application/json'},
            body: {'userID': userID},
          )
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      // The code still expires on its own after 5 minutes.
      debugPrint('Cancel email change error: $e');
    }
  }

  static Future<EmailCodeResult> verifyCode({
    required String userID,
    required String newEmail,
    required String otp,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/verify_email_change_otp.php'),
            headers: {'Accept': 'application/json'},
            body: {'userID': userID, 'newEmail': newEmail, 'otp': otp},
          )
          .timeout(const Duration(seconds: 30));

      final decoded = jsonDecode(response.body);
      final bool ok = response.statusCode == 200 && decoded['success'] == true;

      return EmailCodeResult(
        ok,
        decoded['message']?.toString() ??
            (ok ? 'Email verified.' : 'Invalid verification code.'),
        emailTaken: decoded['code']?.toString() == 'EMAIL_TAKEN',
      );
    } catch (e) {
      debugPrint('Verify email change code error: $e');
      return const EmailCodeResult(
        false,
        'Unable to verify the code. Check your connection.',
      );
    }
  }
}

class EmailChangeVerificationPage extends StatefulWidget {
  const EmailChangeVerificationPage({
    super.key,
    required this.userID,
    required this.firstName,
    required this.newEmail,
  });

  final String userID;
  final String firstName;
  final String newEmail;

  @override
  State<EmailChangeVerificationPage> createState() =>
      _EmailChangeVerificationPageState();
}

class _EmailChangeVerificationPageState
    extends State<EmailChangeVerificationPage> {
  final TextEditingController _otpController = TextEditingController();

  bool _isVerifying = false;
  bool _isResending = false;
  String? _error;

  // Wait time before another code can be requested.
  static const int _resendSeconds = 60;
  int _secondsLeft = _resendSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _secondsLeft = _resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsLeft <= 1) {
        timer.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  Future<void> _verify() async {
    final otp = _otpController.text.trim();

    if (!RegExp(r'^\d{6}$').hasMatch(otp)) {
      setState(() => _error = 'Enter the 6-digit code from your email.');
      return;
    }

    setState(() {
      _isVerifying = true;
      _error = null;
    });

    final result = await EmailChangeApi.verifyCode(
      userID: widget.userID,
      newEmail: widget.newEmail,
      otp: otp,
    );

    if (!mounted) return;

    if (result.success) {
      Navigator.pop(context, true);
      return;
    }

    setState(() {
      _isVerifying = false;
      _error = result.message;
    });
  }

  // Leave without changing the email (back arrow, system back, or the
  // "Keep my current email" button).
  void _cancel() {
    if (_isVerifying) return;
    _timer?.cancel();
    EmailChangeApi.cancel(userID: widget.userID);
    Navigator.pop(context, false);
  }

  Future<void> _resend() async {
    setState(() {
      _isResending = true;
      _error = null;
    });

    final result = await EmailChangeApi.sendCode(
      userID: widget.userID,
      firstName: widget.firstName,
      newEmail: widget.newEmail,
    );

    if (!mounted) return;
    setState(() => _isResending = false);

    if (result.success) {
      _otpController.clear();
      _startCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A new code was sent to your email.')),
      );
    } else {
      setState(() => _error = result.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Route the phone's back gesture through _cancel as well.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 20),
            onPressed: _isVerifying ? null : _cancel,
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: const Icon(
                    Icons.mark_email_read_outlined,
                    color: AppColors.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Verify Your New Email', style: AppText.pageTitle),
                const SizedBox(height: 8),
                const Text(
                  'To make sure this email is active and belongs to you, we sent '
                  'a six-digit code to:',
                  style: AppText.subtitle,
                ),
                const SizedBox(height: 4),
                Text(
                  widget.newEmail,
                  style: const TextStyle(
                    fontSize: 15,
                    fontFamily: appFontFamily,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 32),
                const Text('Verification Code', style: AppText.fieldLabel),
                const SizedBox(height: 8),
                TextField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  onSubmitted: (_) => _isVerifying ? null : _verify(),
                  style: const TextStyle(
                    fontFamily: appFontFamily,
                    fontSize: 20,
                    letterSpacing: 8,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                  decoration: InputDecoration(
                    hintText: '••••••',
                    counterText: '',
                    errorText: _error,
                    errorMaxLines: 3,
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isVerifying ? null : _verify,
                    child: _isVerifying
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Verify Email'),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: _secondsLeft > 0
                      ? Text(
                          'Resend code in ${_secondsLeft}s',
                          style: const TextStyle(
                            fontFamily: appFontFamily,
                            fontSize: 13,
                            color: AppColors.textMuted,
                          ),
                        )
                      : TextButton(
                          onPressed: _isResending ? null : _resend,
                          child: Text(
                            _isResending ? 'Sending...' : 'Resend Code',
                          ),
                        ),
                ),
                const SizedBox(height: 28),

                // Way out for users who changed their mind or can't open
                // the new inbox. Nothing is changed.
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Can't access this email?",
                        style: AppText.fieldLabel,
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'If you changed your mind, the address is no longer '
                        'active, or you can\'t sign in to it, go back. Your '
                        'current email will stay the same.',
                        style: TextStyle(
                          fontFamily: appFontFamily,
                          fontSize: 13,
                          height: 1.45,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(46),
                            backgroundColor: AppColors.surface,
                          ),
                          onPressed: _isVerifying ? null : _cancel,
                          child: const Text('Keep My Current Email'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// APP FEEDBACK
// ------------------------------------------------------------
// api/submit_app_feedback.php  POST userID, type, rating, message
// ============================================================

class AppFeedbackPage extends StatefulWidget {
  const AppFeedbackPage({super.key, required this.userID});

  final String userID;

  @override
  State<AppFeedbackPage> createState() => _AppFeedbackPageState();
}

class _AppFeedbackPageState extends State<AppFeedbackPage> {
  static const List<(String, String, IconData)> _types = [
    ('suggestion', 'Suggestion', Icons.lightbulb_outline_rounded),
    ('complaint', 'Complaint', Icons.report_gmailerrorred_outlined),
    ('bug', 'Bug / Problem', Icons.bug_report_outlined),
    ('other', 'Other', Icons.chat_bubble_outline_rounded),
  ];

  final TextEditingController _messageController = TextEditingController();
  String? _type;
  int _rating = 0;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _messageController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  bool get _canSend =>
      !_sending && _type != null && _messageController.text.trim().length >= 10;

  Future<void> _send() async {
    if (!_canSend) return;

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/submit_app_feedback.php'),
            headers: {'Accept': 'application/json'},
            body: {
              'userID': widget.userID,
              'type': _type!,
              'rating': _rating.toString(),
              'message': _messageController.text.trim(),
            },
          )
          .timeout(const Duration(seconds: 25));

      final decoded = jsonDecode(response.body);
      final bool ok = response.statusCode == 200 && decoded['success'] == true;

      if (!mounted) return;

      if (!ok) {
        setState(() {
          _sending = false;
          _error = decoded['message']?.toString() ?? 'Failed to send feedback.';
        });
        return;
      }

      setState(() => _sending = false);

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const SizedBox(
            width: 96,
            height: 96,
            child: CitiMascot(pose: MascotPose.thumbsUp),
          ),
          title: const Text('Thank you!', textAlign: TextAlign.center),
          content: const Text(
            'Your feedback was sent. It helps us make CitiSense better for '
            'everyone.',
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            ),
          ],
        ),
      );

      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('App feedback error: $e');
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = 'Unable to send feedback. Check your connection.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        title: const Text('App Feedback'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: _sending ? null : () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tell us what you think about CitiSense. Suggestions, '
                'complaints, and problem reports all help us improve.',
                style: AppText.subtitle,
              ),
              const SizedBox(height: 22),

              const Text('Type of feedback', style: AppText.fieldLabel),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 3.2,
                children: [
                  for (final t in _types)
                    _typeChip(value: t.$1, label: t.$2, icon: t.$3),
                ],
              ),

              const SizedBox(height: 22),
              const Text(
                'How would you rate the app? (optional)',
                style: AppText.fieldLabel,
              ),
              const SizedBox(height: 6),
              Row(
                children: List.generate(
                  5,
                  (i) => IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    onPressed: () =>
                        setState(() => _rating = _rating == i + 1 ? 0 : i + 1),
                    icon: Icon(
                      i < _rating
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: i < _rating
                          ? const Color(0xFFF5B800)
                          : AppColors.border,
                      size: 34,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 18),
              const Text('Your feedback', style: AppText.fieldLabel),
              const SizedBox(height: 8),
              TextField(
                controller: _messageController,
                minLines: 5,
                maxLines: 8,
                maxLength: 1000,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(fontFamily: appFontFamily, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Write at least 10 characters...',
                  fillColor: Colors.white,
                  errorText: _error,
                  errorMaxLines: 3,
                ),
              ),

              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _canSend ? _send : null,
                  child: _sending
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Send Feedback'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typeChip({
    required String value,
    required String label,
    required IconData icon,
  }) {
    final bool selected = _type == value;

    return Material(
      color: selected ? AppColors.primarySoft : Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: _sending ? null : () => setState(() => _type = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? AppColors.primary : AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: appFontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: selected ? AppColors.primary : AppColors.ink,
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
