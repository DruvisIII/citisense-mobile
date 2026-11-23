import 'dart:async';
import 'dart:convert';

import 'package:citisense/api_config.dart';
import 'package:citisense/app_theme.dart';
import 'package:citisense/live_updates.dart';
import 'package:citisense/mascot.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class NotificationPage extends StatefulWidget {
  final String userID;
  final String barangayID;

  const NotificationPage({
    super.key,
    required this.userID,
    required this.barangayID,
  });

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage>
    with WidgetsBindingObserver {
  String selectedTab = 'all';

  bool isLoading = true;
  bool isMarkingAll = false;
  String? errorMessage;

  List<Map<String, dynamic>> notifications = [];

  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  StreamSubscription<RemoteMessage>? _openedAppSubscription;

  // Builds API URLs consistently for local and Railway servers.
  Uri _apiUri(String endpoint, {Map<String, String>? queryParameters}) {
    final baseUrl = apiBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    final cleanEndpoint = endpoint.replaceFirst(RegExp(r'^/+'), '');

    return Uri.parse(
      '$baseUrl/$cleanEndpoint',
    ).replace(queryParameters: queryParameters);
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    fetchNotifications();

    _foregroundMessageSubscription = FirebaseMessaging.onMessage.listen(
      _onFirebaseMessage,
    );

    _openedAppSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
      _onFirebaseMessage,
    );

    LiveUpdates.instance.changes.addListener(_onLiveUpdate);
  }

  void _onLiveUpdate() {
    if (mounted) {
      fetchNotifications(showLoading: false);
    }
  }

  void _onFirebaseMessage(RemoteMessage message) {
    if (!mounted) return;

    fetchNotifications(showLoading: false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      fetchNotifications(showLoading: false);
    }
  }

  @override
  void didUpdateWidget(covariant NotificationPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.userID != widget.userID ||
        oldWidget.barangayID != widget.barangayID) {
      fetchNotifications(showLoading: false);
    }
  }

  @override
  void dispose() {
    LiveUpdates.instance.changes.removeListener(_onLiveUpdate);
    _foregroundMessageSubscription?.cancel();
    _openedAppSubscription?.cancel();

    WidgetsBinding.instance.removeObserver(this);

    super.dispose();
  }

  // Retrieve report notifications and barangay announcements.
  Future<void> fetchNotifications({bool showLoading = true}) async {
    if (widget.userID.trim().isEmpty || widget.barangayID.trim().isEmpty) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
        errorMessage = 'User information is missing.';
      });

      return;
    }

    if (!mounted) return;

    setState(() {
      if (showLoading) isLoading = true;
      errorMessage = null;
    });

    try {
      final uri = _apiUri(
        'get_notifications.php',
        queryParameters: {
          'userID': widget.userID,
          'barangayID': widget.barangayID,
        },
      );

      debugPrint('[NOTIFICATIONS] Request URL: $uri');

      final response = await http.get(uri);

      if (response.statusCode != 200) {
        throw Exception(
          'Unable to load notifications. HTTP ${response.statusCode}',
        );
      }

      final result = jsonDecode(response.body);

      if (result['success'] != true) {
        throw Exception(result['message'] ?? 'Failed to load notifications.');
      }

      final List<dynamic> data = result['data'] ?? [];

      final loadedNotifications = data.map((item) {
        return Map<String, dynamic>.from(item);
      }).toList();

      // Sort newest first.
      loadedNotifications.sort((a, b) {
        final dateA =
            DateTime.tryParse(a['timestamp']?.toString() ?? '') ??
            DateTime(2000);

        final dateB =
            DateTime.tryParse(b['timestamp']?.toString() ?? '') ??
            DateTime(2000);

        return dateB.compareTo(dateA);
      });

      if (!mounted) return;

      setState(() {
        notifications = loadedNotifications;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
        errorMessage = e.toString().replaceFirst('Exception: ', '');
      });

      debugPrint('[NOTIFICATIONS] Error: $e');
    }
  }

  // Return notifications matching the selected tab.
  List<Map<String, dynamic>> get visibleNotifications {
    if (selectedTab == 'announcements') {
      return notifications
          .where((item) => item['type'] == 'announcement')
          .toList();
    }

    return notifications;
  }

  int get unreadCount {
    return visibleNotifications.where((item) => item['isRead'] != true).length;
  }

  // Format a timestamp into a relative time.
  String formatRelativeTime(String? timestamp) {
    if (timestamp == null || timestamp.isEmpty) {
      return '';
    }

    final date = DateTime.tryParse(timestamp);

    if (date == null) {
      return '';
    }

    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.isNegative || difference.inSeconds < 60) {
      return 'Just now';
    }

    if (difference.inMinutes < 60) {
      final minutes = difference.inMinutes;

      return minutes == 1 ? '1 minute ago' : '$minutes minutes ago';
    }

    if (difference.inHours < 24) {
      final hours = difference.inHours;

      return hours == 1 ? '1 hour ago' : '$hours hours ago';
    }

    final today = DateTime(now.year, now.month, now.day);
    final notificationDay = DateTime(date.year, date.month, date.day);

    final calendarDays = today.difference(notificationDay).inDays;

    if (calendarDays == 1) {
      return 'Yesterday';
    }

    if (calendarDays < 7) {
      return '$calendarDays days ago';
    }

    if (calendarDays < 30) {
      final weeks = calendarDays ~/ 7;

      return weeks == 1 ? '1 week ago' : '$weeks weeks ago';
    }

    if (calendarDays < 365) {
      final months = calendarDays ~/ 30;

      return months == 1 ? '1 month ago' : '$months months ago';
    }

    final years = calendarDays ~/ 365;

    return years == 1 ? '1 year ago' : '$years years ago';
  }

  // Mark one notification as read.
  Future<void> markAsRead(Map<String, dynamic> notification) async {
    if (notification['isRead'] == true) return;

    final id = notification['id']?.toString() ?? '';
    final type = notification['type']?.toString() ?? '';

    try {
      final uri = _apiUri('mark_notification_read.php');

      debugPrint('[NOTIFICATIONS] Mark as read URL: $uri');

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'userID': widget.userID, 'type': type, 'id': id}),
      );

      final result = jsonDecode(response.body);

      if (response.statusCode != 200 || result['success'] != true) {
        throw Exception(result['message'] ?? 'Failed to mark as read.');
      }

      if (!mounted) return;

      setState(() {
        final index = notifications.indexWhere(
          (item) => item['id'].toString() == id && item['type'] == type,
        );

        if (index != -1) {
          notifications[index]['isRead'] = true;
        }
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update notification: $e')),
      );
    }
  }

  // Mark all notifications in the current tab as read.
  Future<void> markAllAsRead() async {
    if (unreadCount == 0 || isMarkingAll) return;

    setState(() {
      isMarkingAll = true;
    });

    try {
      final uri = _apiUri('mark_all_notifications_read.php');

      debugPrint('[NOTIFICATIONS] Mark all as read URL: $uri');

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'userID': widget.userID, 'scope': selectedTab}),
      );

      final result = jsonDecode(response.body);

      if (response.statusCode != 200 || result['success'] != true) {
        throw Exception(result['message'] ?? 'Failed to mark all as read.');
      }

      if (!mounted) return;

      setState(() {
        for (final item in visibleNotifications) {
          item['isRead'] = true;
        }

        isMarkingAll = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notifications marked as read.')),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isMarkingAll = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not mark notifications as read: $e')),
      );
    }
  }

  // NOTIFICATIONS SCREEN
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildTabsPanel(),
            Expanded(child: _buildNotificationList()),
          ],
        ),
      ),
    );
  }

  // Shared header geometry for Notifications and Settings.
  Widget _buildHeader() {
    return SizedBox(
      width: double.infinity,
      height: 222,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            Positioned(
              left: 22,
              right: 22,
              top: 38,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Notifications',
                    maxLines: 1,
                    softWrap: false,
                    style: const TextStyle(
                      fontFamily: appFontFamily,
                      fontSize: 37,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 22,
              top: 109,
              width: (constraints.maxWidth - 44) * 0.55,
              child: Text(
                'Stay updated with your reports and announcements.',
                style: const TextStyle(
                  fontFamily: appFontFamily,
                  fontSize: 16,
                  height: 1.5,
                  color: textGrey,
                ),
              ),
            ),
            Positioned(
              right: 18,
              top: 84,
              bottom: 6,
              width: (constraints.maxWidth - 44) * 0.40,
              child: const CitiMascot(
                pose: MascotPose.notification,
                backdrop: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabsPanel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              boxShadow: AppShadows.soft,
            ),
            child: Row(
              children: [
                _buildTab(label: 'All', value: 'all'),
                _buildTab(label: 'Announcements', value: 'announcements'),
              ],
            ),
          ),
          SizedBox(
            height: 40,
            child: (unreadCount > 0 || isMarkingAll)
                ? Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: isMarkingAll ? null : markAllAsRead,
                      icon: isMarkingAll
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.done_all, size: 16),
                      label: Text('Mark all as read ($unreadCount)'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        textStyle: const TextStyle(
                          fontFamily: appFontFamily,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildTab({required String label, required String value}) {
    final selected = selectedTab == value;

    return Expanded(
      child: InkWell(
        onTap: () => setState(() => selectedTab = value),
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 2),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            label,
            maxLines: 1,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: appFontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : textGrey,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationList() {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator(color: primaryBlue));
    }

    if (errorMessage != null) {
      return RefreshIndicator(
        onRefresh: fetchNotifications,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 80),
            const Icon(Icons.cloud_off_outlined, color: textGrey, size: 48),
            const SizedBox(height: 14),
            Text(errorMessage!, textAlign: TextAlign.center),
            Center(
              child: TextButton(
                onPressed: fetchNotifications,
                child: const Text('Try Again'),
              ),
            ),
          ],
        ),
      );
    }

    final items = visibleNotifications;

    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: fetchNotifications,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 80),
            Icon(
              selectedTab == 'announcements'
                  ? Icons.campaign_outlined
                  : Icons.notifications_none_rounded,
              color: primaryBlue,
              size: 55,
            ),
            const SizedBox(height: 14),
            Text(
              selectedTab == 'announcements'
                  ? 'No announcements yet'
                  : 'No notifications yet',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: appFontFamily,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: darkBlue,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'You are all caught up!',
              textAlign: TextAlign.center,
              style: TextStyle(color: textGrey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: primaryBlue,
      onRefresh: fetchNotifications,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        itemCount: items.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          return _buildNotificationCard(items[index]);
        },
      ),
    );
  }

  Widget _buildNotificationCard(Map<String, dynamic> item) {
    final isAnnouncement = item['type'] == 'announcement';
    final isRead = item['isRead'] == true;
    final title = item['title']?.toString() ?? 'Notification';
    final message = item['message']?.toString() ?? '';
    final timestamp = formatRelativeTime(item['timestamp']?.toString());

    // The server sends the status this update is about ("In Progress",
    // "Resolved", ...). Older servers didn't, so fall back to the text.
    final String status =
        (item['status']?.toString().trim().isNotEmpty ?? false)
        ? item['status'].toString().trim()
        : _statusFromText('$title $message');
    final lower = status.toLowerCase();

    final resolved = lower.contains('resolved') || lower.contains('complete');
    final inProgress = lower.contains('progress') || lower.contains('review');
    final problem =
        lower.contains('reject') ||
        lower.contains('overdue') ||
        lower.contains('not accepted');
    final isMessage = lower.contains('message');

    final Color accent = isAnnouncement
        ? AppColors.warning
        : resolved
        ? AppColors.success
        : inProgress
        ? AppColors.primary
        : problem
        ? AppColors.danger
        : isMessage
        ? AppColors.accent
        : AppColors.warning;

    final Color iconBackground = isAnnouncement
        ? AppColors.warningSoft
        : resolved
        ? AppColors.successSoft
        : inProgress
        ? AppColors.primarySoft
        : problem
        ? AppColors.dangerSoft
        : isMessage
        ? AppColors.accentSoft
        : AppColors.warningSoft;

    final IconData leadingIcon = isAnnouncement
        ? Icons.notifications_active_rounded
        : resolved
        ? Icons.check_circle_rounded
        : inProgress
        ? Icons.assignment_turned_in_outlined
        : problem
        ? Icons.error_outline_rounded
        : isMessage
        ? Icons.forum_rounded
        : Icons.chat_bubble_rounded;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadows.card,
        border: Border.all(
          color: isRead ? Colors.transparent : AppColors.primaryBorder,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: () => markAsRead(item),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: iconBackground,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(leadingIcon, color: accent, size: 28),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                color: AppColors.ink,
                                fontFamily: appFontFamily,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            timestamp,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontFamily: appFontFamily,
                              fontSize: 12,
                            ),
                          ),
                          if (!isRead) ...[
                            const SizedBox(width: 7),
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(top: 4),
                              decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        message,
                        style: const TextStyle(
                          color: textGrey,
                          fontSize: 13,
                          height: 1.5,
                          fontFamily: appFontFamily,
                        ),
                      ),
                      if (!isAnnouncement) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: iconBackground,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            status,
                            style: TextStyle(
                              color: accent,
                              fontSize: 11,
                              fontFamily: appFontFamily,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Best guess at the status from the notification text.
  String _statusFromText(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('not accepted') || lower.contains('reject')) {
      return 'Rejected';
    }
    if (lower.contains('overdue')) return 'Overdue';
    if (lower.contains('resolved') || lower.contains('complete')) {
      return 'Resolved';
    }
    if (lower.contains('in progress')) return 'In Progress';
    if (lower.contains('replied') || lower.contains('new message')) {
      return 'New Message';
    }
    return 'Pending';
  }
}
