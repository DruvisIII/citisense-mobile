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

  /// Toggles, their indicator, and the content they switch.
  static const Duration toggle = Duration(milliseconds: 260);
  static const Curve curve = Curves.easeOutCubic;

  /// Fade between the old and the new content of a toggle.
  static Widget fadeSwitcher({
    required Object contentKey,
    required Widget child,
  }) {
    return AnimatedSwitcher(
      duration: toggle,
      switchInCurve: curve,
      switchOutCurve: Curves.easeInCubic,
      // Keep the new content at the top while the old one fades out, so
      // the page does not jump when the lists have different lengths.
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.015),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
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
  });

  /// Settings style: light grey track, white indicator.
  const SlidingToggle.subtle({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
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
                duration: AppMotion.toggle,
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
                              duration: AppMotion.toggle,
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

/// The header of the four main pages (Home is the reference):
///
///   📍 Barangay …          (same on every page)
///      Cebu City
///   eyebrow                 (greeting on Home / My Reports)
///   Title                   (name, or the page title)
///   Description             mascot on the right
///
/// Every element has a fixed slot, so switching pages never moves,
/// resizes or re-spaces anything, whatever the text lengths.
class CitiPageHeader extends StatelessWidget {
  const CitiPageHeader({
    super.key,
    required this.barangayName,
    required this.title,
    required this.description,
    required this.mascot,
    this.eyebrow,
  });

  final String barangayName;
  final String? eyebrow;
  final String title;
  final String description;
  final Widget mascot;

  /// Height of the greeting / title / description area.
  static const double heroHeight = 190;

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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.location_on,
                  color: AppColors.primary,
                  size: 32,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        barangayName.isNotEmpty
                            ? 'Barangay $barangayName'
                            : 'Your Barangay',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                          fontFamily: appHeadingFontFamily,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Cebu City',
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                          fontFamily: appFontFamily,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            SizedBox(
              height: heroHeight,
              width: double.infinity,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    top: 12,
                    right: 0,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // The slot is kept even without an eyebrow, so the
                        // title sits at the same height on every page.
                        Text(
                          eyebrow ?? '',
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                            fontFamily: appFontFamily,
                          ),
                        ),
                        const SizedBox(height: 1),
                        SizedBox(
                          width: pageWidth * .53,
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
                        const SizedBox(height: 13),
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
                      height: 188,
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
