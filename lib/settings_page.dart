import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'app_settings.dart';

const Color primaryBlue = Color(0xFF5887E0);
const Color darkBlue = Color(0xFF172D68);
const Color textGrey = Color(0xFF596887);
const Color backgroundColor = Color(0xFFF5F8FD);

const String baseUrl =
    // 'http://192.168.1.48/citisense/api';
    'http://10.127.214.252/citisense/api';

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
  late String _firstName;
  late String _lastName;
  late String _email;
  late String _contactNo;
  late String _barangayID;
  String? _profilePic;

  @override
  void initState() {
    super.initState();

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
      return 'http://192.168.1.48/citisense$value';
    }

    return 'http://192.168.1.48/citisense/$value';
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

  // UI state only. No AI preference backend is configured in the original file.
  bool _aiInsightsEnabled = true;

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
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: InkWell(
                  onTap: _openPersonalDetails,
                  borderRadius: BorderRadius.circular(24),
                  child: _buildProfileCard(),
                ),
              ),
              const SizedBox(height: 25),
              _buildSectionTitle('PREFERENCES'),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: _buildPreferencesCard(),
              ),
              const SizedBox(height: 25),
              _buildSectionTitle('ACCESSIBILITY'),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: _buildFontSizeTile(),
              ),
              const SizedBox(height: 25),
              _buildSectionTitle('ACCOUNT'),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
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
                      fontFamily: 'Biennale',
                      fontSize: 37,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                      color: Color(0xFF0E235B),
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
                  fontFamily: 'Biennale',
                  fontSize: 16,
                  height: 1.5,
                  color: textGrey,
                ),
              ),
            ),
            // Replace this placeholder with your mascot Image.asset later.
            Positioned(
              right: 18,
              top: 91,
              bottom: 10,
              width: (constraints.maxWidth - 44) * 0.40,
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF3FF),
                  border: Border.all(color: const Color(0xFFCFE1FF)),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Text(
                  'Mascot\nplaceholder',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Biennale',
                    fontSize: 13,
                    color: textGrey,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration() => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(23),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFF344B79).withOpacity(0.08),
        blurRadius: 17,
        offset: const Offset(0, 5),
      ),
    ],
  );

  Widget _buildProfileCard() {
    final imageUrl = _getProfileImageUrl(_profilePic);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 18),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          ClipOval(
            child: SizedBox(
              width: 71,
              height: 71,
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
                    fontFamily: 'Biennale',
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
                    fontFamily: 'Biennale',
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
    color: const Color(0xFFE4EEFF),
    child: const Icon(Icons.person_rounded, color: primaryBlue, size: 42),
  );

  Widget _buildSectionTitle(String title) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 21),
    child: Text(
      title,
      style: const TextStyle(
        fontFamily: 'Biennale',
        fontSize: 13,
        color: textGrey,
        fontWeight: FontWeight.w800,
      ),
    ),
  );

  Widget _buildIconCircle(IconData icon, Color bg, Color color) => Container(
    width: 51,
    height: 51,
    decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
    child: Icon(icon, color: color, size: 27),
  );

  Widget _buildPreferencesCard() => Container(
    decoration: _cardDecoration(),
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 15),
          child: Row(
            children: [
              _buildIconCircle(
                Icons.auto_awesome,
                const Color(0xFFF0E7FF),
                const Color(0xFF8045DF),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'AI Insights',
                      style: TextStyle(
                        fontFamily: 'Biennale',
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: darkBlue,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Get AI-powered insights about community issues.',
                      style: TextStyle(
                        fontFamily: 'Biennale',
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
                activeColor: const Color(0xFF1563ED),
                onChanged: (value) =>
                    setState(() => _aiInsightsEnabled = value),
              ),
            ],
          ),
        ),
        const Divider(
          height: 1,
          thickness: 0.8,
          indent: 65,
          color: Color(0xFFECF0F6),
        ),
        InkWell(
          onTap: () {}, // No notification preferences action existed in source.
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              children: [
                _buildIconCircle(
                  Icons.notifications_none_rounded,
                  const Color(0xFFE9F1FF),
                  const Color(0xFF1768F3),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'AI Insights Notification',
                        style: TextStyle(
                          fontFamily: 'Biennale',
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: darkBlue,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Receive notifications for new AI insights.',
                        style: TextStyle(
                          fontFamily: 'Biennale',
                          fontSize: 12.5,
                          height: 1.4,
                          color: textGrey,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 27,
                  color: textGrey,
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
    padding: const EdgeInsets.all(15),
    child: Row(
      children: [
        _buildIconCircle(
          Icons.text_fields_rounded,
          const Color(0xFFE7F8ED),
          const Color(0xFF28B55C),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Font Size',
                style: TextStyle(
                  fontFamily: 'Biennale',
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: darkBlue,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Adjust the text size in the app.',
                style: TextStyle(
                  fontFamily: 'Biennale',
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
                color: const Color(0xFFF1F2F6),
                borderRadius: BorderRadius.circular(17),
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

  Widget _buildLogoutCard() => InkWell(
    onTap: _logout,
    borderRadius: BorderRadius.circular(23),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 18),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          _buildIconCircle(
            Icons.logout_rounded,
            const Color(0xFFFFE9E9),
            const Color(0xFFF02E38),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Log Out',
                  style: TextStyle(
                    fontFamily: 'Biennale',
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: darkBlue,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Sign out of your account.',
                  style: TextStyle(
                    fontFamily: 'Biennale',
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
                    color: Colors.black.withOpacity(0.06),
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
            fontFamily: 'Biennale',
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
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Logout',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: darkBlue,
              fontFamily: 'Biennale',
            ),
          ),
          content: const Text(
            'Are you sure you want to logout?',
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: textGrey,
              fontFamily: 'Biennale',
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
                  fontFamily: 'Biennale',
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text(
                'Logout',
                style: TextStyle(
                  color: Color(0xFFE14D4D),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Biennale',
                ),
              ),
            ),
          ],
        );
      },
    ).then((confirmed) {
      if (confirmed == true && mounted) {
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
      return 'http://192.168.1.48/citisense$value';
    }

    return 'http://192.168.1.48/citisense/$value';
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
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 15),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 45,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),

                const SizedBox(height: 20),

                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Select Barangay',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: darkBlue,
                      fontFamily: 'Biennale',
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
                              color: Color(0xFFE8F0FF),
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
                              fontFamily: 'Biennale',
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
        color: Color(0xFFE8F0FF),
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
          fontFamily: 'Biennale',
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: textGrey, fontFamily: 'Biennale'),
          prefixIcon: Icon(icon, color: primaryBlue),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 15,
            vertical: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(17),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(17),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(17),
            borderSide: const BorderSide(color: primaryBlue, width: 1.5),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(17),
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
          borderRadius: BorderRadius.circular(17),
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
                      fontFamily: 'Biennale',
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
                      fontFamily: 'Biennale',
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
            fontFamily: 'Biennale',
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
                  fontFamily: 'Biennale',
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
                  fontFamily: 'Biennale',
                ),
              ),

              const SizedBox(height: 5),

              Text(
                _emailController.text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: textGrey,
                  fontFamily: 'Biennale',
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
                    fontFamily: 'Biennale',
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
                      backgroundColor: primaryBlue,
                      disabledBackgroundColor: primaryBlue.withOpacity(0.5),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
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
                              fontFamily: 'Biennale',
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
