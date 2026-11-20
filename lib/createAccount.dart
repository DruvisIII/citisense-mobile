import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:citisense/login.dart';
import 'package:citisense/emailVerification.dart';

class CreateAccount extends StatefulWidget {
  const CreateAccount({super.key});

  @override
  State<CreateAccount> createState() => _CreateAccountState();
}

class _CreateAccountState extends State<CreateAccount> {
  static const String _sendOtpUrl =
      'http://10.119.145.252/citisense/api/send_registration_otp.php';

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _contactController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isSendingOtp = false;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _contactController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Accept 09XXXXXXXXX, 639XXXXXXXXX, and +639XXXXXXXXX.
  // Store the normalized number as 09XXXXXXXXX.
  String? _normalizePhilippineNumber(String input) {
    String digits = input.replaceAll(RegExp(r'\D'), '');

    if (digits.startsWith('63')) {
      digits = '0${digits.substring(2)}';
    }

    if (RegExp(r'^09\d{9}$').hasMatch(digits)) {
      return digits;
    }

    return null;
  }

  Future<void> _createAccount() async {
    if (_isSendingOtp) return;

    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;
    final contactNumber = _normalizePhilippineNumber(_contactController.text);

    if (firstName.isEmpty ||
        lastName.isEmpty ||
        email.isEmpty ||
        _contactController.text.trim().isEmpty ||
        password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields.')),
      );
      return;
    }

    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email address.')),
      );
      return;
    }

    if (contactNumber == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please enter a valid Philippine mobile number (09XXXXXXXXX).',
          ),
        ),
      );
      return;
    }

    if (password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password must be at least 6 characters.'),
        ),
      );
      return;
    }

    setState(() => _isSendingOtp = true);

    try {
      final response = await http.post(
        Uri.parse(_sendOtpUrl),
        headers: {'Accept': 'application/json'},
        body: {'firstName': firstName, 'email': email},
      );

      final decoded = jsonDecode(response.body);

      if (response.statusCode == 200 && decoded['success'] == true) {
        if (!mounted) return;

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EmailVerification(
              firstName: firstName,
              lastName: lastName,
              email: email,
              contactNumber: contactNumber,
              password: password,
            ),
          ),
        );
      } else {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(decoded['message'] ?? 'Failed to send OTP.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to send verification code: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSendingOtp = false);
      }
    }
  }

  InputDecoration _inputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontFamily: 'Biennale', color: Colors.grey),
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.blueGrey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF5887E0), width: 2),
      ),
    );
  }

  Widget _fieldLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 15,
        fontFamily: 'Biennale',
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _textField({
    required String label,
    required String hint,
    required IconData icon,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization capitalization = TextCapitalization.none,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(label),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          textCapitalization: capitalization,
          decoration: _inputDecoration(hint, icon),
        ),
      ],
    );
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
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 10),
                const Text(
                  'Create Account',
                  style: TextStyle(
                    fontSize: 32,
                    fontFamily: 'Biennale',
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Create an account to start reporting community issues.',
                  style: TextStyle(
                    fontSize: 14,
                    fontFamily: 'Biennale',
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 30),

                _textField(
                  label: 'First Name',
                  hint: 'Enter your first name',
                  icon: Icons.person_outline,
                  controller: _firstNameController,
                  keyboardType: TextInputType.name,
                  capitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 20),

                _textField(
                  label: 'Last Name',
                  hint: 'Enter your last name',
                  icon: Icons.person_outline,
                  controller: _lastNameController,
                  keyboardType: TextInputType.name,
                  capitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 20),

                _textField(
                  label: 'Email',
                  hint: 'Enter your email',
                  icon: Icons.email_outlined,
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 20),

                _textField(
                  label: 'Contact Number',
                  hint: '09XXXXXXXXX or +639XXXXXXXXX',
                  icon: Icons.phone_outlined,
                  controller: _contactController,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 20),

                _fieldLabel('Password'),
                const SizedBox(height: 8),
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration:
                      _inputDecoration(
                        'Enter your password',
                        Icons.lock_outline,
                      ).copyWith(
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                ),

                const SizedBox(height: 30),

                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed: _isSendingOtp ? null : _createAccount,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5887E0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    child: _isSendingOtp
                        ? const SizedBox(
                            height: 23,
                            width: 23,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Next',
                            style: TextStyle(
                              fontSize: 16,
                              fontFamily: 'Biennale',
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 25),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Already have an account? ',
                      style: TextStyle(
                        fontSize: 14,
                        fontFamily: 'Biennale',
                        color: Colors.grey,
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const LoginPage()),
                        );
                      },
                      child: const Text(
                        'Login',
                        style: TextStyle(
                          fontSize: 14,
                          fontFamily: 'Biennale',
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF5887E0),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
