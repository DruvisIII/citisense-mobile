import 'dart:async';
import 'package:citisense/api_config.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:citisense/app_theme.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:citisense/home.dart';
import 'package:citisense/forgot_password_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // ------------------------------------------------------------
  // API URL
  // ------------------------------------------------------------

  static const String _loginUrl =
      // 'http://10.186.51.252/citisense/api/login.php';
      '$serverBaseUrl/api/login.php';
  //'http://10.127.214.252/citisense/api/login.php';
  //'http://192.168.83.252/citisense/api/login.php';

  // If your PC's IP changes, update the URL above.

  // Diagnostic switch: set to false only temporarily to test whether
  // sending an FCM token causes login.php to stall.
  static const bool _includeFcmTokenInLogin = true;

  // ------------------------------------------------------------
  // CONTROLLERS
  // ------------------------------------------------------------

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // ------------------------------------------------------------
  // VARIABLES
  // ------------------------------------------------------------

  bool _obscurePassword = true;
  bool _isLoading = false;

  // ------------------------------------------------------------
  // DISPOSE
  // ------------------------------------------------------------

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------
  // LOGIN
  // ------------------------------------------------------------

  Future<void> _login() async {
    final String email = _emailController.text.trim();
    final String password = _passwordController.text;

    // ----------------------------------------------------------
    // CHECK EMPTY FIELDS
    // ----------------------------------------------------------

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your email and password.')),
      );
      return;
    }

    // ----------------------------------------------------------
    // CHECK EMAIL FORMAT
    // ----------------------------------------------------------

    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email address.')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // --------------------------------------------------------
      // GET FIREBASE CLOUD MESSAGING TOKEN
      // --------------------------------------------------------

      String? fcmToken;

      if (_includeFcmTokenInLogin) {
        try {
          debugPrint('[LOGIN] Retrieving FCM token...');

          fcmToken = await FirebaseMessaging.instance.getToken().timeout(
            const Duration(seconds: 5),
          );

          debugPrint(
            '[LOGIN] FCM token available: '
            '${fcmToken != null && fcmToken.isNotEmpty}',
          );
        } on TimeoutException {
          debugPrint(
            '[LOGIN] FCM token retrieval timed out; continuing login.',
          );
        } catch (e) {
          debugPrint('[LOGIN] FCM token unavailable; continuing login: $e');
        }
      }

      // --------------------------------------------------------
      // SEND LOGIN REQUEST TO PHP API
      // --------------------------------------------------------

      final Map<String, String> loginData = {
        'email': email,
        'password': password,
      };

      if (_includeFcmTokenInLogin && fcmToken != null && fcmToken.isNotEmpty) {
        loginData['fcmToken'] = fcmToken;
      }

      // Never print the password or the actual FCM token.
      final requestTimer = Stopwatch()..start();

      debugPrint('[LOGIN] Sending POST to $_loginUrl');

      debugPrint(
        '[LOGIN] Including FCM token: '
        '${loginData.containsKey('fcmToken')}',
      );

      late final http.Response response;

      try {
        response = await http
            .post(
              Uri.parse(_loginUrl),
              headers: {'Accept': 'application/json'},
              body: loginData,
            )
            .timeout(const Duration(seconds: 20));

        debugPrint(
          '[LOGIN] HTTP status: ${response.statusCode} '
          'after ${requestTimer.elapsedMilliseconds}ms',
        );
      } on TimeoutException {
        debugPrint(
          '[LOGIN] PHP HTTP POST timed out after '
          '${requestTimer.elapsedMilliseconds}ms. '
          'FCM included: ${loginData.containsKey('fcmToken')}',
        );

        throw TimeoutException(
          'The login server did not respond within 20 seconds. '
          'Check login.php and your Apache error log.',
        );
      } finally {
        requestTimer.stop();
      }

      // --------------------------------------------------------
      // CHECK HTTP STATUS
      // --------------------------------------------------------

      if (response.statusCode != 200) {
        throw Exception('Server returned status code ${response.statusCode}');
      }

      // --------------------------------------------------------
      // DECODE JSON RESPONSE
      // --------------------------------------------------------

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        throw Exception('Invalid response received from server.');
      }

      // --------------------------------------------------------
      // LOGIN FAILED
      // --------------------------------------------------------

      if (decoded['success'] != true) {
        if (!mounted) return;

        setState(() {
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              decoded['message']?.toString() ?? 'Incorrect email or password.',
            ),
          ),
        );

        return;
      }

      // --------------------------------------------------------
      // GET USER DATA
      // --------------------------------------------------------

      final dynamic userData = decoded['user'];

      if (userData == null || userData is! Map) {
        throw Exception('Invalid user data received from server.');
      }

      final String? userID = userData['userID']?.toString();
      final String? firstName = userData['firstName']?.toString();
      final String? lastName = userData['lastName']?.toString();
      final String? userEmail = userData['email']?.toString();
      final String? contactNo = userData['contactNo']?.toString();
      final String? profilePic = userData['profilePic']?.toString();
      final String? barangayID = userData['barangayID']?.toString();

      // --------------------------------------------------------
      // CHECK WHETHER BARANGAY EXISTS
      // --------------------------------------------------------

      final bool hasBarangay =
          barangayID != null && barangayID.isNotEmpty && barangayID != 'null';

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      // --------------------------------------------------------
      // LOGIN SUCCESSFUL
      // --------------------------------------------------------

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Login successful!'),
          backgroundColor: AppColors.success,
        ),
      );

      // --------------------------------------------------------
      // IF USER HAS NO BARANGAY
      // --------------------------------------------------------

      if (!hasBarangay) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Your account has no assigned barangay. Please contact the administrator.',
            ),
            backgroundColor: AppColors.warning,
          ),
        );

        return;
      }

      // --------------------------------------------------------
      // USER ALREADY HAS BARANGAY
      // GO TO HOME
      // --------------------------------------------------------

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => HomePage(
            userID: userID ?? '',
            firstName: firstName ?? '',
            lastName: lastName ?? '',
            email: userEmail ?? email,
            contactNo: contactNo ?? '',
            profilePic: profilePic,
            barangayID: barangayID ?? '',
          ),
        ),
      );
    } catch (e) {
      // --------------------------------------------------------
      // OTHER ERRORS
      // --------------------------------------------------------

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Something went wrong: ${e.toString()}'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  // ------------------------------------------------------------
  // BUILD
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,

      // --------------------------------------------------------
      // APP BAR
      // --------------------------------------------------------
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),

      // --------------------------------------------------------
      // BODY
      // --------------------------------------------------------
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),

              // ------------------------------------------------
              // TITLE
              // ------------------------------------------------
              const Text('Welcome Back!', style: AppText.pageTitle),

              const SizedBox(height: 8),

              const Text(
                'Log in to continue to CitiSense.',
                style: AppText.subtitle,
              ),

              const SizedBox(height: 32),

              // ------------------------------------------------
              // EMAIL
              // ------------------------------------------------
              const Text('Email', style: AppText.fieldLabel),

              const SizedBox(height: 8),

              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                style: const TextStyle(fontFamily: appFontFamily, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Enter your email',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),

              const SizedBox(height: 20),

              // ------------------------------------------------
              // PASSWORD
              // ------------------------------------------------
              const Text('Password', style: AppText.fieldLabel),

              const SizedBox(height: 8),

              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  if (!_isLoading) _login();
                },
                style: const TextStyle(fontFamily: appFontFamily, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Enter your password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
              ),

              // ------------------------------------------------
              // FORGOT PASSWORD
              // ------------------------------------------------
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ForgotPasswordPage(),
                      ),
                    );
                  },
                  child: const Text(
                    'Forgot Password?',
                    style: TextStyle(fontSize: 13, fontFamily: appFontFamily),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ------------------------------------------------
              // LOGIN BUTTON
              // ------------------------------------------------
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Log In'),
                ),
              ),

              const SizedBox(height: 28),

              // ------------------------------------------------
              // SIGN UP
              // ------------------------------------------------
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "Don't have an account? ",
                    style: TextStyle(
                      fontSize: 14,
                      fontFamily: appFontFamily,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                    },
                    child: const Text('Sign Up', style: AppText.link),
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
