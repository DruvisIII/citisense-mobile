import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:citisense/barangaySelection.dart';

class EmailVerification extends StatefulWidget {
  final String firstName;
  final String lastName;
  final String email;
  final String contactNumber;
  final String password;

  const EmailVerification({
    super.key,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.contactNumber,
    required this.password,
  });

  @override
  State<EmailVerification> createState() => _EmailVerificationState();
}

class _EmailVerificationState extends State<EmailVerification> {
  static const String _verifyUrl =
      'http://10.119.145.252/citisense/api/verify_registration_otp.php';

  final TextEditingController _otpController = TextEditingController();

  bool _isVerifying = false;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _verifyOTP() async {
    if (_isVerifying) return;

    final otp = _otpController.text.trim();

    if (!RegExp(r'^[0-9]{6}$').hasMatch(otp)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid six-digit code.')),
      );
      return;
    }

    setState(() => _isVerifying = true);

    try {
      final response = await http.post(
        Uri.parse(_verifyUrl),
        headers: {'Accept': 'application/json'},
        body: {'email': widget.email, 'otp': otp},
      );

      final decoded = jsonDecode(response.body);

      if (response.statusCode == 200 && decoded['success'] == true) {
        final token = decoded['registrationToken']?.toString() ?? '';

        if (token.isEmpty) {
          throw Exception('Registration token was not returned.');
        }

        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => BarangaySelection(
              firstName: widget.firstName,
              lastName: widget.lastName,
              email: widget.email,
              contactNumber: widget.contactNumber,
              password: widget.password,
              registrationToken: token,
            ),
          ),
        );
      } else {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(decoded['message'] ?? 'Email verification failed.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Verification failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isVerifying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black),
          onPressed: _isVerifying ? null : () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 30),
              const Text(
                'Verify Your Email',
                style: TextStyle(
                  fontSize: 30,
                  fontFamily: 'Biennale',
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'We sent a six-digit verification code to:',
                style: TextStyle(
                  fontSize: 14,
                  fontFamily: 'Biennale',
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.email,
                style: const TextStyle(
                  fontSize: 15,
                  fontFamily: 'Biennale',
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF5887E0),
                ),
              ),
              const SizedBox(height: 35),
              const Text(
                'Verification Code',
                style: TextStyle(
                  fontSize: 15,
                  fontFamily: 'Biennale',
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                  hintText: 'Enter your six-digit code',
                  counterText: '',
                  prefixIcon: const Icon(Icons.lock_outline),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.blueGrey.shade200),
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
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: _isVerifying ? null : _verifyOTP,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5887E0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  child: _isVerifying
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'Verify Email',
                          style: TextStyle(
                            fontSize: 16,
                            fontFamily: 'Biennale',
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
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
