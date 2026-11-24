import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:citisense/announcement_details_page.dart';
import 'package:citisense/api_config.dart';
import 'package:citisense/app_theme.dart';
import 'package:citisense/barangay_messages_page.dart';
import 'package:citisense/my_reports.dart';
import 'package:citisense/session_manager.dart';

// ============================================================
// OPEN WHAT A NOTIFICATION IS ABOUT
// ------------------------------------------------------------
// Used by the Notifications page and by push notifications (app
// open, in the background, or closed).
//
//   report status update   -> Report Details of that report
//   message about a report -> Messages, with that report selected
//   general message        -> Messages
//   announcement           -> Announcement details
//
// A push that opens the app before Home is ready is kept and
// opened as soon as Home calls attach().
// ============================================================

enum NotificationTargetType { report, reportMessage, message, announcement }

class NotificationTarget {
  const NotificationTarget(this.type, {this.id = ''});

  final NotificationTargetType type;

  /// reportID for reports, announceID for announcements.
  final String id;

  /// From an FCM data payload (push_dispatch.php, update_report_status.php,
  /// admin_reply_report_message.php).
  static NotificationTarget? fromPushData(Map<String, dynamic> data) {
    final type = data['type']?.toString() ?? '';
    final reportID = data['reportID']?.toString().trim() ?? '';
    final announceID = data['announceID']?.toString().trim() ?? '';

    switch (type) {
      case 'announcement':
        return announceID.isEmpty
            ? null
            : NotificationTarget(
                NotificationTargetType.announcement,
                id: announceID,
              );
      case 'report_message':
        return reportID.isEmpty
            ? const NotificationTarget(NotificationTargetType.message)
            : NotificationTarget(
                NotificationTargetType.reportMessage,
                id: reportID,
              );
      case 'message':
        return const NotificationTarget(NotificationTargetType.message);
      case 'report_status':
      case 'report':
        return reportID.isEmpty
            ? null
            : NotificationTarget(NotificationTargetType.report, id: reportID);
    }
    return null;
  }

  /// From an item of get_notifications.php.
  static NotificationTarget? fromNotificationItem(Map<String, dynamic> item) {
    final kind = item['kind']?.toString() ?? '';
    final type = item['type']?.toString() ?? '';
    final reportID = item['reportID']?.toString().trim() ?? '';
    final id = item['id']?.toString().trim() ?? '';

    if (type == 'announcement' || kind == 'announcement') {
      return id.isEmpty
          ? null
          : NotificationTarget(NotificationTargetType.announcement, id: id);
    }
    if (kind == 'message') {
      return const NotificationTarget(NotificationTargetType.message);
    }
    if (kind == 'report_message') {
      return reportID.isEmpty
          ? const NotificationTarget(NotificationTargetType.message)
          : NotificationTarget(
              NotificationTargetType.reportMessage,
              id: reportID,
            );
    }
    return reportID.isEmpty
        ? null
        : NotificationTarget(NotificationTargetType.report, id: reportID);
  }
}

class NotificationRouter {
  NotificationRouter._();

  static String? _userID;
  static String? _barangayID;
  static NotificationTarget? _pending;

  /// Home is ready for this account: open a waiting notification, if any.
  static void attach({required String userID, required String barangayID}) {
    _userID = userID;
    _barangayID = barangayID;

    final pending = _pending;
    _pending = null;
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => open(pending));
    }
  }

  /// Logged out: forget the account (and any waiting notification).
  static void detach() {
    _userID = null;
    _barangayID = null;
    _pending = null;
  }

  /// Tapped push notification (FCM data or local notification payload).
  static void openPushData(Map<String, dynamic> data) {
    final target = NotificationTarget.fromPushData(data);
    if (target == null) return;

    if (_userID == null || appNavigatorKey.currentState == null) {
      // Home is not open yet (app was closed or is starting up).
      _pending = target;
      return;
    }
    open(target);
  }

  /// Local notification payload (JSON of the FCM data).
  static void openPayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        openPushData(Map<String, dynamic>.from(decoded));
      }
    } catch (e) {
      debugPrint('[NOTIFICATION] Unreadable payload: $e');
    }
  }

  static void open(NotificationTarget target) {
    final navigator = appNavigatorKey.currentState;
    final userID = _userID;
    if (navigator == null || userID == null) {
      _pending = target;
      return;
    }

    switch (target.type) {
      case NotificationTargetType.message:
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => BarangayMessagesPage(userID: userID),
          ),
        );
      case NotificationTargetType.reportMessage:
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => BarangayMessagesPage(
              userID: userID,
              initialReportID: target.id,
            ),
          ),
        );
      case NotificationTargetType.report:
      case NotificationTargetType.announcement:
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => _OpenTargetPage(
              target: target,
              userID: userID,
              barangayID: _barangayID ?? '',
            ),
          ),
        );
    }
  }
}

// ============================================================
// Loads the report / announcement, then shows its details page
// in place of this one (Back returns to where the user was).
// ============================================================

class _OpenTargetPage extends StatefulWidget {
  const _OpenTargetPage({
    required this.target,
    required this.userID,
    required this.barangayID,
  });

  final NotificationTarget target;
  final String userID;
  final String barangayID;

  @override
  State<_OpenTargetPage> createState() => _OpenTargetPageState();
}

class _OpenTargetPageState extends State<_OpenTargetPage> {
  String? _error;

  bool get _isReport => widget.target.type == NotificationTargetType.report;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);

    try {
      final Map<String, dynamic>? item = _isReport
          ? await _findReport()
          : await _findAnnouncement();

      if (!mounted) return;

      if (item == null) {
        setState(
          () => _error = _isReport
              ? 'This report is no longer available.'
              : 'This announcement is no longer available.',
        );
        return;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => _isReport
              ? ReportDetailsPage(report: item, userID: widget.userID)
              : AnnouncementDetailsPage(
                  announcement: item,
                  userID: widget.userID,
                ),
        ),
      );
    } catch (e) {
      debugPrint('[NOTIFICATION] Could not open ${widget.target.id}: $e');
      if (mounted) {
        setState(
          () => _error = 'We could not open this right now. Please try again.',
        );
      }
    }
  }

  Future<List<dynamic>> _getList(Uri uri) async {
    final response = await http
        .get(uri, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['success'] != true) {
      throw Exception('Unexpected response');
    }
    final data = decoded['data'];
    return data is List ? data : const [];
  }

  Future<Map<String, dynamic>?> _findReport() async {
    final list = await _getList(
      Uri.parse(
        '$apiBaseUrl/get_my_reports.php',
      ).replace(queryParameters: {'userID': widget.userID}),
    );
    for (final item in list) {
      if (item is Map && item['reportID']?.toString() == widget.target.id) {
        return Map<String, dynamic>.from(item);
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> _findAnnouncement() async {
    if (widget.barangayID.isEmpty) return null;
    final list = await _getList(
      Uri.parse(
        '$apiBaseUrl/get_announcements.php',
      ).replace(queryParameters: {'barangayID': widget.barangayID}),
    );
    for (final item in list) {
      if (item is Map && item['announceID']?.toString() == widget.target.id) {
        return Map<String, dynamic>.from(item);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_isReport ? 'Report Details' : 'Announcement'),
      ),
      body: Center(
        child: _error == null
            ? const CircularProgressIndicator(color: AppColors.primary)
            : Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 46,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: appFontFamily,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    TextButton(
                      onPressed: _load,
                      child: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
