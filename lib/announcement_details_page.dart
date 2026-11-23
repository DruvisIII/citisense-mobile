import 'package:flutter/material.dart';

import 'package:citisense/app_theme.dart';

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
      ? value
      : DateTime.tryParse(value?.toString() ?? '');
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

  const AnnouncementDetailsPage({super.key, required this.announcement});

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
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_month_outlined,
                          size: 16,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            dateText,
                            style: const TextStyle(
                              fontFamily: appFontFamily,
                              fontSize: 12.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
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
          ],
        ),
      ),
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
