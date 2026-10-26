// import 'dart:math';

import 'package:citisense/login.dart';
import 'package:flutter/material.dart';
import 'package:citisense/createAccount.dart';

class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // appBar: AppBar(
      //   backgroundColor: Color(0xFFF5F5F5),
      //   title: const Text('CitiSense'),
      // ),
      body: SingleChildScrollView(
        child: SizedBox(
          width: double.infinity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              SizedBox(height: 130),
              Container(
                height: 180,
                width: 180,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(300),
                  // color: Colors.blueAccent,
                ),
                child: ClipOval(
                  child: Image.asset(
                    'assets/citisense logo image.png',
                    // color: Colors.redAccent,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: const Text(
                      'CitiSense',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF5887E0),
                        fontFamily: 'Biennale',
                      ),
                    ),
                  ),

                  Container(
                    width: 50, // ← underline length
                    height: 4, // ← underline thickness
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: const Color(0xFF5887E0),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 40), //child: Container(color: Colors.amber)),
              Container(
                // color: Colors.red,
                width: 279,
                child: const Text(
                  'Making Every Report',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A),
                    fontFamily: 'Biennale',
                  ),
                ),
              ),
              const Text(
                'Count',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF5887E0),
                  fontFamily: 'Biennale',
                ),
              ),
              Container(
                width: 200,
                margin: const EdgeInsets.only(top: 15),
                // color: Colors.grey[200],
                child: const Text(
                  'Join your community and start reporting issues',
                  softWrap: true,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Color(0xFF1A1A1A),
                    fontFamily: 'Biennale',
                  ),
                ),
              ),
              SizedBox(height: 130),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5887E0),
                  minimumSize: const Size(286, 60),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'Create Account',
                  style: TextStyle(color: Colors.white),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CreateAccount(),
                    ),
                  );
                },
              ),
              // Container(
              //   width: 279,
              //   height: 60,
              //   margin: EdgeInsets.only(top: 10),
              //   decoration: BoxDecoration(
              //     borderRadius: BorderRadius.circular(10),
              //     border: Border.all(color: Color(0xFF5887E0), width: 2),
              //   ),
              //   alignment: Alignment.center,
              //   child: const Text(
              //     'Log In',
              //     style: TextStyle(
              //       fontSize: 16,
              //       color: Color(0xFF5887E0),
              //       fontFamily: 'Biennale',
              //     ),
              //   ),
              // ),
              SizedBox(height: 10),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFFFFF),
                  minimumSize: const Size(286, 60),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: Color(0xFF5887E0), width: 2),
                  ),
                ),
                child: const Text(
                  'Log In',
                  style: TextStyle(color: Color(0xFF5887E0)),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const LoginPage()),
                  );
                },
              ),
              Container(
                // color: Colors.amber,
                margin: EdgeInsets.only(top: 20),
                // width: 230,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'By continuing, you agree to our',
                      style: TextStyle(
                        color: Color(0xFFB3BAC5),
                        fontFamily: 'Biennale',
                      ),
                    ),
                    const Text(
                      'Terms & Conditions',
                      style: TextStyle(
                        color: Color(0xFF5887E0),
                        fontFamily: 'Biennale',
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 50),
            ],
          ),
        ),
      ),
    );
  }
}
