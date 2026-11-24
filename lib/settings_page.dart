import 'dart:async';
import 'dart:convert';
import 'package:citisense/api_config.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:citisense/api_client.dart';
import 'package:citisense/auth_session.dart';
import 'package:citisense/session_manager.dart';
import 'package:citisense/change_password_page.dart';
import 'package:citisense/friendly_errors.dart';
import 'package:citisense/validators.dart';
import 'package:citisense/app_theme.dart';
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

  /// Tells Home about saved personal details (name, picture, ...).
  final ValueChanged<Map<String, dynamic>>? onProfileUpdated;

  const SettingsPage({
    super.key,
    required this.userID,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.contactNo,
    this.profilePic,
    required this.barangayID,
    this.onProfileUpdated,
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

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Home refreshed the profile from the server (e.g. a new picture).
    if (widget.profilePic != oldWidget.profilePic &&
        (widget.profilePic ?? '').isNotEmpty) {
      _profilePic = widget.profilePic;
    }
    if (widget.firstName != oldWidget.firstName) _firstName = widget.firstName;
    if (widget.lastName != oldWidget.lastName) _lastName = widget.lastName;
    if (widget.email != oldWidget.email) _email = widget.email;
    if (widget.contactNo != oldWidget.contactNo) _contactNo = widget.contactNo;
    if (widget.barangayID != oldWidget.barangayID) {
      _barangayID = widget.barangayID;
    }
  }

  String get _fullName {
    return '$_firstName $_lastName'.trim();
  }

  String? _getProfileImageUrl(String? profilePic) =>
      profileImageUrl(profilePic);

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
      widget.onProfileUpdated?.call(result);
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
                child: _buildChangePasswordCard(),
              ),
              const SizedBox(height: 12),
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
                      fontFamily: appHeadingFontFamily,
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
                    fontFamily: appHeadingFontFamily,
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
                        fontFamily: appHeadingFontFamily,
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
                          fontFamily: appHeadingFontFamily,
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

  // The Small / Medium / Large switch sits on its own row under the title,
  // so at Large text the title keeps the full width and never breaks
  // into single letters.
  Widget _buildFontSizeTile() => Container(
    decoration: _cardDecoration(),
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _buildIconCircle(
              Icons.text_fields_rounded,
              AppColors.successSoft,
              AppColors.success,
            ),
            const SizedBox(width: 13),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Font Size',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: appHeadingFontFamily,
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
                      fontSize: 12.5,
                      height: 1.4,
                      color: textGrey,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ValueListenableBuilder<double>(
          valueListenable: appFontScale,
          builder: (context, scale, child) {
            final selected = scale <= 0.85
                ? 'Small'
                : scale >= 1.15
                ? 'Large'
                : 'Medium';
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Row(
                children: [
                  Expanded(child: _fontOption('Small', selected)),
                  Expanded(child: _fontOption('Medium', selected)),
                  Expanded(child: _fontOption('Large', selected)),
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
                  fontFamily: appHeadingFontFamily,
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

  Widget _buildChangePasswordCard() => _tappableCard(
    onTap: () {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChangePasswordPage(userID: widget.userID),
        ),
      );
    },
    padding: const EdgeInsets.all(16),
    child: Row(
      children: [
        _buildIconCircle(
          Icons.lock_outline_rounded,
          AppColors.primarySoft,
          AppColors.primary,
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Change Password',
                style: TextStyle(
                  fontFamily: appHeadingFontFamily,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: darkBlue,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Update the password you use to log in.',
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
                  fontFamily: appHeadingFontFamily,
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
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.sm - 3),
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
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.fade,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? darkBlue : textGrey,
            fontFamily: appHeadingFontFamily,
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
              fontFamily: appHeadingFontFamily,
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
                  fontFamily: appHeadingFontFamily,
                ),
              ),
            ),
          ],
        );
      },
    ).then((confirmed) {
      if (confirmed == true && mounted) {
        // Ends the session on the server and on this phone, then shows
        // Log In with nothing behind it.
        SessionManager.logout();
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

    // Shown as +63 followed by the 10 digits (stored as 09XXXXXXXXX).
    _contactController = TextEditingController(
      text: PhilippinePhone.localPart(widget.contactNo),
    );
    _contactController.addListener(() {
      if (mounted) setState(() {});
    });

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

  String? _getProfileImageUrl(String? profilePic) =>
      profileImageUrl(profilePic);

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
                      fontFamily: appHeadingFontFamily,
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
                              fontFamily: appHeadingFontFamily,
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

    final String phoneDigits = _contactController.text.trim();
    final contactNo = PhilippinePhone.toStored(phoneDigits);

    if (firstName.isEmpty ||
        lastName.isEmpty ||
        email.isEmpty ||
        phoneDigits.isEmpty ||
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

    if (!PhilippinePhone.isValid(phoneDigits)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please enter a valid mobile number: 10 digits after +63.',
          ),
          backgroundColor: AppColors.danger,
        ),
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

        request.headers.addAll(AuthSession.headers());
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
          headers: AuthSession.headers(
            extra: {'Content-Type': 'application/x-www-form-urlencoded'},
          ),
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

      dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        decoded = null;
      }

      if (response.statusCode != 200 ||
          decoded is! Map ||
          decoded['success'] != true) {
        throw Exception(
          FriendlyErrors.fromResponse(
            response,
            fallback: 'We could not save your details. Please try again.',
          ),
        );
      }

      final updatedUser = decoded['data'] ?? {};

      final updatedProfilePic = updatedUser['profilePic'] ?? _profilePic;

      // A new picture: check that the saved file can really be loaded
      // before saying it worked.
      bool pictureLoaded = true;
      if (_selectedImage != null) {
        final newUrl = _getProfileImageUrl(updatedProfilePic?.toString());
        final oldUrl = _getProfileImageUrl(widget.profilePic);
        if (oldUrl != null) {
          // Never show the previous picture from the cache again.
          await NetworkImage(oldUrl).evict();
        }
        pictureLoaded =
            newUrl != null &&
            updatedProfilePic?.toString() != widget.profilePic &&
            mounted &&
            await _canLoadImage(newUrl);
      }

      if (!mounted) {
        return;
      }

      if (!pictureLoaded) {
        setState(() {
          _isSaving = false;
          _profilePic = updatedProfilePic?.toString();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Your details were saved, but the new profile picture could '
              'not be loaded. Please check your connection and try again.',
            ),
            backgroundColor: AppColors.danger,
          ),
        );
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

      debugPrint('Update profile error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(FriendlyErrors.fromException(e)),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  /// True when the picture at [url] downloads and decodes.
  Future<bool> _canLoadImage(String url) async {
    final completer = Completer<bool>();
    final stream = NetworkImage(url).resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (image, synchronousCall) {
        if (!completer.isCompleted) completer.complete(true);
        stream.removeListener(listener);
      },
      onError: (error, stackTrace) {
        debugPrint('New profile picture could not be loaded: $error');
        if (!completer.isCompleted) completer.complete(false);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    return completer.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        stream.removeListener(listener);
        return false;
      },
    );
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
    List<TextInputFormatter>? inputFormatters,
    String? prefixText,
    String? errorText,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        enabled: _isEditing,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        style: const TextStyle(
          fontSize: 15,
          color: darkBlue,
          fontFamily: appFontFamily,
        ),
        decoration: InputDecoration(
          labelText: label,
          prefixText: prefixText,
          prefixStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: darkBlue,
            fontFamily: appHeadingFontFamily,
          ),
          errorText: errorText,
          errorMaxLines: 2,
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            borderSide: const BorderSide(color: AppColors.danger),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            borderSide: const BorderSide(color: AppColors.danger, width: 1.5),
          ),
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
            fontFamily: appHeadingFontFamily,
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
                  fontFamily: appHeadingFontFamily,
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
                  fontFamily: appHeadingFontFamily,
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
                    fontFamily: appHeadingFontFamily,
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
                inputFormatters: PhilippinePhone.inputFormatters,
                prefixText: '${PhilippinePhone.countryCode} ',
                errorText: _isEditing
                    ? PhilippinePhone.error(
                        _contactController.text,
                        showEmpty: true,
                      )
                    : null,
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
                              fontFamily: appHeadingFontFamily,
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
        ok
            ? (decoded['message']?.toString() ?? 'Verification code sent.')
            : FriendlyErrors.fromMessage(
                decoded['message']?.toString(),
                fallback: 'We could not send the code. Please try again.',
              ),
        emailTaken: taken,
      );
    } on TimeoutException {
      return const EmailCodeResult(
        false,
        'The server took too long to respond. Please try again.',
      );
    } catch (e) {
      debugPrint('Send email change code error: $e');
      return const EmailCodeResult(false, FriendlyErrors.noConnection);
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
        ok
            ? (decoded['message']?.toString() ?? 'Email verified.')
            : FriendlyErrors.fromMessage(
                decoded['message']?.toString(),
                fallback: 'That code did not work. Please try again.',
              ),
        emailTaken: decoded['code']?.toString() == 'EMAIL_TAKEN',
      );
    } catch (e) {
      debugPrint('Verify email change code error: $e');
      return const EmailCodeResult(false, FriendlyErrors.noConnection);
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
                    fontFamily: appHeadingFontFamily,
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
                    fontFamily: appHeadingFontFamily,
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

  bool _submitted = false;

  String? get _typeError =>
      _submitted && _type == null ? 'Choose the type of feedback.' : null;

  String? get _messageError {
    if (_error != null) return _error;
    return _submitted && _messageController.text.trim().isEmpty
        ? 'Please write your feedback.'
        : null;
  }

  Future<void> _send() async {
    // One request at a time, so a double tap cannot send it twice.
    if (_sending) return;

    setState(() {
      _submitted = true;
      _error = null;
    });

    if (_type == null || _messageController.text.trim().isEmpty) return;

    setState(() => _sending = true);

    try {
      final result = await ApiClient.postForm('submit_app_feedback.php', {
        'userID': widget.userID,
        'type': _type!,
        'rating': _rating.toString(),
        'message': _messageController.text.trim(),
      });

      if (!mounted) return;

      if (!result.success) {
        setState(() {
          _sending = false;
          _error = result.message;
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
        _error = FriendlyErrors.fromException(e);
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
              // Two per row; each button grows with the text size.
              for (int i = 0; i < _types.length; i += 2) ...[
                if (i > 0) const SizedBox(height: 10),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (int j = i; j < i + 2 && j < _types.length; j++) ...[
                        if (j > i) const SizedBox(width: 10),
                        Expanded(
                          child: _typeChip(
                            value: _types[j].$1,
                            label: _types[j].$2,
                            icon: _types[j].$3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              if (_typeError != null) ...[
                const SizedBox(height: 6),
                Text(
                  _typeError!,
                  style: const TextStyle(
                    fontFamily: appFontFamily,
                    fontSize: 12,
                    color: AppColors.danger,
                  ),
                ),
              ],

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
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                decoration: InputDecoration(
                  hintText:
                      'Tell us what you like, what is wrong, or what '
                      'we could improve...',
                  fillColor: Colors.white,
                  errorText: _messageError,
                  errorMaxLines: 3,
                ),
              ),

              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _sending ? null : _send,
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
          constraints: const BoxConstraints(minHeight: 50),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: selected
                  ? AppColors.primary
                  : (_typeError != null ? AppColors.danger : AppColors.border),
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
                  style: TextStyle(
                    fontFamily: appHeadingFontFamily,
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
