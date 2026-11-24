import 'dart:async';

import 'package:flutter/material.dart';

import 'package:citisense/api_client.dart';
import 'package:citisense/app_theme.dart';
import 'package:citisense/live_updates.dart';

// ============================================================
// MESSAGES WITH YOUR BARANGAY
// ------------------------------------------------------------
// A two-way conversation with the barangay that is not about one
// report (report conversations stay under each report's
// "Updates & Messages"). Uses api/resident_messages.php; the admin
// website's Messages page reads and replies to the same messages.
// New replies appear automatically: every 10 seconds while this
// screen is open, and right away when a push notification arrives.
// ============================================================

class BarangayMessage {
  const BarangayMessage({
    required this.id,
    required this.fromBarangay,
    required this.name,
    required this.message,
    required this.createdAt,
  });

  final int id;
  final bool fromBarangay;
  final String name;
  final String message;
  final DateTime? createdAt;

  factory BarangayMessage.fromJson(Map<String, dynamic> json) =>
      BarangayMessage(
        id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
        fromBarangay: json['fromBarangay'] == true,
        name: json['name']?.toString() ?? '',
        message: json['message']?.toString() ?? '',
        createdAt: parseApiTime(json['createdAt']),
      );
}

class BarangayMessagesPage extends StatefulWidget {
  final String userID;

  const BarangayMessagesPage({super.key, required this.userID});

  @override
  State<BarangayMessagesPage> createState() => _BarangayMessagesPageState();
}

class _BarangayMessagesPageState extends State<BarangayMessagesPage> {
  static const int _maxLength = 2000;

  final TextEditingController _composer = TextEditingController();
  final ScrollController _scroll = ScrollController();

  List<BarangayMessage> _messages = [];
  String _barangayName = '';
  bool _loading = true;
  bool _sending = false;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!_sending) _load(silent: true);
    });
    LiveUpdates.instance.changes.addListener(_onLiveUpdate);
    _composer.addListener(() => setState(() {}));
  }

  void _onLiveUpdate() {
    if (mounted && !_sending) _load(silent: true);
  }

  @override
  void dispose() {
    _poll?.cancel();
    LiveUpdates.instance.changes.removeListener(_onLiveUpdate);
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
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

    final bool grew = list.length > _messages.length;
    setState(() {
      _messages = list;
      _barangayName = result.body['barangayName']?.toString() ?? _barangayName;
      _loading = false;
      _error = null;
    });

    if (grew) _scrollToBottom();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = _messages.isEmpty;
        _error = null;
      });
    }

    final result = await ApiClient.postForm('resident_messages.php', {
      'action': 'list',
      'userID': widget.userID,
    });

    if (!mounted) return;

    if (result.success) {
      _applyResult(result);
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
    });

    if (!mounted) return;
    setState(() => _sending = false);

    if (result.success) {
      _composer.clear();
      _applyResult(result);
    } else {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: AppColors.danger,
        ),
      );
    }
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
            onPressed: _loading ? null : () => _load(),
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
              TextButton(onPressed: _load, child: const Text('Try Again')),
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
      onRefresh: _load,
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
    final maxWidth = MediaQuery.sizeOf(context).width * 0.78;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
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
              Text(
                m.message,
                style: TextStyle(
                  fontFamily: appFontFamily,
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
                  color: mine
                      ? Colors.white.withValues(alpha: 0.8)
                      : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComposer() {
    final bool canSend = _composer.text.trim().isNotEmpty && !_sending;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _composer,
              minLines: 1,
              maxLines: 5,
              maxLength: _maxLength,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(fontFamily: appFontFamily, fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'Write a message…',
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
    );
  }
}
