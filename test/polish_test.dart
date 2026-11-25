import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:citisense/api_client.dart';
import 'package:citisense/app_theme.dart';
import 'package:citisense/my_reports.dart';
import 'package:citisense/notification_router.dart';
import 'package:citisense/ui_components.dart';

// Timestamps, toggle animation, and "announcement updated" pushes.

void main() {
  tearDown(ServerClock.reset);

  group('report card information', () {
    test('short location from a full address', () {
      expect(
        shortReportAddress(
          'To-ong Pardo, 7VQ8+JMW To-ong Pardo, Cebu City, '
          'Central Visayas, Philippines',
        ),
        'To-ong Pardo, Cebu City',
      );
      expect(
        shortReportAddress('Sanciangko St, Cebu City'),
        'Sanciangko St, Cebu City',
      );
      expect(shortReportAddress(''), 'Location unavailable');
    });

    test('category: own icon and color, no "Report" in the name', () {
      final waste = ReportCategoryStyle.of({
        'categoryName': 'Waste Accumulation',
      });
      final pothole = ReportCategoryStyle.of({'categoryName': 'Pothole'});
      final other = ReportCategoryStyle.of({'categoryName': 'Others'});

      expect(waste.label, 'Waste Accumulation');
      expect(pothole.label, 'Pothole');
      expect(other.label, 'Other Issue');
      expect({waste.color, pothole.color, other.color}.length, 3);
      expect({waste.icon, pothole.icon, other.icon}.length, 3);
    });

    test('status labels follow the current status', () {
      expect(reportStatusOf({'statusID': 'STAT001'}).label, 'Pending');
      expect(reportStatusOf({'statusID': 'STAT002'}).label, 'Ongoing');
      expect(reportStatusOf({'statusID': 'STAT003'}).label, 'Resolved');
    });
  });

  testWidgets('Font Size toggle moves at once (no animation)', (tester) async {
    var selected = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SlidingToggle.subtle(
              animate: false,
              labels: const ['Small', 'Medium', 'Large'],
              selectedIndex: selected,
              onChanged: (i) => setState(() => selected = i),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Large'));
    await tester.pump();
    final positioned = tester.widget<AnimatedPositioned>(
      find.byType(AnimatedPositioned),
    );
    expect(positioned.duration, Duration.zero);
    expect(selected, 2);
  });

  group('relativeTime', () {
    final now = DateTime(2026, 11, 25, 0, 30); // just after midnight

    String ago(Duration d) => relativeTime(now.subtract(d), now: now);

    test('minutes and hours, never "Yesterday" under a day', () {
      expect(ago(const Duration(seconds: 20)), 'Just now');
      expect(ago(const Duration(minutes: 42)), '42 minutes ago');
      // 11:20 PM yesterday, 70 minutes ago: not "Yesterday".
      expect(ago(const Duration(minutes: 70)), '1 hour ago');
      expect(ago(const Duration(hours: 23)), '23 hours ago');
      // 11:30 PM on Nov 23 is two calendar days back.
      expect(ago(const Duration(hours: 25)), '2 days ago');
      expect(ago(const Duration(days: 3)), '3 days ago');

      final evening = DateTime(2026, 11, 25, 20, 0);
      expect(
        relativeTime(evening.subtract(const Duration(hours: 26)), now: evening),
        'Yesterday',
      );
    });

    test('a time slightly in the future is "Just now"', () {
      expect(ago(const Duration(seconds: -30)), 'Just now');
    });

    test('ages are measured on the server clock', () {
      // The phone's clock is 8 hours ahead of the server.
      final serverNow = DateTime.now().toUtc().subtract(
        const Duration(hours: 8),
      );
      ServerClock.syncFromBody({'serverTime': serverNow.toIso8601String()});

      final sentFiveMinutesAgo = serverNow.subtract(const Duration(minutes: 5));
      expect(relativeTime(sentFiveMinutesAgo), '5 minutes ago');
    });
  });

  test('"Announcement updated" push opens that announcement', () {
    final target = NotificationTarget.fromPushData({
      'type': 'announcement_updated',
      'announceID': '12',
    });
    expect(target?.type, NotificationTargetType.announcement);
    expect(target?.id, '12');
  });

  testWidgets('SlidingToggle slides its indicator instead of jumping', (
    tester,
  ) async {
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 314,
              child: StatefulBuilder(
                builder: (context, setState) => SlidingToggle(
                  labels: const ['All Reports', 'Ongoing', 'Completed'],
                  selectedIndex: selected,
                  onChanged: (i) => setState(() => selected = i),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    double indicatorLeft() => tester
        .widget<AnimatedPositioned>(find.byType(AnimatedPositioned))
        .left!;
    double renderedLeft() =>
        tester.getTopLeft(find.byType(DecoratedBox).last).dx;

    final start = renderedLeft();
    await tester.tap(find.text('Completed'));
    await tester.pump();
    expect(selected, 2);
    expect(indicatorLeft(), greaterThan(0));

    await tester.pump(AppMotion.toggle ~/ 2);
    final middle = renderedLeft();
    await tester.pump(AppMotion.toggle);
    final end = renderedLeft();

    expect(middle, greaterThan(start));
    expect(middle, lessThan(end));
  });
}

// ------------------------------------------------------------------
// Report cards, headers and Font Size (items 19-24)
// ------------------------------------------------------------------
