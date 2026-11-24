import 'dart:async';

import 'package:flutter/material.dart';

import 'package:citisense/api_client.dart';
import 'package:citisense/app_theme.dart';
import 'package:citisense/live_updates.dart';

// ============================================================
// ANNOUNCEMENT HELPERS
// ------------------------------------------------------------
// Shared by the Home announcement cards and the details page.
// ============================================================

/// Picture URLs of an announcement, as returned by get_announcements.php.
List<String> announcementImages(Map<String, dynamic> announcement) {
  final dynamic images = announcement['images'];
  final List<String> urls = [];

  if (images is List) {
    for (final image in images) {
      final url = image?.toString().trim() ?? '';
      if (url.isNotEmpty) urls.add(url);
    }
  }

  // Older API responses used a single image field.
  if (urls.isEmpty) {
    final single =
        (announcement['imageUrl'] ??
                announcement['image'] ??
                announcement['image_url'] ??
                '')
            .toString()
            .trim();
    if (single.isNotEmpty) urls.add(single);
  }

  return urls;
}

/// "November 23, 2026 · 09:05 AM", or '' when the date is missing.
String formatAnnouncementDateTime(dynamic value) {
  final DateTime? date = value is DateTime
      ? value.toLocal()
      : parseApiTime(value);
  if (date == null) return '';

  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  int hour = date.hour % 12;
  if (hour == 0) hour = 12;
  final minute = date.minute.toString().padLeft(2, '0');
  final period = date.hour >= 12 ? 'PM' : 'AM';

  return '${months[date.month - 1]} ${date.day.toString().padLeft(2, '0')}, '
      '${date.year} · ${hour.toString().padLeft(2, '0')}:$minute $period';
}

/// A network picture with a loading spinner and a "not available" fallback.
class AnnouncementNetworkImage extends StatelessWidget {
  final String url;
  final BoxFit fit;

  const AnnouncementNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: fit,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          color: AppColors.primarySoft,
          alignment: Alignment.center,
          child: const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppColors.primary,
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return Container(
          color: AppColors.primarySoft,
          alignment: Alignment.center,
          child: const Icon(
            Icons.image_not_supported_outlined,
            size: 34,
            color: AppColors.textMuted,
          ),
        );
      },
    );
  }
}

// ============================================================
// ANNOUNCEMENT DETAILS PAGE
// ============================================================

class AnnouncementDetailsPage extends StatefulWidget {
  final Map<String, dynamic> announcement;

  /// The logged-in resident (needed for comments).
  final String userID;

  const AnnouncementDetailsPage({
    super.key,
    required this.announcement,
    required this.userID,
  });

  @override
  State<AnnouncementDetailsPage> createState() =>
      _AnnouncementDetailsPageState();
}

class _AnnouncementDetailsPageState extends State<AnnouncementDetailsPage> {
  final PageController _pageController = PageController();
  int _currentImage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _openFullScreen(List<String> images, int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _FullScreenGallery(images: images, initialIndex: index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final announcement = widget.announcement;
    final title = announcement['title']?.toString().trim() ?? '';
    final content = announcement['content']?.toString().trim() ?? '';
    final barangayName = announcement['barangayName']?.toString().trim() ?? '';
    final postedBy = announcement['postedBy']?.toString().trim() ?? '';
    final dateText = formatAnnouncementDateTime(announcement['datePosted']);
    final images = announcementImages(announcement);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.ink,
        title: const Text(
          'Announcement',
          style: TextStyle(
            fontFamily: appFontFamily,
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: AppColors.ink,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: [
            // ------------------------------------------------
            // PICTURES (swipe; tap to view full screen)
            // ------------------------------------------------
            if (images.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Stack(
                    children: [
                      PageView.builder(
                        controller: _pageController,
                        itemCount: images.length,
                        onPageChanged: (index) =>
                            setState(() => _currentImage = index),
                        itemBuilder: (context, index) => GestureDetector(
                          onTap: () => _openFullScreen(images, index),
                          child: AnnouncementNetworkImage(url: images[index]),
                        ),
                      ),
                      if (images.length > 1)
                        Positioned(
                          top: 10,
                          right: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${_currentImage + 1} / ${images.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (images.length > 1) ...[
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(images.length, (index) {
                    final active = index == _currentImage;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: active ? 18 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: active
                            ? AppColors.primary
                            : AppColors.primaryBorder,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),
              ],
              const SizedBox(height: 16),
            ],

            // ------------------------------------------------
            // TEXT
            // ------------------------------------------------
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                boxShadow: AppShadows.card,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (barangayName.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Barangay $barangayName',
                        style: const TextStyle(
                          fontFamily: appFontFamily,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  Text(
                    title.isNotEmpty ? title : 'Announcement',
                    style: const TextStyle(
                      fontFamily: appFontFamily,
                      fontSize: 20,
                      height: 1.25,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                  if (dateText.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _metaRow(Icons.calendar_month_outlined, dateText),
                  ],
                  if (postedBy.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _metaRow(
                      Icons.verified_user_outlined,
                      'Posted by $postedBy',
                    ),
                  ],
                  const SizedBox(height: 14),
                  const Divider(height: 1, color: AppColors.divider),
                  const SizedBox(height: 14),
                  SelectableText(
                    content.isNotEmpty
                        ? content
                        : 'No announcement details available.',
                    style: const TextStyle(
                      fontFamily: appFontFamily,
                      fontSize: 14.5,
                      height: 1.6,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
            ),

            // ------------------------------------------------
            // COMMENTS
            // ------------------------------------------------
            const SizedBox(height: 16),
            AnnouncementComments(
              announceID: announcement['announceID']?.toString() ?? '',
              userID: widget.userID,
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontFamily: appFontFamily,
              fontSize: 12.5,
              height: 1.35,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// FULL-SCREEN PICTURE VIEWER (pinch to zoom, swipe between)
// ============================================================

class _FullScreenGallery extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const _FullScreenGallery({required this.images, required this.initialIndex});

  @override
  State<_FullScreenGallery> createState() => _FullScreenGalleryState();
}

class _FullScreenGalleryState extends State<_FullScreenGallery> {
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: widget.images.length > 1
            ? Text(
                '${_index + 1} of ${widget.images.length}',
                style: const TextStyle(fontSize: 16),
              )
            : null,
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.images.length,
        onPageChanged: (index) => setState(() => _index = index),
        itemBuilder: (context, index) => InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(
            child: AnnouncementNetworkImage(
              url: widget.images[index],
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// ANNOUNCEMENT COMMENTS
// ------------------------------------------------------------
// Residents and barangay officials comment on an announcement
// (api/announcement_comments.php, same table as the admin
// website). Officials' comments are highlighted with a
// "Barangay" badge. New comments appear automatically.
// ============================================================

class AnnouncementComment {
  const AnnouncementComment({
    required this.id,
    required this.fromBarangay,
    required this.isMine,
    required this.name,
    required this.message,
    required this.hidden,
    required this.replyToName,
    required this.createdAt,
  });

  final int id;
  final bool fromBarangay;
  final bool isMine;
  final String name;
  final String message;
  final bool hidden;
  final String? replyToName;
  final DateTime? createdAt;

  factory AnnouncementComment.fromJson(Map<String, dynamic> json) =>
      AnnouncementComment(
        id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
        fromBarangay: json['fromBarangay'] == true,
        isMine: json['isMine'] == true,
        name: json['name']?.toString() ?? '',
        message: json['message']?.toString() ?? '',
        hidden: json['hidden'] == true,
        replyToName: json['replyToName']?.toString(),
        createdAt: parseApiTime(json['createdAt']),
      );
}

class AnnouncementComments extends StatefulWidget {
  final String announceID;
  final String userID;

  const AnnouncementComments({
    super.key,
    required this.announceID,
    required this.userID,
  });

  @override
  State<AnnouncementComments> createState() => _AnnouncementCommentsState();
}

class _AnnouncementCommentsState extends State<AnnouncementComments> {
  static const int _maxLength = 1000;

  final TextEditingController _composer = TextEditingController();
  List<AnnouncementComment> _comments = [];
  bool _loading = true;
  bool _posting = false;
  String? _error;
  AnnouncementComment? _replyingTo;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!_posting) _load(silent: true);
    });
    LiveUpdates.instance.changes.addListener(_onLiveUpdate);
    _composer.addListener(() => setState(() {}));
  }

  void _onLiveUpdate() {
    if (mounted && !_posting) _load(silent: true);
  }

  @override
  void dispose() {
    _poll?.cancel();
    LiveUpdates.instance.changes.removeListener(_onLiveUpdate);
    _composer.dispose();
    super.dispose();
  }

  List<AnnouncementComment> _parse(dynamic raw) => raw is List
      ? raw
            .whereType<Map>()
            .map(
              (e) => AnnouncementComment.fromJson(Map<String, dynamic>.from(e)),
            )
            .toList()
      : <AnnouncementComment>[];

  Future<void> _load({bool silent = false}) async {
    if (widget.announceID.isEmpty || widget.userID.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Comments are not available right now.';
      });
      return;
    }

    if (!silent) {
      setState(() {
        _loading = _comments.isEmpty;
        _error = null;
      });
    }

    final result = await ApiClient.postForm('announcement_comments.php', {
      'action': 'list',
      'userID': widget.userID,
      'announceID': widget.announceID,
    });

    if (!mounted) return;

    if (result.success) {
      setState(() {
        _comments = _parse(result.data);
        _loading = false;
        _error = null;
      });
    } else if (!silent || _comments.isEmpty) {
      setState(() {
        _loading = false;
        _error = result.message;
      });
    }
  }

  Future<void> _post() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _posting) return;

    setState(() => _posting = true);

    final result = await ApiClient.postForm('announcement_comments.php', {
      'action': 'add',
      'userID': widget.userID,
      'announceID': widget.announceID,
      'message': text,
      if (_replyingTo != null) 'parentID': _replyingTo!.id.toString(),
    });

    if (!mounted) return;
    setState(() => _posting = false);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    if (result.success) {
      _composer.clear();
      FocusScope.of(context).unfocus();
      setState(() {
        _comments = _parse(result.data);
        _replyingTo = null;
        _error = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your comment was posted.'),
          backgroundColor: AppColors.success,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 20,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _comments.isEmpty
                      ? 'Comments'
                      : 'Comments (${_comments.length})',
                  style: const TextStyle(
                    fontFamily: appFontFamily,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildList(),
          const SizedBox(height: 12),
          _buildComposer(),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }

    if (_error != null && _comments.isEmpty) {
      return Column(
        children: [
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: appFontFamily,
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          TextButton(onPressed: _load, child: const Text('Try Again')),
        ],
      );
    }

    if (_comments.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'No comments yet. Be the first to ask or share something.',
          style: TextStyle(
            fontFamily: appFontFamily,
            fontSize: 13,
            height: 1.45,
            color: AppColors.textSecondary,
          ),
        ),
      );
    }

    return Column(
      children: [for (final comment in _comments) _buildComment(comment)],
    );
  }

  Widget _buildComment(AnnouncementComment c) {
    final bool official = c.fromBarangay;
    final String initial = c.name.trim().isEmpty
        ? '?'
        : c.name.trim()[0].toUpperCase();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: official ? AppColors.primarySoft : AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: official ? AppColors.primaryBorder : Colors.transparent,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: official ? AppColors.primary : AppColors.border,
            child: official
                ? const Icon(
                    Icons.account_balance,
                    size: 17,
                    color: Colors.white,
                  )
                : Text(
                    initial,
                    style: const TextStyle(
                      fontFamily: appFontFamily,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 2,
                  children: [
                    Text(
                      c.isMine ? '${c.name} (You)' : c.name,
                      style: TextStyle(
                        fontFamily: appFontFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: official ? AppColors.primary : AppColors.ink,
                      ),
                    ),
                    if (official) _badge('Barangay', AppColors.primary),
                    if (c.hidden)
                      _badge('Hidden by barangay', AppColors.danger),
                  ],
                ),
                if (c.replyToName != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Replying to ${c.replyToName}',
                    style: const TextStyle(
                      fontFamily: appFontFamily,
                      fontSize: 11.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  c.message,
                  style: const TextStyle(
                    fontFamily: appFontFamily,
                    fontSize: 13.5,
                    height: 1.45,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      relativeTime(c.createdAt),
                      style: const TextStyle(
                        fontFamily: appFontFamily,
                        fontSize: 11.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                    if (!c.hidden) ...[
                      const SizedBox(width: 12),
                      InkWell(
                        onTap: () => setState(() => _replyingTo = c),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            'Reply',
                            style: TextStyle(
                              fontFamily: appFontFamily,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: appFontFamily,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  Widget _buildComposer() {
    final bool canPost = _composer.text.trim().isNotEmpty && !_posting;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_replyingTo != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Replying to ${_replyingTo!.fromBarangay ? 'Barangay' : _replyingTo!.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: appFontFamily,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => setState(() => _replyingTo = null),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _composer,
                minLines: 1,
                maxLines: 4,
                maxLength: _maxLength,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(fontFamily: appFontFamily, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Write a comment…',
                  counterText: '',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filled(
              tooltip: 'Post comment',
              onPressed: canPost ? _post : null,
              style: IconButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: AppColors.disabled,
              ),
              icon: _posting
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
    );
  }
}
