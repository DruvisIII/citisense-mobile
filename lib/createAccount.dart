import 'dart:convert';
import 'package:citisense/api_config.dart';

import 'package:flutter/material.dart';
import 'package:citisense/friendly_errors.dart';
import 'package:citisense/validators.dart';
import 'package:citisense/app_theme.dart';
import 'package:citisense/mascot.dart';
import 'package:http/http.dart' as http;
import 'package:citisense/login.dart';
import 'package:citisense/emailVerification.dart';

class CreateAccount extends StatefulWidget {
  const CreateAccount({super.key});

  @override
  State<CreateAccount> createState() => _CreateAccountState();
}

class _CreateAccountState extends State<CreateAccount> {
  static const String _sendOtpUrl = '$apiBaseUrl/send_registration_otp.php';

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _contactController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isSendingOtp = false;

  // Turns on "required" errors for empty fields after a submit attempt.
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    // Re-check the phone and password as the user types.
    _contactController.addListener(_refresh);
    _passwordController.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  String? get _phoneError =>
      PhilippinePhone.error(_contactController.text, showEmpty: _submitted);

  String? get _passwordError =>
      PasswordRules.error(_passwordController.text, showEmpty: _submitted);

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _contactController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _createAccount() async {
    if (_isSendingOtp) return;

    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;
    final phoneDigits = _contactController.text;

    setState(() => _submitted = true);

    if (firstName.isEmpty ||
        lastName.isEmpty ||
        email.isEmpty ||
        phoneDigits.isEmpty ||
        password.isEmpty) {
      _showError('Please fill in all fields.');
      return;
    }

    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      _showError('Please enter a valid email address.');
      return;
    }

    if (!PhilippinePhone.isValid(phoneDigits)) {
      _showError('Please enter a valid mobile number: 10 digits after +63.');
      return;
    }

    if (!PasswordRules.isValid(password)) {
      _showError(_passwordError ?? FriendlyErrors.invalidInput);
      return;
    }

    final contactNumber = PhilippinePhone.toStored(phoneDigits);

    setState(() => _isSendingOtp = true);

    try {
      final response = await http
          .post(
            Uri.parse(_sendOtpUrl),
            headers: {'Accept': 'application/json'},
            body: {'firstName': firstName, 'email': email},
          )
          .timeout(const Duration(seconds: 30));

      final dynamic decoded = jsonDecode(response.body);

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
        _showError(
          FriendlyErrors.fromResponse(
            response,
            fallback:
                'We could not send the verification code. '
                'Please try again.',
          ),
        );
      }
    } catch (e) {
      debugPrint('Send registration OTP error: $e');
      _showError(FriendlyErrors.fromException(e));
    } finally {
      if (mounted) {
        setState(() => _isSendingOtp = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.danger),
    );
  }

  InputDecoration _inputDecoration(String hint, IconData icon) {
    // Borders, fill and colors come from AppTheme so every form matches.
    // Slightly slimmer fields so the whole form fits on one screen.
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, size: 20),
      prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    );
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
        const SizedBox(height: 6),
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
    // First and last name side by side on most phones; stacked on very
    // narrow ones.
    final bool namesSideBySide = MediaQuery.sizeOf(context).width >= 360 + 48;

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

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        toolbarHeight: 48,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, viewport) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              // Fill the screen so the button and "Log In" sit at the
              // bottom; still scrolls on very small screens or with the
              // keyboard open.
              constraints: BoxConstraints(minHeight: viewport.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 2),
                    const Text('Create Account', style: AppText.pageTitle),
                    const SizedBox(height: 4),
                    const Text(
                      'Create an account to start reporting community issues.',
                      style: AppText.subtitle,
                    ),
                    const SizedBox(height: 18),

                    if (namesSideBySide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: firstName),
                          const SizedBox(width: 12),
                          Expanded(child: lastName),
                        ],
                      )
                    else ...[
                      firstName,
                      const SizedBox(height: 12),
                      lastName,
                    ],
                    const SizedBox(height: 12),

                    _textField(
                      label: 'Email',
                      hint: 'Enter your email',
                      icon: Icons.email_outlined,
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 12),

                    _fieldLabel('Contact Number'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _contactController,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      inputFormatters: PhilippinePhone.inputFormatters,
                      style: const TextStyle(
                        fontFamily: appFontFamily,
                        fontSize: 14,
                      ),
                      decoration:
                          _inputDecoration(
                            '9XX XXX XXXX',
                            Icons.phone_outlined,
                          ).copyWith(
                            prefixIcon: const _CountryCodePrefix(),
                            prefixIconConstraints: const BoxConstraints(
                              minWidth: 0,
                              minHeight: 44,
                            ),
                            errorText: _phoneError,
                            errorMaxLines: 2,
                          ),
                    ),
                    const SizedBox(height: 12),

                    _fieldLabel('Password'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      autocorrect: false,
                      enableSuggestions: false,
                      style: const TextStyle(
                        fontFamily: appFontFamily,
                        fontSize: 14,
                      ),
                      decoration:
                          _inputDecoration(
                            'At least 6 characters',
                            Icons.lock_outline,
                          ).copyWith(
                            errorText: _passwordError,
                            errorMaxLines: 2,
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                size: 20,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                          ),
                    ),

                    // Extra space on tall screens goes here.
                    const Spacer(),
                    // Room for the mascot peeking above the button.
                    const SizedBox(height: 58),

                    // Button with the mascot peeking out from behind it.
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(50),
                            ),
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
                                : const Text('Create Account'),
                          ),
                        ),
                        const Positioned(
                          left: 18,
                          top: -61,
                          child: IgnorePointer(
                            child: SizedBox(
                              width: 84,
                              height: 65,
                              child: CitiMascot(pose: MascotPose.peek),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
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
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const LoginPage(),
                              ),
                            );
                          },
                          child: const Text('Log In', style: AppText.link),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fixed "+63" shown at the start of the phone field.
class _CountryCodePrefix extends StatelessWidget {
  const _CountryCodePrefix();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.phone_outlined, size: 20),
          const SizedBox(width: 8),
          const Text(
            PhilippinePhone.countryCode,
            style: TextStyle(
              fontFamily: appFontFamily,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(width: 8),
          Container(width: 1, height: 22, color: AppColors.border),
        ],
      ),
    );
  }
}
