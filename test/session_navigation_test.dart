import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:citisense/app_theme.dart';
import 'package:citisense/auth_session.dart';
import 'package:citisense/createAccount.dart';
import 'package:citisense/home.dart';
import 'package:citisense/landing.dart';
import 'package:citisense/live_updates.dart';
import 'package:citisense/login.dart';
import 'package:citisense/main.dart';
import 'package:citisense/session_manager.dart';

// Stay logged in, back button on Home, Log Out, centered links.

const _token =
    'b1b2b3b4b5b6b7b8b9b0b1b2b3b4b5b6b7b8b9b0b1b2b3b4b5b6b7b8b9b0b1b2';

const _user = {
  'userID': 'USR001',
  'firstName': 'Jannah',
  'lastName': 'Gargar',
  'email': 'j@example.com',
  'contactNo': '09171234567',
  'profilePic': null,
  'barangayID': 'B1',
};

Widget realApp() => MaterialApp(
  theme: AppTheme.light,
  navigatorKey: appNavigatorKey,
  home: const StartupPage(),
);

http.Response json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// The API as seen by Home and its tabs.
Future<http.Response> fakeApi(
  http.Request request, {
  bool sessionValid = true,
  List<String>? calls,
}) async {
  final path = request.url.path;
  calls?.add(
    '${path.split('/').last} ${Uri.splitQueryString(request.body)['action'] ?? ''}'
        .trim(),
  );
  if (path.endsWith('session.php')) {
    final action = Uri.splitQueryString(request.body)['action'];
    if (action == 'logout') return json({'success': true, 'message': 'ok'});
    return sessionValid
        ? json({'success': true, 'user': _user})
        : json({
            'success': false,
            'code': 'SESSION_EXPIRED',
            'message': 'expired',
          }, 401);
  }
  if (path.endsWith('get_barangays.php')) {
    return json({
      'success': true,
      'data': [
        {'barangayID': 'B1', 'barangayName': 'Duljo-Fatima'},
      ],
    });
  }
  if (path.endsWith('get_profile.php')) {
    return json({
      'success': true,
      'data': {..._user, 'barangayName': 'Duljo-Fatima'},
    });
  }
  return json({'success': true, 'data': []});
}

// Tall and wide: the test font draws every letter as a wide square.
Future<void> setPhone(WidgetTester tester, {double width = 390}) async {
  tester.view.physicalSize = Size(width * 3, 1100 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    AuthSession.start(null);
  });

  testWidgets('No saved session: the app opens the welcome page', (
    tester,
  ) async {
    await setPhone(tester);
    await http.runWithClient(() async {
      await tester.pumpWidget(realApp());
      await tester.pumpAndSettle();
      expect(find.byType(LandingPage), findsOneWidget);
      expect(find.byType(HomePage), findsNothing);
    }, () => MockClient((r) => fakeApi(r)));
  });

  testWidgets('Saved session: reopening the app goes straight to Home, '
      'and Back on Home never shows Log In', (tester) async {
    await setPhone(tester);
    FlutterSecureStorage.setMockInitialValues({
      'citisense_session_token': _token,
      'citisense_session_user': jsonEncode(_user),
    });

    await http.runWithClient(() async {
      await tester.pumpWidget(realApp());
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(HomePage), findsOneWidget);
      expect(AuthSession.token, _token);

      // Home is the only page: nothing to go back to.
      expect(appNavigatorKey.currentState!.canPop(), isFalse);

      // From another tab, Back returns to the Home tab first.
      await tester.tap(find.text('Settings'));
      await tester.pump(const Duration(milliseconds: 300));
      await appNavigatorKey.currentState!.maybePop();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(HomePage), findsOneWidget);
      expect(find.byType(LoginPage), findsNothing);
      expect(find.text('Report an Issue'), findsOneWidget);

      // Still logged in.
      expect(AuthSession.isLoggedIn, isTrue);
    }, () => MockClient((r) => fakeApi(r)));

    // Stop the 20-second refresh timer.
    await LiveUpdates.instance.stop();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Expired session: the app forgets it and shows the welcome '
      'page', (tester) async {
    await setPhone(tester);
    FlutterSecureStorage.setMockInitialValues({
      'citisense_session_token': _token,
      'citisense_session_user': jsonEncode(_user),
    });

    await http.runWithClient(() async {
      await tester.pumpWidget(realApp());
      await tester.pumpAndSettle();
      expect(find.byType(LandingPage), findsOneWidget);
      expect(AuthSession.isLoggedIn, isFalse);
      expect(await AuthSession.load(), isFalse);
    }, () => MockClient((r) => fakeApi(r, sessionValid: false)));
  });

  testWidgets('Log Out ends the session and shows Log In with nothing '
      'behind it', (tester) async {
    await setPhone(tester);
    FlutterSecureStorage.setMockInitialValues({
      'citisense_session_token': _token,
      'citisense_session_user': jsonEncode(_user),
    });
    final calls = <String>[];

    await http.runWithClient(() async {
      await tester.pumpWidget(realApp());
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Settings'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.scrollUntilVisible(
        find.text('Log Out'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Log Out'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.widgetWithText(TextButton, 'Log Out'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(calls, contains('session.php logout'));
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byType(HomePage), findsNothing);
      expect(appNavigatorKey.currentState!.canPop(), isFalse);
      expect(AuthSession.isLoggedIn, isFalse);
      expect(await AuthSession.load(), isFalse);

      // Back on Log In goes to the welcome page, not to Home.
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
      await tester.pumpAndSettle();
      expect(find.byType(LandingPage), findsOneWidget);
      expect(find.byType(HomePage), findsNothing);
    }, () => MockClient((r) => fakeApi(r, calls: calls)));
  });

  for (final page in const <Widget>[LoginPage(), CreateAccount()]) {
    testWidgets('${page.runtimeType}: account link is centered', (
      tester,
    ) async {
      // Wide enough that the prompt and the link stay on one line.
      await setPhone(tester, width: 800);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: page));
      await tester.pump();

      final link = page is LoginPage ? 'Sign Up' : 'Log In';
      final prompt = page is LoginPage
          ? "Don't have an account? "
          : 'Already have an account? ';

      await tester.scrollUntilVisible(
        find.text(link).last,
        200,
        scrollable: find.byType(Scrollable).first,
      );

      final left = tester.getTopLeft(find.text(prompt)).dx;
      final right = tester.getTopRight(find.text(link).last).dx;
      final screenCenter = tester.view.physicalSize.width / 3 / 2;
      expect(((left + right) / 2 - screenCenter).abs(), lessThan(2));
    });
  }
}
