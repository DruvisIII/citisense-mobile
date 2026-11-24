import 'dart:async';
import 'dart:convert';

import 'package:citisense/api_client.dart';
import 'package:citisense/api_config.dart';
import 'package:citisense/auth_session.dart';
import 'package:citisense/notification_router.dart';
import 'package:citisense/friendly_errors.dart';
import 'package:citisense/app_theme.dart';
import 'package:citisense/ui_components.dart';
import 'package:citisense/live_updates.dart';
import 'package:citisense/mascot.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class NotificationPage extends StatefulWidget {
  final String userID;
  final String barangayID;

  /// Shown in the page header, like on Home.
  final String barangayName;

  const NotificationPage({
    super.key,
    required this.userID,
    required this.barangayID,
    this.barangayName = '',
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

  // Redraws "5 minutes ago" labels as time passes.
  Timer? _clockTick;
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
    _clockTick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });

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
    _clockTick?.cancel();
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

      final response = await http
          .get(uri, headers: AuthSession.headers())
          .timeout(const Duration(seconds: 30));

      Map<String, dynamic>? result;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) result = decoded;
      } on FormatException {
        result = null;
      }

      if (response.statusCode != 200 || result?['success'] != true) {
        throw Exception(FriendlyErrors.fromResponse(response));
      }

      // Ages are measured on the server's clock (see ServerClock).
      ServerClock.syncFromBody(result);

      final List<dynamic> data = result!['data'] is List
          ? result['data'] as List
          : const [];

      final loadedNotifications = data
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

      // Newest first (the server already sorts; this keeps it stable).
      loadedNotifications.sort((a, b) {
        final dateA = parseApiTime(a['timestamp']) ?? DateTime(2000);
        final dateB = parseApiTime(b['timestamp']) ?? DateTime(2000);
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
        errorMessage = FriendlyErrors.fromException(e);
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

  // "Just now", "5 minutes ago", "Yesterday", ... in the phone's time zone.
  String formatRelativeTime(String? timestamp) =>
      relativeTime(parseApiTime(timestamp));

  // Open what the notification is about, and mark it as read.
  //   status update        -> that report's details (e.g. REP055)
  //   message about report -> Messages, with that report selected
  //   general message      -> Messages
  //   announcement         -> that announcement's details
  void _onNotificationTap(Map<String, dynamic> item) {
    markAsRead(item);

    final target = NotificationTarget.fromNotificationItem(item);
    if (target != null) {
      NotificationRouter.attach(
        userID: widget.userID,
        barangayID: widget.barangayID,
      );
      NotificationRouter.open(target);
    }
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
        headers: AuthSession.headers(
          extra: {'Content-Type': 'application/json'},
        ),
        body: jsonEncode({'userID': widget.userID, 'type': type, 'id': id}),
      );

      final result = jsonDecode(response.body);

      if (response.statusCode != 200 || result['success'] != true) {
        throw Exception(FriendlyErrors.fromResponse(response));
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

      debugPrint('[NOTIFICATIONS] Mark as read failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(FriendlyErrors.fromException(e)),
          backgroundColor: AppColors.danger,
        ),
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
        headers: AuthSession.headers(
          extra: {'Content-Type': 'application/json'},
        ),
        body: jsonEncode({'userID': widget.userID, 'scope': selectedTab}),
      );

      final result = jsonDecode(response.body);

      if (response.statusCode != 200 || result['success'] != true) {
        throw Exception(FriendlyErrors.fromResponse(response));
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

      debugPrint('[NOTIFICATIONS] Mark all failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(FriendlyErrors.fromException(e)),
          backgroundColor: AppColors.danger,
        ),
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
            // The list fades into the newly chosen tab.
            Expanded(
              child: AnimatedSwitcher(
                duration: AppMotion.toggle,
                switchInCurve: AppMotion.curve,
                switchOutCurve: Curves.easeInCubic,
                child: KeyedSubtree(
                  key: ValueKey<String>(selectedTab),
                  child: _buildNotificationList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Same header as Home: same slots, sizes and spacing on every page.
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: CitiPageHeader(
        barangayName: widget.barangayName,
        title: 'Notifications',
        description: 'Stay updated with your reports and announcements.',
        mascot: const CitiMascot(pose: MascotPose.notification, backdrop: true),
      ),
    );
  }

  Widget _buildTabsPanel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: Column(
        children: [
          SlidingToggle(
            labels: const ['All', 'Announcements'],
            selectedIndex: selectedTab == 'all' ? 0 : 1,
            onChanged: (index) => setState(
              () => selectedTab = index == 0 ? 'all' : 'announcements',
            ),
            boxShadow: AppShadows.soft,
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
                          fontFamily: appHeadingFontFamily,
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
                fontFamily: appHeadingFontFamily,
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
          onTap: () => _onNotificationTap(item),
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
                                fontFamily: appHeadingFontFamily,
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
                              fontFamily: appHeadingFontFamily,
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
