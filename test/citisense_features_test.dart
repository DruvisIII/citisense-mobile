import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:citisense/announcement_details_page.dart';
import 'package:citisense/api_client.dart';
import 'package:citisense/app_settings.dart';
import 'package:citisense/app_theme.dart';
import 'package:citisense/auth_session.dart';
import 'package:citisense/barangay_messages_page.dart';
import 'package:citisense/createAccount.dart';
import 'package:citisense/friendly_errors.dart';
import 'package:citisense/home.dart';
import 'package:citisense/live_updates.dart';
import 'package:citisense/login.dart';
import 'package:citisense/report_issue_overlay.dart';
import 'package:citisense/settings_page.dart';
import 'package:citisense/validators.dart';

/// Wraps a screen like the real app does (theme + font scale).
Widget app(Widget home, {double scale = 1.0}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: home,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
  );
}

Future<void> setPhone(WidgetTester tester, {double width = 390}) async {
  tester.view.physicalSize = Size(width * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

http.Response json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthSession.start('a' * 64);
    appFontScale.value = 1.0;
  });

  // ----------------------------------------------------------
  // 1. Philippine phone numbers
  // ----------------------------------------------------------
  group('PhilippinePhone', () {
    test('accepts 10 digits starting with 9', () {
      expect(PhilippinePhone.isValid('9171234567'), isTrue);
      expect(PhilippinePhone.toStored('9171234567'), '09171234567');
    });

    test('rejects wrong start or length', () {
      expect(PhilippinePhone.isValid('8171234567'), isFalse);
      expect(PhilippinePhone.isValid('917123456'), isFalse);
      expect(PhilippinePhone.error('8171'), contains('start with 9'));
      expect(PhilippinePhone.error('91712'), contains('10 digits'));
      expect(PhilippinePhone.error(''), isNull);
      expect(PhilippinePhone.error('', showEmpty: true), isNotNull);
    });

    test('reads stored and pasted formats', () {
      expect(PhilippinePhone.localPart('09171234567'), '9171234567');
      expect(PhilippinePhone.localPart('+63 917 123 4567'), '9171234567');
      expect(PhilippinePhone.localPart('639171234567'), '9171234567');
    });
  });

  // ----------------------------------------------------------
  // 2. Passwords
  // ----------------------------------------------------------
  group('PasswordRules', () {
    test('minimum 6, keyboard characters only', () {
      expect(PasswordRules.error('abc12'), contains('at least 6'));
      expect(PasswordRules.isValid('abc123'), isTrue);
      expect(PasswordRules.isValid(r'P@ss!#$%^&*()'), isTrue);
      expect(PasswordRules.error('pass word'), contains('no spaces'));
      expect(PasswordRules.error('pässword'), isNotNull);
      expect(PasswordRules.error('pass😀word'), isNotNull);
      expect(PasswordRules.error('a' * 73), contains('at most'));
    });
  });

  // ----------------------------------------------------------
  // 4. Friendly errors
  // ----------------------------------------------------------
  group('FriendlyErrors', () {
    test('hides technical messages', () {
      expect(
        FriendlyErrors.fromMessage('Network request failed'),
        FriendlyErrors.noConnection,
      );
      expect(
        FriendlyErrors.fromMessage('Invalid credentials'),
        FriendlyErrors.wrongLogin,
      );
      expect(FriendlyErrors.fromMessage('Server error'), FriendlyErrors.server);
      expect(
        FriendlyErrors.fromMessage('Request timeout'),
        FriendlyErrors.timeout,
      );
      expect(
        FriendlyErrors.fromMessage('Validation failed'),
        FriendlyErrors.invalidInput,
      );
      expect(
        FriendlyErrors.fromMessage("mysqli_sql_exception: Unknown column 'x'"),
        FriendlyErrors.server,
      );
      expect(
        FriendlyErrors.fromMessage('Please write your feedback first.'),
        'Please write your feedback first.',
      );
    });

    test('server error pages become a plain message', () {
      final r = http.Response('<html>Bad Gateway</html>', 502);
      expect(FriendlyErrors.fromResponse(r), FriendlyErrors.server);
    });
  });

  // ----------------------------------------------------------
  // 9B. Timestamps
  // ----------------------------------------------------------
  group('Timestamps', () {
    test('a UTC time from the server is not "8 hours ago"', () {
      final now = DateTime.now();
      final iso = now.toUtc().toIso8601String().replaceFirst(
        RegExp(r'\.\d+Z$'),
        '+00:00',
      );
      expect(relativeTime(parseApiTime(iso), now: now), 'Just now');
    });

    test('relative labels', () {
      final now = DateTime(2026, 11, 23, 18, 0);
      expect(
        relativeTime(now.subtract(const Duration(minutes: 5)), now: now),
        '5 minutes ago',
      );
      expect(
        relativeTime(now.subtract(const Duration(hours: 2)), now: now),
        '2 hours ago',
      );
      expect(relativeTime(DateTime(2026, 11, 22, 9), now: now), 'Yesterday');
      expect(relativeTime(DateTime(2026, 11, 1, 9), now: now), 'Nov 1, 2026');
    });
  });

  // ----------------------------------------------------------
  // 1 + 2. Create Account form
  // ----------------------------------------------------------
  testWidgets('Create Account: +63 field filters input and shows errors', (
    tester,
  ) async {
    await setPhone(tester);
    await tester.pumpWidget(app(const CreateAccount()));

    expect(find.text('+63'), findsOneWidget);

    final phone = find.widgetWithText(TextField, '9XX XXX XXXX');
    await tester.enterText(phone, 'abc09171234567😀');
    await tester.pump();
    expect(
      tester.widget<TextField>(phone).controller!.text,
      '9171234567',
      reason: 'letters/emoji removed, pasted 0 prefix trimmed',
    );

    await tester.enterText(phone, '8171');
    await tester.pump();
    expect(find.textContaining('start with 9'), findsOneWidget);

    final password = find.widgetWithText(TextField, 'At least 6 characters');
    await tester.enterText(password, 'abc');
    await tester.pump();
    expect(
      find.text('Password must be at least 6 characters.'),
      findsOneWidget,
    );

    await tester.enterText(password, 'abc😀12');
    await tester.pump();
    expect(find.textContaining('no spaces or emojis'), findsOneWidget);

    await tester.enterText(password, 'abc123');
    await tester.pump();
    expect(find.textContaining('at least 6'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // ----------------------------------------------------------
  // 3. Login "Sign Up" opens Create Account
  // ----------------------------------------------------------
  testWidgets('Login: Sign Up opens Create Account', (tester) async {
    await setPhone(tester);
    await tester.pumpWidget(app(const LoginPage()));
    await tester.pump(const Duration(seconds: 1));

    await tester.ensureVisible(find.text('Sign Up'));
    await tester.tap(find.text('Sign Up'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(CreateAccount), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);
  });

  // ----------------------------------------------------------
  // 12. Login and Create Account fit a small phone at Large text
  // ----------------------------------------------------------
  for (final page in <Widget>[const LoginPage(), const CreateAccount()]) {
    testWidgets('${page.runtimeType} has no overflow at Large on 360px', (
      tester,
    ) async {
      await setPhone(tester, width: 360);
      await tester.pumpWidget(app(page, scale: 1.2));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });
  }

  // ----------------------------------------------------------
  // 5A + 12. Home: announcement cards with and without pictures
  // ----------------------------------------------------------
  for (final scale in [1.0, 1.2]) {
    testWidgets('Home announcement cards lay out at scale $scale', (
      tester,
    ) async {
      await setPhone(tester, width: 360);
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            app(
              const HomePage(
                userID: 'USR001',
                firstName: 'Juan',
                lastName: 'Dela Cruz',
                email: 'juan@x.ph',
                contactNo: '09171234567',
                barangayID: 'B1',
              ),
              scale: scale,
            ),
          );
          await tester.pump(const Duration(milliseconds: 500));

          await tester.scrollUntilVisible(
            find.text('Water interruption'),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          expect(find.text('Message your barangay'), findsOneWidget);
          expect(find.text('Clean-up drive'), findsOneWidget);
          expect(find.text('2 comments'), findsOneWidget);
          expect(find.text('+1'), findsOneWidget);
          // The card without pictures shows the barangay icon instead.
          expect(find.byIcon(Icons.account_balance), findsWidgets);
          expect(tester.takeException(), isNull);
        },
        () => MockClient((request) async {
          if (request.url.path.endsWith('get_announcements.php')) {
            return json({
              'success': true,
              'data': [
                {
                  'announceID': 1,
                  'title': 'Clean-up drive',
                  'content': 'Saturday 7am at the plaza. ' * 6,
                  'datePosted': DateTime.now().toUtc().toIso8601String(),
                  'commentCount': 2,
                  'images': [
                    'https://example.com/a.jpg',
                    'https://example.com/b.jpg',
                  ],
                },
                {
                  'announceID': 2,
                  'title': 'Water interruption',
                  'content': 'No water from 1 to 5 PM.',
                  'datePosted': '2026-11-20T02:00:00+00:00',
                  'commentCount': 0,
                  'images': <String>[],
                },
              ],
            });
          }
          return json({'success': true, 'data': {}});
        }),
      );
      await tester.pumpWidget(const SizedBox());
      LiveUpdates.instance.stop();
      await tester.pump(const Duration(seconds: 1));
    });
  }

  // ----------------------------------------------------------
  // 10. Settings font size at Large
  // ----------------------------------------------------------
  for (final scale in [0.8, 1.0, 1.2]) {
    testWidgets('Settings: "Font Size" stays on one line at scale $scale', (
      tester,
    ) async {
      await setPhone(tester, width: 360);
      await http.runWithClient(() async {
        await tester.pumpWidget(
          app(
            const SettingsPage(
              userID: 'USR001',
              firstName: 'Juan',
              lastName: 'Dela Cruz',
              email: 'juan@x.ph',
              contactNo: '09171234567',
              barangayID: 'B1',
            ),
            scale: scale,
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        await tester.scrollUntilVisible(
          find.text('Font Size'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        final title = tester.getSize(find.text('Font Size'));
        final subtitle = tester.getSize(
          find.text('Adjust the text size in the app.'),
        );
        // One line of 16px text (times the scale) is well under 30px.
        expect(title.height, lessThan(30 * scale));
        expect(title.width, greaterThan(60));
        // Wraps by words at most, never letter by letter.
        expect(subtitle.width, greaterThan(150));
        expect(find.text('Large'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }, () => MockClient((_) async => json({'success': true, 'data': {}})));
    });
  }

  // ----------------------------------------------------------
  // 6. Report overlay header at different sizes
  // ----------------------------------------------------------
  for (final scale in [1.0, 1.2]) {
    testWidgets('Report overlay lays out without overflow at scale $scale', (
      tester,
    ) async {
      await setPhone(tester, width: 360);
      await tester.pumpWidget(
        app(
          const Scaffold(
            body: ReportIssueOverlay(userID: 'USR001', barangayID: 'B1'),
          ),
          scale: scale,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Report an Issue'), findsOneWidget);
      expect(
        find.text('Help us keep our community safe and clean!'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  // ----------------------------------------------------------
  // 5. Announcement details + comments
  // ----------------------------------------------------------
  testWidgets('Announcement: details, admin comment badge, posting', (
    tester,
  ) async {
    await setPhone(tester);
    final comments = <Map<String, dynamic>>[
      {
        'id': 1,
        'fromBarangay': false,
        'isMine': false,
        'name': 'Ana Reyes',
        'message': 'Will there be gloves?',
        'hidden': false,
        'replyToName': null,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      },
      {
        'id': 2,
        'parentID': 1,
        'fromBarangay': true,
        'isMine': false,
        'name': 'Maria Santos',
        'message': 'Yes, gloves provided.',
        'hidden': false,
        'replyToName': 'Ana Reyes',
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      },
    ];
    final requests = <http.Request>[];

    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          app(
            const AnnouncementDetailsPage(
              userID: 'USR001',
              announcement: {
                'announceID': 7,
                'title': 'Clean-up drive',
                'content': 'Saturday 7am at the plaza.',
                'barangayName': 'Lahug',
                'postedBy': 'Maria Santos',
                'datePosted': '2026-11-23T10:00:00+00:00',
                'images': <String>[],
              },
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Clean-up drive'), findsOneWidget);
        expect(find.text('Posted by Maria Santos'), findsOneWidget);
        expect(find.textContaining('November 23, 2026'), findsOneWidget);

        await tester.scrollUntilVisible(
          find.text('Yes, gloves provided.'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Barangay'), findsOneWidget);
        expect(find.text('Replying to Ana Reyes'), findsOneWidget);

        await tester.enterText(
          find.widgetWithText(TextField, 'Write a comment…'),
          'Thank you po!',
        );
        await tester.pump();
        await tester.tap(find.byTooltip('Post comment'));
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Thank you po!'), findsOneWidget);
        expect(find.text('Juan Dela Cruz (You)'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      () => MockClient((request) async {
        requests.add(request);
        expect(request.headers['X-Auth-Token'], 'a' * 64);
        final fields = Uri.splitQueryString(request.body);
        if (fields['action'] == 'add') {
          comments.add({
            'id': 3,
            'fromBarangay': false,
            'isMine': true,
            'name': 'Juan Dela Cruz',
            'message': fields['message'],
            'hidden': false,
            'replyToName': null,
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          });
        }
        return json({'success': true, 'data': comments});
      }),
    );

    expect(
      requests.any((r) => r.url.path.endsWith('announcement_comments.php')),
      isTrue,
    );
  });

  // ----------------------------------------------------------
  // 8. Messages with the barangay
  // ----------------------------------------------------------
  testWidgets('Messages: shows barangay replies and sends a message', (
    tester,
  ) async {
    await setPhone(tester);
    final messages = <Map<String, dynamic>>[
      {
        'id': 1,
        'fromBarangay': true,
        'name': 'Maria Santos',
        'message': 'Hello! How can we help?',
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      },
    ];

    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          app(const BarangayMessagesPage(userID: 'USR001')),
        );
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Barangay Lahug'), findsOneWidget);
        expect(find.text('Hello! How can we help?'), findsOneWidget);
        expect(find.text('Maria Santos'), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'May baha po sa amin.');
        await tester.pump();
        await tester.tap(find.byTooltip('Send'));
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('May baha po sa amin.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      () => MockClient((request) async {
        final fields = Uri.splitQueryString(request.body);
        if (fields['action'] == 'send') {
          messages.add({
            'id': 2,
            'fromBarangay': false,
            'name': 'You',
            'message': fields['message'],
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          });
        }
        return json({
          'success': true,
          'barangayName': 'Lahug',
          'data': messages,
        });
      }),
    );

    // Stop the 10-second refresh timer.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Messages: ask about a report, reply, delete own message', (
    tester,
  ) async {
    await setPhone(tester);
    final now = DateTime.now().toUtc().toIso8601String();
    final messages = <Map<String, dynamic>>[
      {
        'key': 'r1',
        'fromBarangay': true,
        'canDelete': false,
        'name': 'Maria Santos',
        'message': 'We will check REP055 today 😊',
        'reportID': 'REP055',
        'reportLabel': 'REP055 · Waste Accumulation',
        'replyTo': null,
        'createdAt': now,
      },
    ];
    final sent = <Map<String, String>>[];

    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          app(const BarangayMessagesPage(userID: 'USR001')),
        );
        await tester.pump(const Duration(milliseconds: 300));

        // The report the message is about is shown on the message.
        expect(find.text('REP055 · Waste Accumulation'), findsOneWidget);
        expect(find.text('General message'), findsOneWidget);
        // The barangay's message cannot be deleted.
        expect(find.text('Delete'), findsNothing);

        // Reply to the barangay's message.
        await tester.tap(find.text('Reply'));
        await tester.pump();
        expect(find.text('Replying to Maria Santos'), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'Salamat po! 🙏');
        await tester.pump();
        await tester.tap(find.byTooltip('Send'));
        await tester.pump(const Duration(milliseconds: 300));

        expect(sent.last['replyTo'], 'r1');
        // A reply stays with the report of the message it answers.
        expect(sent.last['reportID'], 'REP055');
        expect(find.text('Salamat po! 🙏'), findsOneWidget);
        expect(
          find.text('Replying to Maria Santos · Barangay'),
          findsOneWidget,
        );

        // Delete my own message (only mine has Delete).
        expect(find.text('Delete'), findsOneWidget);
        await tester.tap(find.text('Delete'));
        await tester.pump();
        await tester.tap(find.widgetWithText(TextButton, 'Delete'));
        await tester.pump(const Duration(milliseconds: 300));

        expect(sent.last['action'], 'delete');
        expect(sent.last['key'], 'r2');
        expect(find.text('Salamat po! 🙏'), findsNothing);
        expect(tester.takeException(), isNull);
      },
      () => MockClient((request) async {
        final fields = Uri.splitQueryString(request.body);
        if (fields['action'] != 'list') sent.add(fields);
        if (fields['action'] == 'send') {
          messages.add({
            'key': 'r2',
            'fromBarangay': false,
            'canDelete': true,
            'name': 'You',
            'message': fields['message'],
            'reportID': fields['reportID'] ?? '',
            'reportLabel': 'REP055 · Waste Accumulation',
            'replyTo': {
              'key': 'r1',
              'name': 'Maria Santos · Barangay',
              'text': 'We will check REP055 today 😊',
              'missing': false,
            },
            'createdAt': now,
          });
        }
        if (fields['action'] == 'delete') {
          messages.removeWhere((m) => m['key'] == fields['key']);
        }
        return json({
          'success': true,
          'barangayName': 'Lahug',
          'data': messages,
          'reports': [
            {
              'reportID': 'REP055',
              'categoryName': 'Waste Accumulation',
              'statusName': 'Resolved',
              'imagePath': '',
              'dateReported': now,
            },
          ],
        });
      }),
    );

    await tester.pumpWidget(const SizedBox());
  });

  // ----------------------------------------------------------
  // 11. App feedback
  // ----------------------------------------------------------
  testWidgets('Feedback: validates, reports failure, then succeeds', (
    tester,
  ) async {
    await setPhone(tester);
    var emailWorks = false;
    var calls = 0;

    await http.runWithClient(
      () async {
        await tester.pumpWidget(app(const AppFeedbackPage(userID: 'USR001')));
        await tester.pump();

        await tester.tap(find.text('Send Feedback'));
        await tester.pump();
        expect(find.text('Choose the type of feedback.'), findsOneWidget);
        expect(find.text('Please write your feedback.'), findsOneWidget);
        expect(calls, 0, reason: 'nothing is sent when invalid');

        await tester.tap(find.text('Suggestion'));
        await tester.enterText(find.byType(TextField), 'Please add dark mode.');
        await tester.pump();

        await tester.tap(find.text('Send Feedback'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          find.text(
            'We could not send your feedback right now. '
            'Please try again in a few minutes.',
          ),
          findsOneWidget,
        );
        expect(find.text('Thank you!'), findsNothing);

        emailWorks = true;
        await tester.tap(find.text('Send Feedback'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Thank you!'), findsOneWidget);
        expect(calls, 2);
      },
      () => MockClient((request) async {
        calls++;
        return emailWorks
            ? json({'success': true, 'message': 'Thank you!'})
            : json({
                'success': false,
                'message':
                    'We could not send your feedback right now. '
                    'Please try again in a few minutes.',
              }, 502);
      }),
    );
  });
}
