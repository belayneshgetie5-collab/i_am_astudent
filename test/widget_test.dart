import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_am_astudent/backend/services/auth_service.dart';
import 'package:i_am_astudent/database/db_helper.dart';
import 'package:i_am_astudent/frontend/features/auth/login_screen.dart';
import 'package:i_am_astudent/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('app launches directly into the login screen', (tester) async {
    await _pumpSaamepApp(tester);

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('SAAMEP'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
  });

  testWidgets('invalid credentials stay on the login form', (tester) async {
    await _pumpSaamepApp(tester);
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(
      find.text('Password must be at least 8 characters.'),
      findsOneWidget,
    );
  });

  testWidgets('unknown credentials show the requested error message', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() => DbHelper.instance.database);
    await _pumpSaamepApp(tester);
    await tester.enterText(
      find.byKey(const ValueKey('emailField')),
      'unknown-${DateTime.now().microsecondsSinceEpoch}@example.org',
    );
    await tester.enterText(
      find.byKey(const ValueKey('passwordField')),
      'UnknownPass123!',
    );
    await tester.tap(find.text('Sign in'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    tester.testTextInput.hide();
    await tester.pump();

    expect(find.text(AuthService.accountNotFoundMessage), findsOneWidget);
    final action = tester.widget<SnackBar>(find.byType(SnackBar)).action!;
    action.onPressed();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('nameField')), findsOneWidget);
    expect(find.text('Already have an account? Sign in'), findsOneWidget);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('login fields start empty and sign-up asks for a name', (
    tester,
  ) async {
    await tester.runAsync(() => DbHelper.instance.database);
    await _pumpSaamepApp(tester);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('emailField')))
          .controller
          ?.text,
      isEmpty,
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('passwordField')))
          .controller
          ?.text,
      isEmpty,
    );
    expect(find.text("Don't have an account? Sign up"), findsOneWidget);

    await tester.tap(find.text("Don't have an account? Sign up"));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('nameField')), findsOneWidget);
    expect(find.text('Sign up'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(3));
  });

  testWidgets('login input survives a parent rebuild', (tester) async {
    Widget loginApp(ThemeData theme) =>
        MaterialApp(theme: theme, home: const LoginScreen());

    await tester.pumpWidget(loginApp(ThemeData.light()));
    await tester.enterText(
      find.byKey(const ValueKey('emailField')),
      'student@example.org',
    );
    await tester.enterText(
      find.byKey(const ValueKey('passwordField')),
      'TypedPassword123!',
    );

    await tester.pumpWidget(
      loginApp(ThemeData.light().copyWith(primaryColor: Colors.orange)),
    );

    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('emailField')))
          .controller
          ?.text,
      'student@example.org',
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('passwordField')))
          .controller
          ?.text,
      'TypedPassword123!',
    );

    await tester.enterText(find.byKey(const ValueKey('passwordField')), '');
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('passwordField')))
          .controller
          ?.text,
      isEmpty,
    );
    await tester.enterText(
      find.byKey(const ValueKey('passwordField')),
      'UpdatedPassword456!',
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('passwordField')))
          .controller
          ?.text,
      'UpdatedPassword456!',
    );
  });

  testWidgets('password is obscured until visibility is toggled', (
    tester,
  ) async {
    await _pumpSaamepApp(tester);
    final passwordField = find.byKey(const ValueKey('passwordField'));
    bool isPasswordObscured() => tester
        .widget<TextField>(
          find.descendant(of: passwordField, matching: find.byType(TextField)),
        )
        .obscureText;

    expect(
      tester.getRect(find.byType(DropdownButtonFormField<String>)).bottom,
      lessThan(tester.getRect(find.byKey(const ValueKey('emailField'))).top),
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('emailField'))).bottom,
      lessThan(tester.getRect(passwordField).top),
    );
    expect(isPasswordObscured(), isTrue);
    expect(find.byTooltip('Show password'), findsOneWidget);

    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(isPasswordObscured(), isFalse);
    expect(find.byTooltip('Hide password'), findsOneWidget);

    await tester.tap(find.byTooltip('Hide password'));
    await tester.pump();
    expect(isPasswordObscured(), isTrue);
  });

  testWidgets('sign-up creates an account and opens its role dashboard', (
    tester,
  ) async {
    await tester.runAsync(() => DbHelper.instance.database);
    await _pumpSaamepApp(tester);
    await tester.tap(find.text("Don't have an account? Sign up"));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('nameField')),
      'Widget Test Student',
    );
    await tester.enterText(
      find.byKey(const ValueKey('schoolIdField')),
      'AMU-WIDGET-001',
    );
    final email = 'widget-${DateTime.now().microsecondsSinceEpoch}@example.org';
    await tester.enterText(find.byKey(const ValueKey('emailField')), email);
    await tester.enterText(
      find.byKey(const ValueKey('passwordField')),
      'SecurePass123!',
    );
    await tester.ensureVisible(find.text('Sign up'));
    await tester.tap(find.text('Sign up'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 2)),
    );
    for (
      var attempt = 0;
      attempt < 100 &&
          find.text("Don't have an account? Sign up").evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final student = await tester.runAsync(
      () => DbHelper.instance.getUserByEmail(email),
    );
    expect(student?['account_status'], 'pending');
    await tester.runAsync(
      () => DbHelper.instance.setStudentStatus(
        student!['id']! as String,
        'approved',
      ),
    );
    await tester.enterText(find.byKey(const ValueKey('emailField')), email);
    await tester.enterText(
      find.byKey(const ValueKey('passwordField')),
      'SecurePass123!',
    );
    await tester.tap(find.text('Sign in'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 2)),
    );
    for (
      var attempt = 0;
      attempt < 100 && find.text('Student Dashboard').evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Student Dashboard'), findsOneWidget);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('isLoggedIn'), isTrue);
    expect(preferences.getString('email'), email);
    expect(preferences.getString('role'), 'student');
  });

  testWidgets('saved admin session restores the admin dashboard', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'isLoggedIn': true,
      'email': 'jerykan@gmail.com',
      'role': 'admin',
    });
    await tester.runAsync(() => DbHelper.instance.database);
    await _pumpSaamepApp(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 1)),
    );
    await tester.pump();

    expect(find.text('Admin Panel'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}

Future<void> _pumpSaamepApp(WidgetTester tester) async {
  await tester.pumpWidget(const SaamepApp());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}
