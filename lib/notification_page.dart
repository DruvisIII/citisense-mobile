import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const Color primaryBlue = Color(0xFF5887E0);
const Color darkBlue = Color(0xFF172D68);
const Color textGrey = Color(0xFF596887);

const String apiBaseUrl =
    //'http://192.168.1.48/citisense/api/';
    'http://10.127.214.252/citisense/api/';

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

class _NotificationPageState extends State<NotificationPage> {
  String selectedTab = 'all';

  bool isLoading = true;
  bool isMarkingAll = false;
  String? errorMessage;

  List<Map<String, dynamic>> notifications = [];

  @override
  void initState() {
    super.initState();
    fetchNotifications();
  }

  // Retrieve report notifications and barangay announcements.
  Future<void> fetchNotifications() async {
    if (widget.userID.trim().isEmpty || widget.barangayID.trim().isEmpty) {
      setState(() {
        isLoading = false;
        errorMessage = 'User information is missing.';
      });
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final uri = Uri.parse('${apiBaseUrl}get_notifications.php').replace(
        queryParameters: {
          'userID': widget.userID,
          'barangayID': widget.barangayID,
        },
      );

      final response = await http.get(uri);

      if (response.statusCode != 200) {
        throw Exception(
          'Unable to load notifications. '
          'HTTP ${response.statusCode}',
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
      final response = await http.post(
        Uri.parse('${apiBaseUrl}mark_notification_read.php'),
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
      final response = await http.post(
        Uri.parse('${apiBaseUrl}mark_all_notifications_read.php'),
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

  // ============================================================
  // NOTIFICATIONS SCREEN — VISUAL REDESIGN
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
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
  // Keep these measurements identical in both pages.
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
                      fontFamily: 'Biennale',
                      fontSize: 37,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                      color: Color(0xFF0E235B),
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
                  fontFamily: 'Biennale',
                  fontSize: 16,
                  height: 1.5,
                  color: textGrey,
                ),
              ),
            ),
            // Replace this placeholder with your mascot Image.asset later.
            Positioned(
              right: 18,
              top: 91,
              bottom: 10,
              width: (constraints.maxWidth - 44) * 0.40,
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF3FF),
                  border: Border.all(color: const Color(0xFFCFE1FF)),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Text(
                  'Mascot\nplaceholder',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Biennale',
                    fontSize: 13,
                    color: textGrey,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabsPanel() {
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 0, 18, 9),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(23),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF253F7A).withOpacity(0.07),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _buildTab(label: 'All', value: 'all'),
              const SizedBox(width: 5),
              _buildTab(label: 'Announcements', value: 'announcements'),
            ],
          ),
          // Keep existing mark-all-as-read functionality without crowding tabs.
          if (unreadCount > 0 || isMarkingAll)
            Align(
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
                  foregroundColor: const Color(0xFF1762EE),
                  textStyle: const TextStyle(fontSize: 11),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            )
          else
            const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _buildTab({required String label, required String value}) {
    final selected = selectedTab == value;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => selectedTab = value),
        borderRadius: BorderRadius.circular(30),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 3),
          decoration: BoxDecoration(
            gradient: selected
                ? const LinearGradient(
                    colors: [Color(0xFF2B7AFF), Color(0xFF0554EC)],
                  )
                : null,
            color: selected ? null : Colors.white,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: selected ? Colors.transparent : const Color(0xFFBDD2FF),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Biennale',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : const Color(0xFF1462F3),
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
                fontFamily: 'Biennale',
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
        padding: const EdgeInsets.fromLTRB(18, 5, 18, 24),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 11),
        itemBuilder: (context, index) => _buildNotificationCard(items[index]),
      ),
    );
  }

  Widget _buildNotificationCard(Map<String, dynamic> item) {
    final isAnnouncement = item['type'] == 'announcement';
    final isRead = item['isRead'] == true;
    final title = item['title']?.toString() ?? 'Notification';
    final message = item['message']?.toString() ?? '';
    final timestamp = formatRelativeTime(item['timestamp']?.toString());
    final lower = title.toLowerCase();
    final resolved = lower.contains('resolved') || lower.contains('complete');
    final inProgress = lower.contains('progress') || lower.contains('review');
    final Color accent = isAnnouncement
        ? const Color(0xFFFFBD36)
        : resolved
        ? const Color(0xFF11B86A)
        : const Color(0xFF1768F7);
    final Color iconBackground = isAnnouncement
        ? const Color(0xFFFFF4DE)
        : resolved
        ? const Color(0xFFE0F7EA)
        : const Color(0xFFE8EFFF);
    final IconData leadingIcon = isAnnouncement
        ? Icons.notifications_active_rounded
        : resolved
        ? Icons.check_circle_rounded
        : inProgress
        ? Icons.assignment_turned_in_outlined
        : Icons.chat_bubble_rounded;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => markAsRead(item),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 17),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF294C8C).withOpacity(0.07),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: iconBackground,
                  shape: BoxShape.circle,
                ),
                child: Icon(leadingIcon, color: accent, size: 31),
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
                              color: Color(0xFF10195B),
                              fontFamily: 'Biennale',
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          timestamp,
                          style: const TextStyle(
                            color: textGrey,
                            fontFamily: 'Biennale',
                            fontSize: 11,
                          ),
                        ),
                        if (!isRead) ...[
                          const SizedBox(width: 7),
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(top: 4),
                            decoration: const BoxDecoration(
                              color: Color(0xFF0863FF),
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
                        fontFamily: 'Biennale',
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
                          resolved
                              ? 'Resolved'
                              : inProgress
                              ? 'In Progress'
                              : 'Pending',
                          style: TextStyle(
                            color: accent,
                            fontSize: 11,
                            fontFamily: 'Biennale',
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
    );
  }
}
