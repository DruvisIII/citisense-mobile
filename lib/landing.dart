import 'package:citisense/login.dart';
import 'package:flutter/material.dart';
import 'package:citisense/app_theme.dart';
import 'package:citisense/createAccount.dart';

class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              // Fill the screen so the buttons sit near the bottom on tall
              // phones, but still scroll on small ones.
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  children: [
                    const SizedBox(height: 64),

                    // ------------------------------------------------
                    // LOGO
                    // ------------------------------------------------
                    Container(
                      height: 168,
                      width: 168,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: AppShadows.card,
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/citisense logo image.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ------------------------------------------------
                    // APP NAME + UNDERLINE
                    // ------------------------------------------------
                    const Text(
                      'CitiSense',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                        fontFamily: appHeadingFontFamily,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 48,
                      height: 4,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: AppColors.primary,
                      ),
                    ),

                    const SizedBox(height: 40),

                    // ------------------------------------------------
                    // TAGLINE
                    // ------------------------------------------------
                    const Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: 'Making Every Report\n'),
                          TextSpan(
                            text: 'Count',
                            style: TextStyle(color: AppColors.primary),
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 30,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                        fontFamily: appHeadingFontFamily,
                      ),
                    ),

                    const SizedBox(height: 14),

                    const SizedBox(
                      width: 240,
                      child: Text(
                        'Join your community and start reporting issues',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.45,
                          color: AppColors.textSecondary,
                          fontFamily: appFontFamily,
                        ),
                      ),
                    ),

                    const Spacer(),
                    const SizedBox(height: 48),

                    // ------------------------------------------------
                    // ACTIONS
                    // ------------------------------------------------
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(56),
                            ),
                            child: const Text('Create Account'),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const CreateAccount(),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(56),
                              backgroundColor: AppColors.surface,
                            ),
                            child: const Text('Log In'),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const LoginPage(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ------------------------------------------------
                    // TERMS
                    // ------------------------------------------------
                    const Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: 'By continuing, you agree to our '),
                          TextSpan(
                            text: 'Terms & Conditions',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                        fontFamily: appFontFamily,
                      ),
                    ),

                    const SizedBox(height: 32),
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
