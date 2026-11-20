import 'dart:convert';

import 'package:flutter/material.dart';
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
  static const String _getBarangaysUrl =
      'http://10.119.145.252/citisense/api/get_barangays.php';

  static const String _registerUrl =
      'http://10.119.145.252/citisense/api/register.php';

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
          backgroundColor: Colors.red,
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
            backgroundColor: Colors.green,
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
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Registration failed: $e'),
          backgroundColor: Colors.red,
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

    return GestureDetector(
      onTap: _isRegistering
          ? null
          : () {
              setState(() {
                _selectedBarangayId = barangayId;
              });
            },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF5887E0)
                : Colors.blueGrey.shade100,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF1FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.location_city_outlined,
                color: Color(0xFF5887E0),
                size: 25,
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
                      fontFamily: 'Biennale',
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Cebu City',
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: 'Biennale',
                      color: Colors.grey,
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
                      ? const Color(0xFF5887E0)
                      : Colors.grey.shade400,
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
                          color: Color(0xFF5887E0),
                        ),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black),
          onPressed: _isRegistering ? null : () => Navigator.pop(context),
        ),
        title: const Text(
          'Select Your Barangay',
          style: TextStyle(
            fontSize: 20,
            fontFamily: 'Biennale',
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 10),
                    const Text(
                      'Choose a barangay to report and monitor community issues.',
                      style: TextStyle(
                        fontSize: 14,
                        fontFamily: 'Biennale',
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 25),

                    // Search field
                    TextField(
                      controller: _searchController,
                      enabled: !_isRegistering,
                      decoration: InputDecoration(
                        hintText: 'Search barangay...',
                        hintStyle: const TextStyle(
                          fontFamily: 'Biennale',
                          color: Colors.grey,
                        ),
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: _searchController.clear,
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: Colors.blueGrey.shade200,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Color(0xFF5887E0),
                            width: 2,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 25),

                    const Text(
                      'Barangays',
                      style: TextStyle(
                        fontSize: 17,
                        fontFamily: 'Biennale',
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),

                    const SizedBox(height: 15),

                    if (_isLoading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.only(top: 40),
                          child: CircularProgressIndicator(
                            color: Color(0xFF5887E0),
                          ),
                        ),
                      )
                    else if (_barangays.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 40),
                          child: Column(
                            children: [
                              const Text(
                                'Unable to load barangays.',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontFamily: 'Biennale',
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: _loadBarangays,
                                child: const Text('Try Again'),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (_filteredBarangays.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.only(top: 40),
                          child: Text(
                            'No barangay found.',
                            style: TextStyle(
                              fontSize: 14,
                              fontFamily: 'Biennale',
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      )
                    else
                      ..._filteredBarangays.map(_buildBarangayCard),

                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),

            // Continue button
            Padding(
              padding: const EdgeInsets.fromLTRB(30, 10, 30, 0),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed:
                          (_isRegistering || _isLoading || _barangays.isEmpty)
                          ? null
                          : _registerAccount,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF5887E0),
                        disabledBackgroundColor: Colors.blueGrey.shade200,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: _isRegistering
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Continue',
                              style: TextStyle(
                                fontSize: 16,
                                fontFamily: 'Biennale',
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Help us build a safer and better community.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: 'Biennale',
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
