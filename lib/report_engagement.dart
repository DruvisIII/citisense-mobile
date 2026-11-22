import 'dart:async';
import 'dart:convert';

import 'package:citisense/api_config.dart';
import 'package:citisense/app_theme.dart';
import 'package:citisense/live_updates.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// ============================================================
// REPORT ENGAGEMENT
// ------------------------------------------------------------
// Shown at the bottom of Report Details:
//   1. "Rate the Resolution" - after the report is resolved
//      (STAT003) the resident confirms it is fixed and rates
//      how the barangay handled it.
//   2. "Updates & Messages" - the barangay's status updates and
//      a two-way conversation about the report.
//
// Server endpoints (api/):
//   get_report_thread.php       POST userID, reportID
//   send_report_message.php     POST userID, reportID, message
//   submit_report_feedback.php  POST userID, reportID, isFixed, rating, comment
// ============================================================

const String _apiUrl = apiBaseUrl;

class ThreadItem {
  ThreadItem({
    required this.type,
    required this.message,
    required this.createdAt,
  });

  /// 'system' (status update), 'barangay', or 'resident'.
  final String type;
  final String message;
  final DateTime? createdAt;

  factory ThreadItem.fromJson(Map<String, dynamic> json) => ThreadItem(
    type: json['type']?.toString() ?? 'system',
    message: json['message']?.toString() ?? '',
    createdAt: DateTime.tryParse(
      (json['createdAt']?.toString() ?? '').replaceFirst(' ', 'T'),
    ),
  );
}

class ReportFeedback {
  const ReportFeedback({
    required this.isFixed,
    required this.rating,
    required this.comment,
  });

  final bool isFixed;
  final int rating;
  final String comment;

  factory ReportFeedback.fromJson(Map<String, dynamic> json) => ReportFeedback(
    isFixed: json['isFixed'] == true,
    rating: int.tryParse(json['rating']?.toString() ?? '') ?? 0,
    comment: json['comment']?.toString() ?? '',
  );
}

class EngagementResult<T> {
  const EngagementResult(this.success, this.message, [this.data]);

  final bool success;
  final String message;
  final T? data;
}

class ReportEngagementApi {
  ReportEngagementApi._();

  static Future<Map<String, dynamic>> _post(
    String endpoint,
    Map<String, String> body,
  ) async {
    final response = await http
        .post(
          Uri.parse('$_apiUrl/$endpoint'),
          headers: {'Accept': 'application/json'},
          body: body,
        )
        .timeout(const Duration(seconds: 25));

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Unexpected server response.');
    }
    decoded['_ok'] = response.statusCode == 200 && decoded['success'] == true;
    return decoded;
  }

  static Future<EngagementResult<Map<String, dynamic>>> loadThread({
    required String userID,
    required String reportID,
  }) async {
    try {
      final d = await _post('get_report_thread.php', {
        'userID': userID,
        'reportID': reportID,
      });
      return EngagementResult(
        d['_ok'] == true,
        d['message']?.toString() ?? '',
        d['data'] is Map<String, dynamic> ? d['data'] : null,
      );
    } catch (e) {
      debugPrint('Load thread error: $e');
      return const EngagementResult(
        false,
        'Unable to load messages. Check your connection.',
      );
    }
  }

  static Future<EngagementResult<void>> sendMessage({
    required String userID,
    required String reportID,
    required String message,
  }) async {
    try {
      final d = await _post('send_report_message.php', {
        'userID': userID,
        'reportID': reportID,
        'message': message,
      });
      return EngagementResult(
        d['_ok'] == true,
        d['message']?.toString() ?? 'Failed to send your message.',
      );
    } catch (e) {
      debugPrint('Send message error: $e');
      return const EngagementResult(
        false,
        'Unable to send your message. Check your connection.',
      );
    }
  }

  static Future<EngagementResult<void>> submitFeedback({
    required String userID,
    required String reportID,
    required bool isFixed,
    required int rating,
    required String comment,
  }) async {
    try {
      final d = await _post('submit_report_feedback.php', {
        'userID': userID,
        'reportID': reportID,
        'isFixed': isFixed ? '1' : '0',
        'rating': rating.toString(),
        'comment': comment,
      });
      return EngagementResult(
        d['_ok'] == true,
        d['message']?.toString() ?? 'Failed to save your feedback.',
      );
    } catch (e) {
      debugPrint('Submit feedback error: $e');
      return const EngagementResult(
        false,
        'Unable to send your feedback. Check your connection.',
      );
    }
  }
}

// ============================================================
// SECTION WIDGET
// ============================================================

class ReportEngagementSection extends StatefulWidget {
  const ReportEngagementSection({
    super.key,
    required this.userID,
    required this.reportID,
    required this.isResolved,
    this.dateReported,
  });

  final String userID;
  final String reportID;

  /// True when the report is COMPLETE (STAT003).
  final bool isResolved;
  final DateTime? dateReported;

  @override
  State<ReportEngagementSection> createState() =>
      _ReportEngagementSectionState();
}

class _ReportEngagementSectionState extends State<ReportEngagementSection> {
  bool _loading = true;
  String? _loadError;
  List<ThreadItem> _items = [];
  ReportFeedback? _feedback;

  // Feedback form
  bool _editingFeedback = false;
  bool? _isFixed;
  int _rating = 0;
  final TextEditingController _feedbackComment = TextEditingController();
  bool _savingFeedback = false;

  // Composer
  final TextEditingController _messageController = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
    // Barangay replies and status updates appear without refreshing.
    LiveUpdates.instance.changes.addListener(_onLiveUpdate);
  }

  void _onLiveUpdate() {
    if (mounted && !_sending && !_savingFeedback) _load(silent: true);
  }

  @override
  void dispose() {
    LiveUpdates.instance.changes.removeListener(_onLiveUpdate);
    _feedbackComment.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }

    final result = await ReportEngagementApi.loadThread(
      userID: widget.userID,
      reportID: widget.reportID,
    );

    if (!mounted) return;

    if (!result.success || result.data == null) {
      // A failed background refresh keeps what is on screen.
      if (silent) return;
      setState(() {
        _loading = false;
        _loadError = result.message.isEmpty
            ? 'Unable to load messages.'
            : result.message;
      });
      return;
    }

    final data = result.data!;
    final rawItems = data['items'];
    final rawFeedback = data['feedback'];

    setState(() {
      _loading = false;
      _items = rawItems is List
          ? rawItems
                .whereType<Map>()
                .map((e) => ThreadItem.fromJson(Map<String, dynamic>.from(e)))
                .toList()
          : [];
      _feedback = rawFeedback is Map
          ? ReportFeedback.fromJson(Map<String, dynamic>.from(rawFeedback))
          : null;
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ------------------------------------------------------------
  // FEEDBACK
  // ------------------------------------------------------------

  void _startEditingFeedback() {
    setState(() {
      _editingFeedback = true;
      _isFixed = _feedback?.isFixed;
      _rating = _feedback?.rating ?? 0;
      _feedbackComment.text = _feedback?.comment ?? '';
    });
  }

  Future<void> _submitFeedback() async {
    if (_isFixed == null || _rating == 0) return;

    setState(() => _savingFeedback = true);

    final result = await ReportEngagementApi.submitFeedback(
      userID: widget.userID,
      reportID: widget.reportID,
      isFixed: _isFixed!,
      rating: _rating,
      comment: _feedbackComment.text.trim(),
    );

    if (!mounted) return;
    setState(() => _savingFeedback = false);
    _toast(result.message);

    if (result.success) {
      setState(() => _editingFeedback = false);
      await _load();
    }
  }

  // ------------------------------------------------------------
  // MESSAGES
  // ------------------------------------------------------------

  Future<void> _send() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);

    final result = await ReportEngagementApi.sendMessage(
      userID: widget.userID,
      reportID: widget.reportID,
      message: text,
    );

    if (!mounted) return;
    setState(() => _sending = false);

    if (result.success) {
      _messageController.clear();
      FocusScope.of(context).unfocus();
      await _load();
    } else {
      _toast(result.message);
    }
  }

  // ------------------------------------------------------------
  // BUILD
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.isResolved) ...[
          const SizedBox(height: 28),
          _sectionTitle(
            'Rate the Resolution',
            'Let your barangay know if the issue is really fixed.',
          ),
          const SizedBox(height: 12),
          _buildFeedbackCard(),
        ],
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
              child: _sectionTitle(
                'Updates & Messages',
                'Reply to your barangay or add more details.',
              ),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildThread(),
        const SizedBox(height: 12),
        _buildComposer(),
      ],
    );
  }

  Widget _sectionTitle(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
            fontFamily: appFontFamily,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
            fontFamily: appFontFamily,
          ),
        ),
      ],
    );
  }

  BoxDecoration get _cardDecoration => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(AppRadius.lg),
    border: Border.all(color: AppColors.divider),
  );

  // ------------------------------------------------------------
  // FEEDBACK CARD
  // ------------------------------------------------------------

  Widget _buildFeedbackCard() {
    if (_loading && _feedback == null) {
      return Container(
        height: 90,
        decoration: _cardDecoration,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(strokeWidth: 2.4),
      );
    }

    if (_feedback != null && !_editingFeedback) {
      return _buildFeedbackSummary(_feedback!);
    }

    return _buildFeedbackForm();
  }

  Widget _buildFeedbackSummary(ReportFeedback fb) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _pill(
                fb.isFixed ? 'Confirmed fixed' : 'Not fixed yet',
                fb.isFixed ? AppColors.success : AppColors.danger,
                fb.isFixed ? AppColors.successSoft : AppColors.dangerSoft,
                fb.isFixed ? Icons.check_circle_rounded : Icons.cancel_rounded,
              ),
              const Spacer(),
              TextButton(
                onPressed: _startEditingFeedback,
                child: const Text('Edit'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              ...List.generate(
                5,
                (i) => Icon(
                  i < fb.rating
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  color: i < fb.rating
                      ? const Color(0xFFF5B800)
                      : AppColors.border,
                  size: 24,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _ratingLabel(fb.rating),
                style: const TextStyle(
                  fontFamily: appFontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
          if (fb.comment.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '"${fb.comment}"',
              style: const TextStyle(
                fontFamily: appFontFamily,
                fontSize: 13,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFeedbackForm() {
    final bool canSubmit = _isFixed != null && _rating > 0 && !_savingFeedback;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Is the issue fixed?', style: AppText.fieldLabel),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _choice(
                  label: "Yes, it's fixed",
                  icon: Icons.check_circle_outline_rounded,
                  selected: _isFixed == true,
                  color: AppColors.success,
                  onTap: () => setState(() => _isFixed = true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _choice(
                  label: 'Not yet',
                  icon: Icons.highlight_off_rounded,
                  selected: _isFixed == false,
                  color: AppColors.danger,
                  onTap: () => setState(() => _isFixed = false),
                ),
              ),
            ],
          ),
          if (_isFixed == false) ...[
            const SizedBox(height: 8),
            const Text(
              'Your barangay will see this in Updates & Messages.',
              style: TextStyle(
                fontFamily: appFontFamily,
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 18),
          const Text(
            'How did the barangay handle it?',
            style: AppText.fieldLabel,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              ...List.generate(
                5,
                (i) => IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                  onPressed: () => setState(() => _rating = i + 1),
                  icon: Icon(
                    i < _rating
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: i < _rating
                        ? const Color(0xFFF5B800)
                        : AppColors.border,
                    size: 32,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _ratingLabel(_rating),
                style: const TextStyle(
                  fontFamily: appFontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _feedbackComment,
            maxLength: 300,
            maxLines: 3,
            minLines: 2,
            style: const TextStyle(fontFamily: appFontFamily, fontSize: 14),
            decoration: const InputDecoration(
              hintText: 'Add a short comment (optional)',
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              if (_feedback != null)
                TextButton(
                  onPressed: _savingFeedback
                      ? null
                      : () => setState(() => _editingFeedback = false),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              const Spacer(),
              SizedBox(
                height: 46,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(140, 46),
                  ),
                  onPressed: canSubmit ? _submitFeedback : null,
                  child: _savingFeedback
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Submit Feedback'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _ratingLabel(int rating) {
    switch (rating) {
      case 1:
        return 'Poor';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      case 4:
        return 'Very good';
      case 5:
        return 'Excellent';
      default:
        return 'Tap a star';
    }
  }

  Widget _choice({
    required String label,
    required IconData icon,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? color.withValues(alpha: 0.10) : AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: _savingFeedback ? null : onTap,
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: selected ? color : AppColors.border,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? color : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: appFontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: selected ? color : AppColors.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(String text, Color color, Color bg, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              fontFamily: appFontFamily,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // THREAD
  // ------------------------------------------------------------

  Widget _buildThread() {
    if (_loading && _items.isEmpty) {
      return Container(
        height: 90,
        decoration: _cardDecoration,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(strokeWidth: 2.4),
      );
    }

    if (_loadError != null && _items.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: _cardDecoration,
        child: Column(
          children: [
            Text(
              _loadError!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: appFontFamily,
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            TextButton(onPressed: _load, child: const Text('Try Again')),
          ],
        ),
      );
    }

    final List<Widget> rows = [];

    // The report submission is always the first entry.
    rows.add(
      _systemRow(
        'You submitted this report.',
        widget.dateReported,
        Icons.send_rounded,
      ),
    );

    for (final item in _items) {
      if (item.type == 'system') {
        rows.add(
          _systemRow(item.message, item.createdAt, Icons.update_rounded),
        );
      } else {
        rows.add(_bubble(item));
      }
    }

    if (_items.where((i) => i.type != 'system').isEmpty) {
      rows.add(
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            'No messages yet. Ask a question or add details for your barangay.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: appFontFamily,
              fontSize: 12,
              color: AppColors.textMuted,
            ),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(children: rows),
    );
  }

  Widget _systemRow(String text, DateTime? date, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              color: AppColors.primarySoft,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 15, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: const TextStyle(
                    fontFamily: appFontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                if (date != null)
                  Text(
                    _formatStamp(date),
                    style: const TextStyle(
                      fontFamily: appFontFamily,
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(ThreadItem item) {
    final bool mine = item.type == 'resident';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.68,
          ),
          child: Column(
            crossAxisAlignment: mine
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Text(
                mine ? 'You' : 'Barangay',
                style: TextStyle(
                  fontFamily: appFontFamily,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: mine ? AppColors.textSecondary : AppColors.primary,
                ),
              ),
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: mine ? AppColors.primary : Colors.white,
                  border: mine ? null : Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(mine ? 16 : 4),
                    bottomRight: Radius.circular(mine ? 4 : 16),
                  ),
                ),
                child: Text(
                  item.message,
                  style: TextStyle(
                    fontFamily: appFontFamily,
                    fontSize: 13,
                    height: 1.45,
                    color: mine ? Colors.white : AppColors.ink,
                  ),
                ),
              ),
              if (item.createdAt != null) ...[
                const SizedBox(height: 3),
                Text(
                  _formatStamp(item.createdAt!),
                  style: const TextStyle(
                    fontFamily: appFontFamily,
                    fontSize: 10,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComposer() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: _messageController,
            minLines: 1,
            maxLines: 4,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontFamily: appFontFamily, fontSize: 14),
            decoration: const InputDecoration(
              hintText: 'Write a message to your barangay...',
              counterText: '',
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 50,
          height: 50,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(50, 50),
            ),
            onPressed: _sending ? null : _send,
            child: _sending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send_rounded, size: 22),
          ),
        ),
      ],
    );
  }

  String _formatStamp(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final period = d.hour >= 12 ? 'PM' : 'AM';
    final minute = d.minute.toString().padLeft(2, '0');
    return '${months[d.month - 1]} ${d.day}, ${d.year} • $hour:$minute $period';
  }
}
