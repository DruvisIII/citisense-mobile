import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:citisense/api_client.dart';
import 'package:citisense/api_config.dart';
import 'package:citisense/app_theme.dart';
import 'package:citisense/live_updates.dart';

// ============================================================
// MESSAGES WITH YOUR BARANGAY
// ------------------------------------------------------------
// One conversation with the barangay (api/resident_messages.php),
// the same one the admin website's Messages page shows:
//   - choose one of your reports to ask about it (the message is
//     tagged with the report, so the barangay knows which one), or
//     send a general message;
//   - reply to a specific message (a quote of it is shown);
//   - delete messages you sent (never the barangay's).
// New replies appear automatically: every 10 seconds while this
// screen is open, and right away when a push notification arrives.
// ============================================================

class BarangayMessageReply {
  const BarangayMessageReply({
    required this.key,
    required this.name,
    required this.text,
    required this.missing,
  });

  final String key;
  final String name;
  final String text;

  /// The original message was deleted.
  final bool missing;

  static BarangayMessageReply? fromJson(dynamic json) {
    if (json is! Map) return null;
    return BarangayMessageReply(
      key: json['key']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
      missing: json['missing'] == true,
    );
  }
}

class BarangayMessage {
  const BarangayMessage({
    required this.key,
    required this.fromBarangay,
    required this.canDelete,
    required this.name,
    required this.message,
    required this.reportID,
    required this.reportLabel,
    required this.replyTo,
    required this.createdAt,
  });

  /// "d5" (general message) or "r12" (message about a report).
  final String key;
  final bool fromBarangay;
  final bool canDelete;
  final String name;
  final String message;
  final String reportID;
  final String reportLabel;
  final BarangayMessageReply? replyTo;
  final DateTime? createdAt;

  factory BarangayMessage.fromJson(Map<String, dynamic> json) =>
      BarangayMessage(
        key: json['key']?.toString() ?? '',
        fromBarangay: json['fromBarangay'] == true,
        canDelete: json['canDelete'] == true,
        name: json['name']?.toString() ?? '',
        message: json['message']?.toString() ?? '',
        reportID: json['reportID']?.toString() ?? '',
        reportLabel: json['reportLabel']?.toString() ?? '',
        replyTo: BarangayMessageReply.fromJson(json['replyTo']),
        createdAt: parseApiTime(json['createdAt']),
      );
}

/// One of the resident's reports, for "Ask about a report".
class MessageReportOption {
  const MessageReportOption({
    required this.reportID,
    required this.categoryName,
    required this.statusName,
    required this.imagePath,
    required this.dateReported,
  });

  final String reportID;
  final String categoryName;
  final String statusName;
  final String imagePath;
  final DateTime? dateReported;

  String get label =>
      categoryName.isEmpty ? reportID : '$reportID · $categoryName';

  String? get imageUrl {
    final path = imagePath.trim();
    if (path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return path.startsWith('/')
        ? '$serverBaseUrl$path'
        : '$serverBaseUrl/$path';
  }

  factory MessageReportOption.fromJson(Map<String, dynamic> json) =>
      MessageReportOption(
        reportID: json['reportID']?.toString() ?? '',
        categoryName: json['categoryName']?.toString() ?? '',
        statusName: json['statusName']?.toString() ?? '',
        imagePath: json['imagePath']?.toString() ?? '',
        dateReported: parseApiTime(json['dateReported']),
      );
}

class BarangayMessagesPage extends StatefulWidget {
  final String userID;

  /// Opens with this report selected (e.g. from a notification).
  final String? initialReportID;

  const BarangayMessagesPage({
    super.key,
    required this.userID,
    this.initialReportID,
  });

  @override
  State<BarangayMessagesPage> createState() => _BarangayMessagesPageState();
}

class _BarangayMessagesPageState extends State<BarangayMessagesPage> {
  static const int _maxLength = 2000;

  final TextEditingController _composer = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _composerFocus = FocusNode();

  List<BarangayMessage> _messages = [];
  List<MessageReportOption> _reports = [];
  String _barangayName = '';
  bool _loading = true;
  bool _sending = false;
  String? _error;
  Timer? _poll;

  /// The report the next message is about ('' = general message).
  String _selectedReportID = '';
  BarangayMessage? _replyingTo;
  final Set<String> _deleting = {};

  @override
  void initState() {
    super.initState();
    _selectedReportID = widget.initialReportID?.trim() ?? '';
    _load(includeReports: true);
    _poll = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!_sending) _load(silent: true);
    });
    LiveUpdates.instance.changes.addListener(_onLiveUpdate);
    _composer.addListener(() => setState(() {}));
  }

  void _onLiveUpdate() {
    if (mounted && !_sending) _load(silent: true, includeReports: true);
  }

  @override
  void dispose() {
    _poll?.cancel();
    LiveUpdates.instance.changes.removeListener(_onLiveUpdate);
    _composer.dispose();
    _scroll.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  MessageReportOption? get _selectedReport {
    for (final report in _reports) {
      if (report.reportID == _selectedReportID) return report;
    }
    return null;
  }

  void _applyResult(ApiResult result) {
    final raw = result.data;
    final list = raw is List
        ? raw
              .whereType<Map>()
              .map(
                (e) => BarangayMessage.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList()
        : <BarangayMessage>[];

    final rawReports = result.body['reports'];
    final reports = rawReports is List
        ? rawReports
              .whereType<Map>()
              .map(
                (e) =>
                    MessageReportOption.fromJson(Map<String, dynamic>.from(e)),
              )
              .where((r) => r.reportID.isNotEmpty)
              .toList()
        : null;

    final bool grew = list.length > _messages.length;
    setState(() {
      _messages = list;
      if (reports != null) {
        _reports = reports;
        // A report that no longer exists cannot be selected.
        if (_selectedReportID.isNotEmpty &&
            !reports.any((r) => r.reportID == _selectedReportID)) {
          _selectedReportID = '';
        }
      }
      // The message being answered was deleted meanwhile.
      if (_replyingTo != null && !list.any((m) => m.key == _replyingTo!.key)) {
        _replyingTo = null;
      }
      _barangayName = result.body['barangayName']?.toString() ?? _barangayName;
      _loading = false;
      _error = null;
    });

    if (grew) _scrollToBottom();
  }

  Future<void> _load({bool silent = false, bool includeReports = false}) async {
    if (!silent) {
      setState(() {
        _loading = _messages.isEmpty;
        _error = null;
      });
    }

    final result = await ApiClient.postForm('resident_messages.php', {
      'action': 'list',
      'userID': widget.userID,
      if (includeReports || _reports.isEmpty) 'includeReports': '1',
    });

    if (!mounted) return;

    if (result.success) {
      _applyResult(result);
    } else if (result.sessionExpired) {
      return; // ApiClient already logged the user out.
    } else if (!silent || _messages.isEmpty) {
      // A failed background refresh keeps what is already on screen.
      setState(() {
        _loading = false;
        _error = result.message;
      });
    }
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);

    final result = await ApiClient.postForm('resident_messages.php', {
      'action': 'send',
      'userID': widget.userID,
      'message': text,
      if (_selectedReportID.isNotEmpty) 'reportID': _selectedReportID,
      if (_replyingTo != null) 'replyTo': _replyingTo!.key,
    });

    if (!mounted) return;
    setState(() => _sending = false);

    if (result.success) {
      _composer.clear();
      setState(() => _replyingTo = null);
      _applyResult(result);
      _scrollToBottom();
    } else if (result.sessionExpired) {
      return; // ApiClient already logged the user out.
    } else {
      _showError(result.message);
    }
  }

  Future<void> _delete(BarangayMessage message) async {
    if (!message.canDelete || _deleting.contains(message.key)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text(
          'This message will be deleted for you and for your barangay.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _deleting.add(message.key));

    final result = await ApiClient.postForm('resident_messages.php', {
      'action': 'delete',
      'userID': widget.userID,
      'key': message.key,
    });

    if (!mounted) return;
    setState(() => _deleting.remove(message.key));

    if (result.success) {
      _applyResult(result);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Message deleted.')));
    } else if (result.sessionExpired) {
      return; // ApiClient already logged the user out.
    } else {
      _showError(result.message);
      _load(silent: true);
    }
  }

  void _startReply(BarangayMessage message) {
    setState(() {
      _replyingTo = message;
      // Keep the reply with the same report as the message it answers.
      _selectedReportID = message.reportID;
    });
    _composerFocus.requestFocus();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.danger),
    );
  }

  void _showMessageActions(BarangayMessage message) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: const Text('Reply'),
              onTap: () {
                Navigator.pop(sheetContext);
                _startReply(message);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('Copy text'),
              onTap: () {
                Navigator.pop(sheetContext);
                Clipboard.setData(ClipboardData(text: message.message));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Message copied.')),
                );
              },
            ),
            if (message.canDelete)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.danger,
                ),
                title: const Text(
                  'Delete',
                  style: TextStyle(color: AppColors.danger),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _delete(message);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ------------------------------------------------------------
  // CHOOSE A REPORT
  // ------------------------------------------------------------

  Future<void> _chooseReport() async {
    FocusScope.of(context).unfocus();

    final chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            const Text(
              'What is your message about?',
              style: TextStyle(
                fontFamily: appHeadingFontFamily,
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Choose one of your reports so your barangay knows which one '
              'you are asking about.',
              style: TextStyle(
                fontFamily: appFontFamily,
                fontSize: 13,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 14),
            _reportOptionTile(
              sheetContext,
              null,
              selected: _selectedReportID.isEmpty,
            ),
            if (_reports.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Text(
                  'You have not submitted any reports yet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: appFontFamily,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            for (final report in _reports)
              _reportOptionTile(
                sheetContext,
                report,
                selected: report.reportID == _selectedReportID,
              ),
          ],
        ),
      ),
    );

    if (chosen != null && mounted) {
      setState(() => _selectedReportID = chosen);
    }
  }

  Widget _reportOptionTile(
    BuildContext sheetContext,
    MessageReportOption? report, {
    required bool selected,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected ? AppColors.primarySoft : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: () => Navigator.pop(sheetContext, report?.reportID ?? ''),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.divider,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                _reportThumbnail(report, size: 56),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        report == null ? 'General message' : report.reportID,
                        style: const TextStyle(
                          fontFamily: appHeadingFontFamily,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        report == null
                            ? 'A question that is not about one report'
                            : report.categoryName.isEmpty
                            ? 'Report'
                            : report.categoryName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: appFontFamily,
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (report != null && report.statusName.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        _statusPill(report.statusName),
                      ],
                    ],
                  ),
                ),
                if (selected)
                  const Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.primary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _reportThumbnail(MessageReportOption? report, {double size = 40}) {
    final url = report?.imageUrl;
    final fallback = Container(
      width: size,
      height: size,
      color: AppColors.primarySoft,
      alignment: Alignment.center,
      child: Icon(
        report == null ? Icons.forum_outlined : Icons.assignment_outlined,
        color: AppColors.primary,
        size: size * 0.45,
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: size,
        height: size,
        child: url == null
            ? fallback
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) => fallback,
              ),
      ),
    );
  }

  Widget _statusPill(String status) {
    final lower = status.toLowerCase();
    final Color color = lower.contains('resolved') || lower.contains('complete')
        ? AppColors.success
        : lower.contains('progress')
        ? AppColors.primary
        : lower.contains('overdue') || lower.contains('reject')
        ? AppColors.danger
        : AppColors.warning;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontFamily: appHeadingFontFamily,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // BUILD
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Messages',
              style: TextStyle(
                fontFamily: appHeadingFontFamily,
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: AppColors.ink,
              ),
            ),
            Text(
              _barangayName.isNotEmpty
                  ? 'Barangay $_barangayName'
                  : 'Your barangay',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: appFontFamily,
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : () => _load(includeReports: true),
            icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(child: _buildBody()),
            _buildComposer(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_error != null && _messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_outlined,
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
                onPressed: () => _load(includeReports: true),
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    if (_messages.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(28),
        children: const [
          SizedBox(height: 40),
          Icon(Icons.forum_outlined, size: 54, color: AppColors.primary),
          SizedBox(height: 14),
          Text(
            'Start a conversation',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: appHeadingFontFamily,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Ask a question or share a concern with your barangay. '
            'Tap "About" below to choose the report you are asking about. '
            'Their replies will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: appFontFamily,
              height: 1.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () => _load(includeReports: true),
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        itemCount: _messages.length,
        itemBuilder: (context, index) => _bubble(_messages[index]),
      ),
    );
  }

  Widget _bubble(BarangayMessage m) {
    final bool mine = !m.fromBarangay;
    final bool deleting = _deleting.contains(m.key);
    final maxWidth = MediaQuery.sizeOf(context).width * 0.8;
    final Color subtle = mine
        ? Colors.white.withValues(alpha: 0.85)
        : AppColors.textMuted;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Column(
          crossAxisAlignment: mine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Opacity(
              opacity: deleting ? 0.5 : 1,
              child: GestureDetector(
                onLongPress: () => _showMessageActions(m),
                child: Container(
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 9),
                  decoration: BoxDecoration(
                    color: mine ? AppColors.primary : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(mine ? 18 : 4),
                      bottomRight: Radius.circular(mine ? 4 : 18),
                    ),
                    border: mine ? null : Border.all(color: AppColors.divider),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!mine)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.verified_rounded,
                                size: 14,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  m.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontFamily: appHeadingFontFamily,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (m.reportLabel.isNotEmpty) _reportTag(m, mine),
                      if (m.replyTo != null) _replyQuote(m.replyTo!, mine),
                      Text(
                        m.message,
                        style: TextStyle(
                          fontFamily: appFontFamily,
                          fontFamilyFallback: emojiFontFallback,
                          fontSize: 14,
                          height: 1.45,
                          color: mine ? Colors.white : AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        relativeTime(m.createdAt),
                        style: TextStyle(
                          fontFamily: appFontFamily,
                          fontSize: 11,
                          color: subtle,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Visible actions (long press also shows them).
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _miniAction(
                    'Reply',
                    Icons.reply_rounded,
                    () => _startReply(m),
                  ),
                  if (m.canDelete) ...[
                    const SizedBox(width: 6),
                    _miniAction(
                      'Delete',
                      Icons.delete_outline_rounded,
                      deleting ? null : () => _delete(m),
                      color: AppColors.danger,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniAction(
    String label,
    IconData icon,
    VoidCallback? onTap, {
    Color color = AppColors.textSecondary,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontFamily: appHeadingFontFamily,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reportTag(BarangayMessage m, bool mine) {
    final Color color = mine ? Colors.white : AppColors.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: mine
            ? Colors.white.withValues(alpha: 0.18)
            : AppColors.primarySoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.assignment_outlined, size: 13, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              m.reportLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: appHeadingFontFamily,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _replyQuote(BarangayMessageReply reply, bool mine) {
    final Color bar = mine ? Colors.white : AppColors.primary;
    final Color text = mine
        ? Colors.white.withValues(alpha: 0.9)
        : AppColors.textSecondary;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 6),
      decoration: BoxDecoration(
        color: mine
            ? Colors.white.withValues(alpha: 0.15)
            : AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: bar, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!reply.missing)
            Text(
              'Replying to ${reply.name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: appHeadingFontFamily,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: bar,
              ),
            ),
          Text(
            reply.text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: appFontFamily,
              fontFamilyFallback: emojiFontFallback,
              fontSize: 12.5,
              fontStyle: reply.missing ? FontStyle.italic : FontStyle.normal,
              color: text,
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // COMPOSER
  // ------------------------------------------------------------

  Widget _buildComposer() {
    final bool canSend = _composer.text.trim().isNotEmpty && !_sending;
    final report = _selectedReport;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // What the message is about.
          InkWell(
            onTap: _sending ? null : _chooseReport,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  _reportThumbnail(report, size: 34),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'About',
                          style: TextStyle(
                            fontFamily: appFontFamily,
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                        Text(
                          report?.label ?? 'General message',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: appHeadingFontFamily,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Text(
                    'Change',
                    style: TextStyle(
                      fontFamily: appHeadingFontFamily,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  const Icon(
                    Icons.expand_more_rounded,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          ),
          if (_replyingTo != null) _replyBar(_replyingTo!),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _composer,
                  focusNode: _composerFocus,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: _maxLength,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(
                    fontFamily: appFontFamily,
                    fontFamilyFallback: emojiFontFallback,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: report == null
                        ? 'Write a message…'
                        : 'Ask about ${report.reportID}…',
                    counterText: '',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                tooltip: 'Send',
                onPressed: canSend ? _send : null,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor: AppColors.disabled,
                ),
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded, color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _replyBar(BarangayMessage message) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(10),
        border: const Border(
          left: BorderSide(color: AppColors.primary, width: 3),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.fromBarangay
                      ? 'Replying to ${message.name}'
                      : 'Replying to your message',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: appHeadingFontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
                Text(
                  message.message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: appFontFamily,
                    fontFamilyFallback: emojiFontFallback,
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cancel reply',
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _replyingTo = null),
            icon: const Icon(
              Icons.close_rounded,
              size: 18,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
