import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:citisense/barangaySelection.dart';
import 'package:citisense/home.dart';

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
      //'http://192.168.1.48/citisense/api/login.php';
      'http://10.127.214.252/citisense/api/login.php';
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
      // SEND LOGIN REQUEST TO PHP API
      // --------------------------------------------------------

      final response = await http.post(
        Uri.parse(_loginUrl),
        headers: {'Accept': 'application/json'},
        body: {'email': email, 'password': password},
      );

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
            content: Text(decoded['message'] ?? 'Incorrect email or password.'),
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
          backgroundColor: Colors.green,
        ),
      );

      // --------------------------------------------------------
      // IF USER HAS NO BARANGAY
      // --------------------------------------------------------

      if (!hasBarangay) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => BarangaySelection(
              firstName: firstName ?? '',
              lastName: lastName ?? '',
              email: userEmail ?? email,
              contactNumber: contactNo ?? '',
              password: password,
            ),
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
    }
    // ----------------------------------------------------------
    // OTHER ERRORS
    // ----------------------------------------------------------
    catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Something went wrong: ${e.toString()}'),
          backgroundColor: Colors.red,
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
      backgroundColor: Colors.white,

      // --------------------------------------------------------
      // APP BAR
      // --------------------------------------------------------
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,

        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.black,
            size: 20,
          ),
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),

                // ------------------------------------------------
                // TITLE
                // ------------------------------------------------
                const Text(
                  'Welcome Back!',
                  style: TextStyle(
                    fontSize: 32,
                    fontFamily: 'Biennale',
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),

                const SizedBox(height: 8),

                const Text(
                  'Log in to continue to CitiSense.',
                  style: TextStyle(
                    fontSize: 14,
                    fontFamily: 'Biennale',
                    color: Colors.grey,
                  ),
                ),

                const SizedBox(height: 35),

                // ------------------------------------------------
                // EMAIL LABEL
                // ------------------------------------------------
                const Text(
                  'Email',
                  style: TextStyle(
                    fontSize: 15,
                    fontFamily: 'Biennale',
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 10),

                // ------------------------------------------------
                // EMAIL FIELD
                // ------------------------------------------------
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,

                  style: const TextStyle(fontFamily: 'Biennale', fontSize: 14),

                  decoration: InputDecoration(
                    hintText: 'Enter your email',

                    hintStyle: const TextStyle(
                      fontFamily: 'Biennale',
                      fontSize: 14,
                      color: Colors.grey,
                    ),

                    prefixIcon: const Icon(
                      Icons.email_outlined,
                      color: Colors.blueGrey,
                    ),

                    filled: true,
                    fillColor: Colors.white,

                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.blueGrey),
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

                const SizedBox(height: 20),

                // ------------------------------------------------
                // PASSWORD LABEL
                // ------------------------------------------------
                const Text(
                  'Password',
                  style: TextStyle(
                    fontSize: 15,
                    fontFamily: 'Biennale',
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 10),

                // ------------------------------------------------
                // PASSWORD FIELD
                // ------------------------------------------------
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,

                  style: const TextStyle(fontFamily: 'Biennale', fontSize: 14),

                  decoration: InputDecoration(
                    hintText: 'Enter your password',

                    hintStyle: const TextStyle(
                      fontFamily: 'Biennale',
                      fontSize: 14,
                      color: Colors.grey,
                    ),

                    prefixIcon: const Icon(
                      Icons.lock_outline,
                      color: Colors.blueGrey,
                    ),

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
                        color: Colors.blueGrey,
                      ),
                    ),

                    filled: true,
                    fillColor: Colors.white,

                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.blueGrey),
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

                const SizedBox(height: 10),

                // ------------------------------------------------
                // FORGOT PASSWORD
                // ------------------------------------------------
                Align(
                  alignment: Alignment.centerRight,

                  child: TextButton(
                    onPressed: () {
                      // Add forgot password later
                    },

                    child: const Text(
                      'Forgot Password?',
                      style: TextStyle(
                        fontSize: 13,
                        fontFamily: 'Biennale',
                        color: Color(0xFF5887E0),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 15),

                // ------------------------------------------------
                // LOGIN BUTTON
                // ------------------------------------------------
                SizedBox(
                  width: double.infinity,
                  height: 52,

                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _login,

                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5887E0),

                      disabledBackgroundColor: Colors.grey.shade300,

                      elevation: 0,

                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),

                    child: _isLoading
                        ? const SizedBox(
                            width: 23,
                            height: 23,

                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Log In',
                            style: TextStyle(
                              fontSize: 16,
                              fontFamily: 'Biennale',
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 30),

                // ------------------------------------------------
                // SIGN UP
                // ------------------------------------------------
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,

                  children: [
                    const Text(
                      "Don't have an account? ",
                      style: TextStyle(
                        fontSize: 13,
                        fontFamily: 'Biennale',
                        color: Colors.grey,
                      ),
                    ),

                    GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                      },

                      child: const Text(
                        'Sign Up',
                        style: TextStyle(
                          fontSize: 13,
                          fontFamily: 'Biennale',
                          fontWeight: FontWeight.w700,
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
