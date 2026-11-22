import 'dart:convert';
import 'package:citisense/api_config.dart';

import 'package:flutter/material.dart';
import 'package:citisense/app_theme.dart';
import 'package:citisense/mascot.dart';
import 'package:http/http.dart' as http;
import 'package:citisense/login.dart';

class BarangaySelection extends StatefulWidget {
  final String firstName;
  final String lastName;
  final String email;
  final String contactNumber;
  final String password;
  final String registrationToken;

  const BarangaySelection({
    super.key,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.contactNumber,
    required this.password,
    required this.registrationToken,
  });

  @override
  State<BarangaySelection> createState() => _BarangaySelectionState();
}

class _BarangaySelectionState extends State<BarangaySelection> {
  static const String _getBarangaysUrl = '$apiBaseUrl/get_barangays.php';

  static const String _registerUrl = '$apiBaseUrl/register.php';

  List<Map<String, String>> _barangays = [];
  List<Map<String, String>> _filteredBarangays = [];

  String? _selectedBarangayId;

  bool _isLoading = true;
  bool _isRegistering = false;

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();

    _searchController.addListener(_filterBarangays);
    _loadBarangays();
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterBarangays);
    _searchController.dispose();
    super.dispose();
  }

  // Load barangays from the database
  Future<void> _loadBarangays() async {
    setState(() => _isLoading = true);

    try {
      final response = await http
          .get(
            Uri.parse(_getBarangaysUrl),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        throw Exception('Server returned status code ${response.statusCode}.');
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map ||
          decoded['success'] != true ||
          decoded['data'] is! List) {
        throw Exception(
          decoded is Map
              ? decoded['message'] ?? 'Invalid barangay data.'
              : 'Invalid server response.',
        );
      }

      final loaded = <Map<String, String>>[];

      for (final item in decoded['data']) {
        if (item is Map &&
            item['barangayID'] != null &&
            item['barangayName'] != null) {
          final id = item['barangayID'].toString().trim();
          final name = item['barangayName'].toString().trim();

          if (id.isNotEmpty && name.isNotEmpty) {
            loaded.add({'barangayID': id, 'barangayName': name});
          }
        }
      }

      if (!mounted) return;

      setState(() {
        _barangays = loaded;
        _filteredBarangays = loaded;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => _isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load barangays: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  // Search and filter barangays
  void _filterBarangays() {
    final query = _searchController.text.trim().toLowerCase();

    final filtered = query.isEmpty
        ? _barangays
        : _barangays.where((barangay) {
            return barangay['barangayName']!.toLowerCase().contains(query);
          }).toList();

    if (!mounted) return;

    setState(() => _filteredBarangays = filtered);
  }

  // Register account after selecting a barangay
  Future<void> _registerAccount() async {
    if (_selectedBarangayId == null || _selectedBarangayId!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select your barangay first.')),
      );
      return;
    }

    if (_isRegistering || _isLoading) return;

    if (_barangays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Barangay list is unavailable. Please try again.'),
        ),
      );
      return;
    }

    setState(() => _isRegistering = true);

    try {
      final response = await http
          .post(
            Uri.parse(_registerUrl),
            headers: {'Accept': 'application/json'},
            body: {
              'firstName': widget.firstName,
              'lastName': widget.lastName,
              'email': widget.email,
              'password': widget.password,
              'contactNo': widget.contactNumber,
              'barangayID': _selectedBarangayId!,
              'registrationToken': widget.registrationToken,
            },
          )
          .timeout(const Duration(seconds: 20));

      final decoded = jsonDecode(response.body);

      if (decoded is! Map) {
        throw Exception('Invalid server response.');
      }

      if (response.statusCode == 200 && decoded['success'] == true) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account created successfully!'),
            backgroundColor: AppColors.success,
          ),
        );

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
        );
      } else {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              decoded['message']?.toString() ?? 'Failed to create account.',
            ),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Registration failed: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isRegistering = false);
      }
    }
  }

  // Barangay selection card
  Widget _buildBarangayCard(Map<String, String> barangay) {
    final barangayId = barangay['barangayID']!;
    final barangayName = barangay['barangayName']!;
    final isSelected = _selectedBarangayId == barangayId;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 40),
            child: Material(
              color: isSelected ? AppColors.primarySoft : AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.md),
                onTap: _isRegistering
                    ? null
                    : () {
                        setState(() {
                          _selectedBarangayId = barangayId;
                        });
                      },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(
                      color: isSelected ? AppColors.primary : AppColors.border,
                      width: isSelected ? 1.6 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.surface
                              : AppColors.primarySoft,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: const Icon(
                          Icons.location_city_outlined,
                          color: AppColors.primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              barangayName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontFamily: appFontFamily,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Cebu City',
                              style: TextStyle(
                                fontSize: 13,
                                fontFamily: appFontFamily,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.textMuted,
                            width: 2,
                          ),
                        ),
                        child: isSelected
                            ? Center(
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppColors.primary,
                                  ),
                                ),
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Every card (including newly added barangays) gets a mascot
          // peeking from behind its left edge. Drawn on top so its hand
          // overlaps the card edge; the body is cut off at the edge.
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 50,
            child: IgnorePointer(
              child: Center(
                child: SizedBox(
                  width: 50,
                  height: 84,
                  child: CitiMascot(
                    pose: isSelected
                        ? MascotPose.sidePeekHappy
                        : MascotPose.sidePeek,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(String text, {Widget? action}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Column(
          children: [
            Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                fontFamily: appFontFamily,
                color: AppColors.textSecondary,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 12), action],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: _isRegistering ? null : () => Navigator.pop(context),
        ),
        title: const Text('Select Your Barangay'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    const Text(
                      'Choose a barangay to report and monitor community issues.',
                      style: AppText.subtitle,
                    ),
                    const SizedBox(height: 20),

                    // Search field
                    TextField(
                      controller: _searchController,
                      enabled: !_isRegistering,
                      style: const TextStyle(
                        fontFamily: appFontFamily,
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search barangay...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: _searchController.clear,
                              )
                            : null,
                      ),
                    ),

                    const SizedBox(height: 24),

                    Row(
                      children: [
                        const Text('BARANGAYS', style: AppText.sectionLabel),
                        const Spacer(),
                        if (!_isLoading && _barangays.isNotEmpty)
                          Text(
                            '${_filteredBarangays.length} found',
                            style: const TextStyle(
                              fontSize: 12,
                              fontFamily: appFontFamily,
                              color: AppColors.textMuted,
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    if (_isLoading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.only(top: 40),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (_barangays.isEmpty)
                      _buildMessage(
                        'Unable to load barangays.',
                        action: TextButton(
                          onPressed: _loadBarangays,
                          child: const Text('Try Again'),
                        ),
                      )
                    else if (_filteredBarangays.isEmpty)
                      _buildMessage('No barangay found.')
                    else
                      ..._filteredBarangays.map(_buildBarangayCard),

                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),

            // Continue button
            Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.divider)),
              ),
              child: Column(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed:
                              (_isRegistering ||
                                  _isLoading ||
                                  _barangays.isEmpty)
                              ? null
                              : _registerAccount,
                          child: _isRegistering
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Continue'),
                        ),
                      ),
                      // Mascot peeks out from behind the button and hides.
                      const Positioned(
                        left: 18,
                        top: -70,
                        child: IgnorePointer(
                          child: SizedBox(
                            width: 96,
                            height: 75,
                            child: CitiMascot(pose: MascotPose.peek),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Help us build a safer and better community.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: appFontFamily,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
