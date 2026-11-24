import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:citisense/api_config.dart';
import 'package:citisense/app_theme.dart';
import 'package:citisense/auth_session.dart';
import 'package:citisense/friendly_errors.dart';
import 'package:citisense/validators.dart';

// ============================================================
// CHANGE PASSWORD (Settings > Account)
// ============================================================

class ChangePasswordPage extends StatefulWidget {
  final String userID;

  const ChangePasswordPage({super.key, required this.userID});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _submitted = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final controller in [
      _currentController,
      _newController,
      _confirmController,
    ]) {
      controller.addListener(_refresh);
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  String? get _currentError => _submitted && _currentController.text.isEmpty
      ? 'Enter your current password.'
      : null;

  String? get _newError {
    final error = PasswordRules.error(
      _newController.text,
      showEmpty: _submitted,
    );
    if (error != null) return error;
    if (_newController.text.isNotEmpty &&
        _newController.text == _currentController.text) {
      return 'Choose a password different from your current one.';
    }
    return null;
  }

  String? get _confirmError {
    final confirm = _confirmController.text;
    if (confirm.isEmpty) {
      return _submitted ? 'Re-enter your new password.' : null;
    }
    return confirm == _newController.text
        ? null
        : 'The passwords do not match.';
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.danger : AppColors.success,
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _submitted = true);

    if (_currentError != null || _newError != null || _confirmError != null) {
      _showMessage(FriendlyErrors.invalidInput, error: true);
      return;
    }

    setState(() => _saving = true);

    try {
      final response = await http
          .post(
            Uri.parse('$apiBaseUrl/change_password.php'),
            headers: AuthSession.headers(),
            body: {
              'userID': widget.userID,
              'currentPassword': _currentController.text,
              'newPassword': _newController.text,
            },
          )
          .timeout(const Duration(seconds: 30));

      Map<String, dynamic>? decoded;
      try {
        final body = jsonDecode(response.body);
        if (body is Map<String, dynamic>) decoded = body;
      } on FormatException {
        decoded = null;
      }

      if (response.statusCode == 200 && decoded?['success'] == true) {
        if (!mounted) return;
        _showMessage('Your password has been changed.');
        Navigator.pop(context);
        return;
      }

      _showMessage(FriendlyErrors.fromResponse(response), error: true);
    } catch (e) {
      debugPrint('Change password error: $e');
      _showMessage(FriendlyErrors.fromException(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _passwordField({
    required String label,
    required TextEditingController controller,
    required bool obscure,
    required VoidCallback onToggle,
    required String? errorText,
    TextInputAction action = TextInputAction.next,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.fieldLabel),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscure,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: action,
          onSubmitted: action == TextInputAction.done ? (_) => _save() : null,
          style: const TextStyle(fontFamily: appFontFamily, fontSize: 14),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.lock_outline, size: 20),
            errorText: errorText,
            errorMaxLines: 2,
            suffixIcon: IconButton(
              tooltip: obscure ? 'Show password' : 'Hide password',
              icon: Icon(
                obscure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 20,
              ),
              onPressed: onToggle,
            ),
          ),
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
        title: const Text(
          'Change Password',
          style: TextStyle(
            fontFamily: appFontFamily,
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: AppColors.ink,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            const Text(
              'Enter your current password, then choose a new one. '
              'Use at least 6 characters: letters, numbers and keyboard '
              'symbols.',
              style: AppText.subtitle,
            ),
            const SizedBox(height: 22),
            _passwordField(
              label: 'Current Password',
              controller: _currentController,
              obscure: _obscureCurrent,
              onToggle: () =>
                  setState(() => _obscureCurrent = !_obscureCurrent),
              errorText: _currentError,
            ),
            const SizedBox(height: 16),
            _passwordField(
              label: 'New Password',
              controller: _newController,
              obscure: _obscureNew,
              onToggle: () => setState(() => _obscureNew = !_obscureNew),
              errorText: _newError,
            ),
            const SizedBox(height: 16),
            _passwordField(
              label: 'Confirm New Password',
              controller: _confirmController,
              obscure: _obscureConfirm,
              onToggle: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
              errorText: _confirmError,
              action: TextInputAction.done,
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Save New Password'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
