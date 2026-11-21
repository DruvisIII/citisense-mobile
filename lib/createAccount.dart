import 'dart:convert';
import 'package:citisense/api_config.dart';

import 'package:flutter/material.dart';
import 'package:citisense/app_theme.dart';
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
      '$serverBaseUrl/api/send_registration_otp.php';

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
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to send verification code: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSendingOtp = false);
      }
    }
  }

  InputDecoration _inputDecoration(String hint, IconData icon) {
    // Borders, fill and colors come from AppTheme so every form matches.
    return InputDecoration(hintText: hint, prefixIcon: Icon(icon));
  }

  Widget _fieldLabel(String label) {
    return Text(label, style: AppText.fieldLabel);
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
          textInputAction: TextInputAction.next,
          style: const TextStyle(fontFamily: appFontFamily, fontSize: 14),
          decoration: _inputDecoration(hint, icon),
        ),
      ],
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
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              const Text('Create Account', style: AppText.pageTitle),
              const SizedBox(height: 8),
              const Text(
                'Create an account to start reporting community issues.',
                style: AppText.subtitle,
              ),
              const SizedBox(height: 32),

              // First and last name side by side saves vertical space
              // on wider phones; they stack on narrow ones.
              LayoutBuilder(
                builder: (context, constraints) {
                  final firstName = _textField(
                    label: 'First Name',
                    hint: 'First name',
                    icon: Icons.person_outline,
                    controller: _firstNameController,
                    keyboardType: TextInputType.name,
                    capitalization: TextCapitalization.words,
                  );
                  final lastName = _textField(
                    label: 'Last Name',
                    hint: 'Last name',
                    icon: Icons.person_outline,
                    controller: _lastNameController,
                    keyboardType: TextInputType.name,
                    capitalization: TextCapitalization.words,
                  );

                  if (constraints.maxWidth < 360) {
                    return Column(
                      children: [firstName, const SizedBox(height: 20), lastName],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: firstName),
                      const SizedBox(width: 12),
                      Expanded(child: lastName),
                    ],
                  );
                },
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
                style: const TextStyle(fontFamily: appFontFamily, fontSize: 14),
                decoration:
                    _inputDecoration(
                      'Enter your password',
                      Icons.lock_outline,
                    ).copyWith(
                      helperText: 'At least 6 characters',
                      helperStyle: const TextStyle(
                        fontFamily: appFontFamily,
                        color: AppColors.textMuted,
                      ),
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

              const SizedBox(height: 28),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isSendingOtp ? null : _createAccount,
                  child: _isSendingOtp
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text('Next'),
                ),
              ),

              const SizedBox(height: 28),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Already have an account? ',
                    style: TextStyle(
                      fontSize: 14,
                      fontFamily: appFontFamily,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginPage()),
                      );
                    },
                    child: const Text('Log In', style: AppText.link),
                  ),
                ],
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
