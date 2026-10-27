import 'package:flutter_test/flutter_test.dart';
import 'package:i_am_astudent/backend/services/auth_service.dart';
import 'package:i_am_astudent/database/db_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('demo roles authenticate against the seeded local database', () async {
    for (final entry in DbHelper.demoAccounts.entries) {
      final user = await AuthService.instance.signIn(
        email: entry.value,
        password: DbHelper.demoPasswords[entry.key]!,
        role: entry.key,
      );
      expect(user.role, entry.key);
    }
  });

  test('requested offline admin credentials authenticate', () async {
    final user = await AuthService.instance.signIn(
      email: '  JERYKAN@GMAIL.COM ',
      password: 'eyerus@1234',
      role: ' Admin ',
    );
    expect(user.email, 'jerykan@gmail.com');
    expect(user.role, 'admin');
  });

  test('requested offline student credentials authenticate', () async {
    final user = await AuthService.instance.signIn(
      email: 'student@saamep.com',
      password: 'password123',
      role: 'student',
    );
    expect(user.email, 'student@saamep.com');
    expect(user.role, 'student');
  });

  test('student usernames are unique, persistent login identifiers', () async {
    final suffix = DateTime.now().microsecondsSinceEpoch.toString();
    final email = 'username-$suffix@example.org';
    final username = 'saamep-$suffix';
    final user = await AuthService.instance.register(
      email: email,
      displayName: 'Username Student',
      password: 'StudentPass123!',
      role: 'student',
      studentUsername: username,
    );
    expect(
      (await DbHelper.instance.getUserByEmail(email))?['student_username'],
      username,
    );
    await DbHelper.instance.setStudentStatus(user.id, 'active');
    final signedIn = await AuthService.instance.signIn(
      email: username,
      password: 'StudentPass123!',
      role: 'student',
    );
    expect(signedIn.email, email);
    expect(signedIn.role, 'student');

    await expectLater(
      DbHelper.instance.registerUser(
        email: 'duplicate-$suffix@example.org',
        displayName: 'Duplicate Username',
        password: 'StudentPass123!',
        role: 'student',
        studentUsername: username,
      ),
      throwsArgumentError,
    );
  });

  test('local authentication trims and case-folds the email', () async {
    final user = await DbHelper.instance.authenticateLocalUser(
      email: '  STUDENT@SAAMEP.COM  ',
      password: DbHelper.demoPasswords['student']!,
      role: ' Student ',
    );
    expect(user?['email'], DbHelper.demoAccounts['student']);
  });

  test(
    'empty local credentials are rejected without a database match',
    () async {
      expect(
        await DbHelper.instance.authenticateLocalUser(
          email: '   ',
          password: DbHelper.demoPasswords['student']!,
          role: 'student',
        ),
        isNull,
      );
      expect(
        await DbHelper.instance.authenticateLocalUser(
          email: DbHelper.demoAccounts['student']!,
          password: '',
          role: 'student',
        ),
        isNull,
      );
    },
  );

  test('demo credentials are role-specific', () async {
    expect(DbHelper.demoAccounts.values.toSet(), hasLength(4));
    expect(DbHelper.demoPasswords.values.toSet(), hasLength(4));
    for (final entry in DbHelper.demoAccounts.entries) {
      for (final otherEntry in DbHelper.demoAccounts.entries) {
        if (entry.key == otherEntry.key) continue;
        await expectLater(
          await DbHelper.instance.authenticateLocalUser(
            email: entry.value,
            password: DbHelper.demoPasswords[otherEntry.key]!,
            role: entry.key,
          ),
          isNull,
        );
      }
    }
  });

  test(
    'unknown role shows sign-up prompt and incorrect password is rejected',
    () async {
      await expectLater(
        AuthService.instance.signIn(
          email: DbHelper.demoAccounts['student']!,
          password: DbHelper.demoPasswords['student']!,
          role: 'teacher',
        ),
        throwsA(
          isA<AuthException>().having(
            (error) => error.message,
            'message',
            AuthService.accountNotFoundMessage,
          ),
        ),
      );
      await expectLater(
        AuthService.instance.signIn(
          email: DbHelper.demoAccounts['student']!,
          password: 'WrongPassword123!',
          role: 'student',
        ),
        throwsA(
          isA<AuthException>().having(
            (error) => error.message,
            'message',
            AuthService.invalidCredentialsMessage,
          ),
        ),
      );
    },
  );

  test(
    'new accounts are stored locally with a role-bound credential',
    () async {
      final email =
          'signup-${DateTime.now().microsecondsSinceEpoch}@example.org';
      final user = await AuthService.instance.register(
        email: email,
        displayName: 'New Student',
        password: 'StudentPass123!',
        role: 'student',
      );
      expect(user.id, matches(RegExp(r'^\d+-\d+$')));
      expect(user.email, email);
      expect(user.role, 'student');

      final authenticated = await DbHelper.instance.authenticateLocalUser(
        email: email,
        password: 'StudentPass123!',
        role: 'student',
      );
      expect(authenticated?['display_name'], 'New Student');
      expect(authenticated?['account_status'], 'pending');
      expect(
        await DbHelper.instance.authenticateLocalUser(
          email: email,
          password: 'StudentPass123!',
          role: 'teacher',
        ),
        isNull,
      );
      await expectLater(
        AuthService.instance.signIn(
          email: email,
          password: 'StudentPass123!',
          role: 'student',
        ),
        throwsA(
          isA<AuthException>().having(
            (error) => error.message,
            'message',
            AuthService.pendingApprovalMessage,
          ),
        ),
      );
      await DbHelper.instance.setStudentStatus(user.id, 'approved');
      final signedIn = await AuthService.instance.signIn(
        email: email,
        password: 'StudentPass123!',
        role: 'student',
      );
      expect(signedIn.email, email);
      expect(signedIn.role, 'student');
      await DbHelper.instance.setStudentStatus(user.id, 'blocked');
      await expectLater(
        AuthService.instance.signIn(
          email: email,
          password: 'StudentPass123!',
          role: 'student',
        ),
        throwsA(
          isA<AuthException>().having(
            (error) => error.message,
            'message',
            AuthService.blockedAccountMessage,
          ),
        ),
      );
      await expectLater(
        AuthService.instance.register(
          email: email,
          displayName: 'Duplicate Student',
          password: 'AnotherPass123!',
          role: 'student',
        ),
        throwsA(
          isA<AuthException>().having(
            (error) => error.message,
            'message',
            'An account with this email address already exists.',
          ),
        ),
      );
    },
  );
}
