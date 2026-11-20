import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  // Keep this IP address synchronized with login.dart.
  static const String _apiBaseUrl = 'http://10.119.145.252/citisense/api';

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  // 0 = Request OTP, 1 = Verify OTP, 2 = Reset Password
  int _step = 0;

  String? _resetToken;

  bool _isLoading = false;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  static const Color _primaryBlue = Color(0xFF2563D9);
  static const Color _darkBlue = Color(0xFF173B70);
  static const Color _textGrey = Color(0xFF777777);

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------
  // SEND REQUEST TO PHP API
  // ------------------------------------------------------------

  Future<Map<String, dynamic>> _post(
    String endpoint,
    Map<String, String> data,
  ) async {
    final response = await http
        .post(
          Uri.parse('$_apiBaseUrl/$endpoint'),
          headers: {'Accept': 'application/json'},
          body: data,
        )
        .timeout(const Duration(seconds: 30));

    final dynamic decoded = jsonDecode(response.body);

    if (decoded is! Map<String, dynamic>) {
      throw Exception('The server returned an invalid response.');
    }

    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        decoded['success'] != true) {
      throw Exception(
        decoded['message']?.toString() ?? 'The request could not be completed.',
      );
    }

    return decoded;
  }

  // ------------------------------------------------------------
  // SHOW MESSAGE
  // ------------------------------------------------------------

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade700 : _darkBlue,
      ),
    );
  }

  // ------------------------------------------------------------
  // STEP 1: REQUEST EMAIL OTP
  // ------------------------------------------------------------

  Future<void> _requestCode() async {
    final email = _emailController.text.trim();

    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      _showMessage('Please enter a valid email address.', error: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await _post('forgot_password.php', {'email': email});

      if (!mounted) return;

      setState(() {
        _step = 1;
      });

      _showMessage(result['message']?.toString() ?? 'Request completed.');
    } catch (e) {
      _showMessage(e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ------------------------------------------------------------
  // STEP 2: VERIFY EMAIL OTP
  // ------------------------------------------------------------

  Future<void> _verifyCode() async {
    final otp = _otpController.text.trim();

    if (!RegExp(r'^\d{6}$').hasMatch(otp)) {
      _showMessage('Enter the six-digit code.', error: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await _post('verify_otp.php', {
        'email': _emailController.text.trim(),
        'method': 'email',
        'otp': otp,
      });

      final token = result['resetToken']?.toString();

      if (token == null || token.isEmpty) {
        throw Exception('The server did not provide a reset session.');
      }

      if (!mounted) return;

      setState(() {
        _resetToken = token;
        _step = 2;
      });
    } catch (e) {
      _showMessage(e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ------------------------------------------------------------
  // STEP 3: RESET PASSWORD
  // ------------------------------------------------------------

  Future<void> _resetPassword() async {
    final password = _newPasswordController.text;
    final confirmation = _confirmPasswordController.text;

    if (password.length < 8) {
      _showMessage(
        'Your password must contain at least 8 characters.',
        error: true,
      );
      return;
    }

    if (password != confirmation) {
      _showMessage('The passwords do not match.', error: true);
      return;
    }

    if (_resetToken == null) {
      _showMessage(
        'Your reset session is missing. Please start again.',
        error: true,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await _post('reset_password.php', {
        'resetToken': _resetToken!,
        'newPassword': password,
      });

      if (!mounted) return;

      _showMessage(result['message']?.toString() ?? 'Password updated.');

      Navigator.pop(context);
    } catch (e) {
      _showMessage(e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ------------------------------------------------------------
  // INPUT DECORATION
  // ------------------------------------------------------------

  InputDecoration _inputDecoration(String label, {Widget? suffixIcon}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _textGrey, fontFamily: 'Biennale'),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF7F8FA),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _primaryBlue, width: 1.4),
      ),
    );
  }

  // ------------------------------------------------------------
  // PRIMARY BUTTON
  // ------------------------------------------------------------

  Widget _buildPrimaryButton(String label, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _primaryBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.3,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Biennale',
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
      ),
    );
  }

  // ------------------------------------------------------------
  // STEP CONTENT
  // ------------------------------------------------------------

  Widget _buildStepContent() {
    // STEP 0: EMAIL ADDRESS
    if (_step == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: _inputDecoration('Registered email address'),
          ),

          const SizedBox(height: 18),

          const Text(
            'A verification code will be sent to your registered email address.',
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'Biennale',
              color: _textGrey,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 22),

          _buildPrimaryButton('Send Verification Code', _requestCode),
        ],
      );
    }

    // STEP 1: VERIFY OTP
    if (_step == 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enter the six-digit code sent to your registered email address.',
            style: TextStyle(
              fontFamily: 'Biennale',
              color: _textGrey,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 20),

          TextField(
            controller: _otpController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: _inputDecoration('6-digit verification code'),
          ),

          const SizedBox(height: 16),

          _buildPrimaryButton('Verify Code', _verifyCode),

          Center(
            child: TextButton(
              onPressed: _isLoading
                  ? null
                  : () {
                      setState(() {
                        _step = 0;
                        _otpController.clear();
                      });
                    },
              child: const Text(
                'Change email address',
                style: TextStyle(fontFamily: 'Biennale'),
              ),
            ),
          ),
        ],
      );
    }

    // STEP 2: CREATE NEW PASSWORD
    return Column(
      children: [
        TextField(
          controller: _newPasswordController,
          obscureText: _obscureNewPassword,
          decoration: _inputDecoration(
            'New password',
            suffixIcon: IconButton(
              onPressed: () {
                setState(() {
                  _obscureNewPassword = !_obscureNewPassword;
                });
              },
              icon: Icon(
                _obscureNewPassword ? Icons.visibility_off : Icons.visibility,
              ),
            ),
          ),
        ),

        const SizedBox(height: 15),

        TextField(
          controller: _confirmPasswordController,
          obscureText: _obscureConfirmPassword,
          decoration: _inputDecoration(
            'Confirm new password',
            suffixIcon: IconButton(
              onPressed: () {
                setState(() {
                  _obscureConfirmPassword = !_obscureConfirmPassword;
                });
              },
              icon: Icon(
                _obscureConfirmPassword
                    ? Icons.visibility_off
                    : Icons.visibility,
              ),
            ),
          ),
        ),

        const SizedBox(height: 10),

        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Use at least 8 characters.',
            style: TextStyle(
              fontFamily: 'Biennale',
              fontSize: 11,
              color: _textGrey,
            ),
          ),
        ),

        const SizedBox(height: 22),

        _buildPrimaryButton('Reset Password', _resetPassword),
      ],
    );
  }

  // ------------------------------------------------------------
  // BUILD
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final titles = [
      'Forgot Password?',
      'Verify Your Code',
      'Create New Password',
    ];

    final descriptions = [
      'Enter your registered email to receive a verification code.',
      'We sent a verification code to your registered email address.',
      'Your code is verified. Create a new password for your account.',
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.black,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.lock_reset_rounded,
                size: 48,
                color: _primaryBlue,
              ),

              const SizedBox(height: 22),

              Text(
                titles[_step],
                style: const TextStyle(
                  fontSize: 29,
                  fontFamily: 'Biennale',
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
              ),

              const SizedBox(height: 9),

              Text(
                descriptions[_step],
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  fontFamily: 'Biennale',
                  color: _textGrey,
                ),
              ),

              const SizedBox(height: 30),

              _buildStepContent(),
            ],
          ),
        ),
      ),
    );
  }
}
