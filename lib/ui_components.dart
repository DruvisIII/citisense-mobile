import 'package:flutter/material.dart';

import 'package:citisense/app_theme.dart';

// ============================================================
// SHARED UI PIECES
// ------------------------------------------------------------
// - AppMotion       one duration and curve for every toggle
// - SlidingToggle   segmented switch with a sliding indicator
//                   (My Reports, Notifications, Settings > Font Size)
// - CitiPageHeader  the header of Home, My Reports, Notifications and
//                   Settings, with the same size and positions on every
//                   page so nothing jumps when switching tabs
// ============================================================

class AppMotion {
  AppMotion._();

  /// The sliding highlight of a toggle.
  static const Duration toggle = Duration(milliseconds: 220);
  static const Curve curve = Curves.easeOutCubic;

  /// The content a toggle switches (lists).
  static const Duration content = Duration(milliseconds: 180);

  /// Shows the content of the newly chosen option. The old content is
  /// removed at once (never laid out twice, so no lag or overlap) and the
  /// new content fades in with the same timing for every option.
  static Widget fadeSwitcher({
    required Object contentKey,
    required Widget child,
  }) {
    return AnimatedSwitcher(
      duration: content,
      switchInCurve: Curves.easeOut,
      layoutBuilder: (current, previous) => current ?? const SizedBox.shrink(),
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: KeyedSubtree(key: ValueKey<Object>(contentKey), child: child),
    );
  }
}

/// A row of options with one selected; the highlight slides to the
/// tapped option instead of jumping.
class SlidingToggle extends StatelessWidget {
  const SlidingToggle({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
    this.backgroundColor = Colors.white,
    this.indicatorColor = AppColors.primary,
    this.selectedTextColor = Colors.white,
    this.unselectedTextColor = AppColors.textSecondary,
    this.padding = 7,
    this.radius = AppRadius.lg,
    this.indicatorRadius = 14,
    this.itemVerticalPadding = 13,
    this.fontSize = 13,
    this.boxShadow,
    this.indicatorShadow,
    this.animate = true,
  });

  /// Settings style: light grey track, white indicator.
  const SlidingToggle.subtle({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
    this.animate = true,
  }) : backgroundColor = AppColors.surfaceMuted,
       indicatorColor = Colors.white,
       selectedTextColor = AppColors.ink,
       unselectedTextColor = AppColors.textSecondary,
       padding = 3,
       radius = AppRadius.sm,
       indicatorRadius = AppRadius.sm - 3,
       itemVerticalPadding = 9,
       fontSize = 12.5,
       boxShadow = null,
       indicatorShadow = const [
         BoxShadow(
           color: Color(0x0F1E3A6E),
           blurRadius: 4,
           offset: Offset(0, 2),
         ),
       ];

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  final Color backgroundColor;
  final Color indicatorColor;
  final Color selectedTextColor;
  final Color unselectedTextColor;
  final double padding;
  final double radius;
  final double indicatorRadius;
  final double itemVerticalPadding;
  final double fontSize;
  final List<BoxShadow>? boxShadow;
  final List<BoxShadow>? indicatorShadow;

  /// False: the highlight jumps straight to the new option (used where
  /// the change itself is heavy, e.g. Font Size re-lays out the app).
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final count = labels.length;
    final index = selectedIndex.clamp(0, count - 1);

    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: boxShadow,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = constraints.maxWidth / count;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: animate ? AppMotion.toggle : Duration.zero,
                curve: AppMotion.curve,
                left: itemWidth * index,
                width: itemWidth,
                top: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: indicatorColor,
                    borderRadius: BorderRadius.circular(indicatorRadius),
                    boxShadow: indicatorShadow,
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < count; i++)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: i == index,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(indicatorRadius),
                          onTap: () {
                            if (i != index) onChanged(i);
                          },
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              vertical: itemVerticalPadding,
                              horizontal: 2,
                            ),
                            child: AnimatedDefaultTextStyle(
                              duration: animate
                                  ? AppMotion.toggle
                                  : Duration.zero,
                              curve: AppMotion.curve,
                              style: TextStyle(
                                fontFamily: appHeadingFontFamily,
                                fontSize: fontSize,
                                fontWeight: FontWeight.w700,
                                color: i == index
                                    ? selectedTextColor
                                    : unselectedTextColor,
                              ),
                              child: Text(
                                labels[i],
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.fade,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The header of the four main pages, with the same size and positions
/// on every page:
///
///   [ soft community scenery band ]   (Home: 📍 Barangay / City on it)
///   eyebrow                           (greeting, report count, ...)
///   Title                             (name, or the page title)
///   Description                       mascot on the right
///
/// Every element has a fixed slot, so switching pages never moves,
/// resizes or re-spaces anything, whatever the text lengths.
class CitiPageHeader extends StatelessWidget {
  const CitiPageHeader({
    super.key,
    required this.title,
    required this.description,
    required this.mascot,
    this.eyebrow,
    this.barangayName,
  });

  /// Shown on Home only (with "Cebu City"); null on other pages.
  final String? barangayName;
  final String? eyebrow;
  final String title;
  final String description;
  final Widget mascot;

  /// Height of the scenery band at the top.
  static const double bandHeight = 58;

  /// Height of the eyebrow / title / description area.
  static const double heroHeight = 186;

  /// The page's top padding, which the scenery also fills.
  static const double topPadding = 24;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // Same fractions Home always used (of the full page width).
        final pageWidth = width + 40;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: bandHeight,
              width: double.infinity,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Edge to edge, from the very top of the page.
                  const Positioned(
                    left: -20,
                    right: -20,
                    top: -topPadding,
                    bottom: -14,
                    child: IgnorePointer(child: CommunityScenery()),
                  ),
                  if (barangayName != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _LocationLabel(barangayName: barangayName!),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: heroHeight,
              width: double.infinity,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    top: 10,
                    right: 0,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // The slot is kept even without an eyebrow, so the
                        // title sits at the same height on every page.
                        Text(
                          eyebrow ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                            fontFamily: appFontFamily,
                          ),
                        ),
                        const SizedBox(height: 1),
                        SizedBox(
                          width: pageWidth * .55,
                          height: 46,
                          // Long titles shrink to fit their slot instead of
                          // pushing the description down.
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              title,
                              maxLines: 1,
                              softWrap: false,
                              style: const TextStyle(
                                fontSize: 41,
                                height: 1.12,
                                fontWeight: FontWeight.w900,
                                color: AppColors.ink,
                                fontFamily: appHeadingFontFamily,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 11),
                        SizedBox(
                          width: pageWidth * .46,
                          child: Text(
                            description,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.55,
                              color: AppColors.textSecondary,
                              fontFamily: appFontFamily,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    right: -10,
                    bottom: -4,
                    child: SizedBox(
                      width: pageWidth * .40,
                      height: 184,
                      child: mascot,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 📍 Barangay … / Cebu City (Home only). The barangay name is a little
/// larger than the city.
class _LocationLabel extends StatelessWidget {
  const _LocationLabel({required this.barangayName});

  final String barangayName;

  @override
  Widget build(BuildContext context) {
    // A soft frosted tag, so the text stays readable over the scenery.
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 5, 12, 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.location_on, color: AppColors.primary, size: 26),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  barangayName.isNotEmpty
                      ? 'Barangay $barangayName'
                      : 'Your Barangay',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                    fontFamily: appHeadingFontFamily,
                  ),
                ),
                const Text(
                  'Cebu City',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.3,
                    color: AppColors.textSecondary,
                    fontFamily: appFontFamily,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A soft, light illustration of a barangay: sky, sun, clouds, hills,
/// houses, trees and the barangay hall with its flag. It fades into the
/// page background at the bottom so it never competes with the title.
class CommunityScenery extends StatelessWidget {
  const CommunityScenery({super.key});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      // Fade out at the bottom so the scene blends into the page.
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.white, Colors.white, Colors.transparent],
        stops: [0, 0.62, 1],
      ).createShader(rect),
      blendMode: BlendMode.dstIn,
      child: CustomPaint(painter: _SceneryPainter(), size: Size.infinite),
    );
  }
}

class _SceneryPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final ground = h * 0.80;

    // Sky.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFDCE8FD), Color(0xFFEEF3FD)],
        ).createShader(Offset.zero & size),
    );

    // Sun with a soft glow.
    final sun = Offset(w * 0.64, h * 0.26);
    canvas.drawCircle(
      sun,
      h * 0.20,
      Paint()..color = const Color(0xFFFFE9A8).withValues(alpha: 0.45),
    );
    canvas.drawCircle(
      sun,
      h * 0.12,
      Paint()..color = const Color(0xFFFFE08A).withValues(alpha: 0.85),
    );

    // Clouds.
    final cloud = Paint()..color = Colors.white.withValues(alpha: 0.9);
    void drawCloud(double cx, double cy, double s) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(cx, cy),
            width: 46 * s,
            height: 13 * s,
          ),
          Radius.circular(7 * s),
        ),
        cloud,
      );
      canvas.drawCircle(Offset(cx - 6 * s, cy - 5 * s), 8 * s, cloud);
      canvas.drawCircle(Offset(cx + 7 * s, cy - 4 * s), 6 * s, cloud);
    }

    drawCloud(w * 0.50, h * 0.22, 0.9);
    drawCloud(w * 0.88, h * 0.20, 1.0);
    drawCloud(w * 0.10, h * 0.30, 0.8);

    // Birds.
    final bird = Paint()
      ..color = const Color(0xFF9DB3DA)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    for (final p in [Offset(w * 0.40, h * 0.34), Offset(w * 0.45, h * 0.40)]) {
      final path = Path()
        ..moveTo(p.dx - 5, p.dy)
        ..quadraticBezierTo(p.dx - 2.5, p.dy - 3, p.dx, p.dy)
        ..quadraticBezierTo(p.dx + 2.5, p.dy - 3, p.dx + 5, p.dy);
      canvas.drawPath(path, bird);
    }

    // Rolling hills.
    final hills = Path()
      ..moveTo(0, ground)
      ..quadraticBezierTo(
        w * 0.18,
        ground - h * 0.20,
        w * 0.38,
        ground - h * 0.04,
      )
      ..quadraticBezierTo(
        w * 0.62,
        ground - h * 0.22,
        w * 0.82,
        ground - h * 0.05,
      )
      ..quadraticBezierTo(w * 0.93, ground - h * 0.12, w, ground - h * 0.06)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(hills, Paint()..color = const Color(0xFFD9E6F7));

    final houseBody = Paint()..color = const Color(0xFFC3D3EE);
    final roof = Paint()..color = const Color(0xFFA9BEE4);
    final tree = Paint()..color = const Color(0xFFC6E3CC);
    final trunk = Paint()..color = const Color(0xFFB9C9DE);

    void drawHouse(double x, double s) {
      final bw = 18 * s;
      final bh = 11 * s;
      canvas.drawRect(Rect.fromLTWH(x, ground - bh, bw, bh), houseBody);
      final r = Path()
        ..moveTo(x - 3 * s, ground - bh)
        ..lineTo(x + bw / 2, ground - bh - 9 * s)
        ..lineTo(x + bw + 3 * s, ground - bh)
        ..close();
      canvas.drawPath(r, roof);
    }

    void drawTree(double x, double s) {
      canvas.drawRect(
        Rect.fromLTWH(x - 1.2 * s, ground - 9 * s, 2.4 * s, 9 * s),
        trunk,
      );
      canvas.drawCircle(Offset(x, ground - 12 * s), 6.5 * s, tree);
    }

    // Houses and trees along the street.
    drawTree(w * 0.05, 1.0);
    drawHouse(w * 0.09, 1.0);
    drawHouse(w * 0.19, 0.85);
    drawTree(w * 0.30, 0.9);
    drawHouse(w * 0.36, 1.1);
    drawTree(w * 0.50, 1.0);
    drawHouse(w * 0.55, 0.9);
    drawTree(w * 0.96, 0.9);

    // Barangay hall with columns and a flag.
    final hallX = w * 0.70;
    final hallW = w * 0.16;
    const hallH = 16.0;
    canvas.drawRect(
      Rect.fromLTWH(hallX, ground - hallH, hallW, hallH),
      houseBody,
    );
    final col = Paint()..color = const Color(0xFFEAF0FB);
    for (var i = 1; i < 5; i++) {
      canvas.drawRect(
        Rect.fromLTWH(
          hallX + hallW * i / 5 - 1.5,
          ground - hallH + 4,
          3,
          hallH - 4,
        ),
        col,
      );
    }
    final hallRoof = Path()
      ..moveTo(hallX - 5, ground - hallH)
      ..lineTo(hallX + hallW / 2, ground - hallH - 12)
      ..lineTo(hallX + hallW + 5, ground - hallH)
      ..close();
    canvas.drawPath(hallRoof, roof);
    final poleX = hallX + hallW / 2;
    canvas.drawLine(
      Offset(poleX, ground - hallH - 12),
      Offset(poleX, ground - hallH - 28),
      Paint()
        ..color = const Color(0xFF9DB3DA)
        ..strokeWidth = 1.4,
    );
    final flag = Path()
      ..moveTo(poleX, ground - hallH - 28)
      ..lineTo(poleX + 11, ground - hallH - 24.5)
      ..lineTo(poleX, ground - hallH - 21)
      ..close();
    canvas.drawPath(flag, Paint()..color = const Color(0xFF8FA9F0));
  }

  @override
  bool shouldRepaint(_SceneryPainter oldDelegate) => false;
}
