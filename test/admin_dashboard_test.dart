import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_am_astudent/backend/services/auth_service.dart';
import 'package:i_am_astudent/database/db_helper.dart';
import 'package:i_am_astudent/frontend/features/admin/admin_dashboard.dart';
import 'package:i_am_astudent/frontend/features/admin/admin_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('admin dashboard exposes all five functional consoles', (
    tester,
  ) async {
    await tester.runAsync(() => DbHelper.instance.database);
    await tester.runAsync(
      () => DbHelper.instance.saveAdminFilters(
        section: 'All',
        gender: 'All',
        tier: 'All',
      ),
    );
    await tester.runAsync(() => DbHelper.instance.saveAdminSearch(''));
    await tester.pumpWidget(
      const MaterialApp(home: AdminDashboard(email: 'admin@example.org')),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump();

    expect(find.text('Admin Panel'), findsOneWidget);
    expect(find.text('Platform Analytics'), findsOneWidget);
    expect(find.text('Grade Distribution'), findsOneWidget);
    await tester.tap(find.text('Online'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(find.text('System Health & Diagnostics'), findsOneWidget);
    expect(find.text('SQLite Local DB'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Platform-Wide Student Performance'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Platform-Wide Student Performance'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.tap(find.text('Students'));
    await tester.pump();
    expect(find.text('Verification Console'), findsOneWidget);
    await tester.tap(find.text('Parents'));
    await tester.pump();
    expect(find.text('Parent Accounts'), findsOneWidget);
    await tester.tap(find.text('Database'));
    await tester.pump();
    expect(find.text('Academic Database'), findsOneWidget);
    final students = await tester.runAsync(
      () => DbHelper.instance.getAdminStudents(),
    );
    expect(students, isNotNull);
    final searchableStudent = students!.firstWhere(
      (student) => student['student_username'] != null,
    );
    await tester.enterText(
      find.byKey(const ValueKey('studentRosterSearch')),
      '@${searchableStudent['student_username']}',
    );
    await tester.pump();
    expect(find.byType(DataTable), findsOneWidget);
    expect(
      find.text(searchableStudent['display_name']! as String),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('studentRosterSearch')),
      'no-student-matches-this-search',
    );
    await tester.pump();
    expect(
      find.text('No student records match the selected filters.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Teachers'));
    await tester.pump();
    expect(find.text('Teachers'), findsWidgets);
  });

  test(
    'admin metrics, filters, and registration states persist in SQLite',
    () async {
      final suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final studentEmail = 'admin-student-$suffix@example.org';
      final parentEmail = 'admin-parent-$suffix@example.org';
      final teacherEmail = 'admin-teacher-$suffix@example.org';
      final originalAdminSearch = await DbHelper.instance.getAdminSearch();

      await DbHelper.instance.registerUser(
        email: studentEmail,
        displayName: 'Pending Student',
        password: 'StudentPass123!',
        role: 'student',
        schoolId: 'AMU-$suffix',
        section: 'Section B',
        gender: 'Female',
      );
      final student = await DbHelper.instance.getUserByEmail(studentEmail);
      expect(student?['school_id'], 'AMU-$suffix');
      expect(student?['section'], 'Section B');
      expect(student?['gender'], 'Female');
      expect(student?['account_status'], 'pending');
      expect(student?['status'], 'pending');
      expect(student?['student_username'], isNotEmpty);
      expect(student?['school'], 'AMU Community School');
      expect(
        (await DbHelper.instance.getAdminStudents()).singleWhere(
          (row) => row['email'] == studentEmail,
        )['average_score'],
        isNull,
      );

      await DbHelper.instance.setStudentStatus(
        student!['id']! as String,
        'approved',
      );
      expect(
        (await DbHelper.instance.getAdminStudents()).singleWhere(
          (row) => row['email'] == studentEmail,
        )['account_status'],
        'approved',
      );
      expect(
        (await DbHelper.instance.getAdminStudents()).singleWhere(
          (row) => row['email'] == studentEmail,
        )['status'],
        'active',
      );
      expect(
        (await DbHelper.instance.getAdminStudents()).singleWhere(
          (row) => row['email'] == studentEmail,
        )['approved_at'],
        isNotNull,
      );
      await DbHelper.instance.toggleBlockUser(student['id']! as String);
      expect(
        (await DbHelper.instance.getUserByEmail(studentEmail))?['status'],
        'blocked',
      );
      await DbHelper.instance.toggleBlockUser(student['id']! as String);
      expect(
        (await DbHelper.instance.getUserByEmail(studentEmail))?['status'],
        'active',
      );
      await DbHelper.instance.setStudentStatus(
        student['id']! as String,
        'rejected',
      );
      final rejectedStudent = await DbHelper.instance.getUserByEmail(
        studentEmail,
      );
      expect(rejectedStudent?['status'], 'blocked');
      expect(rejectedStudent?['account_status'], 'rejected');
      await DbHelper.instance.setStudentStatus(
        student['id']! as String,
        'active',
      );
      final rejectedEmail = 'rejected-student-$suffix@example.org';
      await DbHelper.instance.registerUser(
        email: rejectedEmail,
        displayName: 'Rejected Applicant',
        password: 'StudentPass123!',
        role: 'student',
      );
      final rejectedApplicant = await DbHelper.instance.getUserByEmail(
        rejectedEmail,
      );
      await DbHelper.instance.rejectPendingStudent(
        rejectedApplicant!['id']! as String,
      );
      expect(await DbHelper.instance.getUserByEmail(rejectedEmail), isNull);

      await DbHelper.instance.createUser(
        id: 'parent-$suffix',
        email: parentEmail,
        displayName: 'Parent Account',
        role: 'parent',
      );
      await DbHelper.instance.registerUser(
        email: teacherEmail,
        displayName: 'Teacher Account',
        password: 'TeacherPass123!',
        role: 'teacher',
        assignedSubjects: 'Civics, History',
      );
      expect(
        (await DbHelper.instance.getAdminRoleCounts())['parent'],
        greaterThanOrEqualTo(1),
      );
      expect(
        (await DbHelper.instance.getAdminTeachers()).singleWhere(
          (row) => row['email'] == teacherEmail,
        )['assigned_subjects'],
        'Civics, History',
      );
      expect(
        (await DbHelper.instance.getTeachersList()).any(
          (row) => row['email'] == teacherEmail,
        ),
        isTrue,
      );

      await DbHelper.instance.createParentLinkRequest(
        parentEmail: parentEmail,
        studentId: student['student_username']! as String,
      );
      final request = (await DbHelper.instance.getParentLinkRequests())
          .singleWhere((row) => row['parent_email'] == parentEmail);
      expect(
        (await DbHelper.instance.getParentLinks()).any(
          (link) => link['id'] == request['id'],
        ),
        isTrue,
      );
      await DbHelper.instance.approveParentLink(request['id']! as String);
      final linkedStudent = await DbHelper.instance.getUserByEmail(
        studentEmail,
      );
      expect(linkedStudent?['parent_email'], parentEmail);

      await DbHelper.instance.saveAdminFilters(
        section: 'Section B',
        gender: 'Female',
        tier: 'Good',
      );
      expect(await DbHelper.instance.getAdminFilters(), {
        'section': 'Section B',
        'gender': 'Female',
        'tier': 'Good',
      });
      await DbHelper.instance.saveAdminSearch(
        student['student_username']! as String,
      );
      expect(
        await DbHelper.instance.getAdminSearch(),
        student['student_username'],
      );
      await DbHelper.instance.saveAdminSearch(originalAdminSearch);
      expect(
        await DbHelper.instance.filterStudents(
          section: 'Section B',
          gender: 'Female',
          search: student['student_username']! as String,
        ),
        hasLength(1),
      );

      final temporaryPassword = await DbHelper.instance.resetTeacherPassword(
        (await DbHelper.instance.getAdminTeachers()).singleWhere(
              (row) => row['email'] == teacherEmail,
            )['id']!
            as String,
      );
      expect(temporaryPassword, hasLength(14));
      final teacherRecord = await DbHelper.instance.getUserByEmail(
        teacherEmail,
      );
      expect(teacherRecord?['force_password_reset'], 1);
      final forcedSignIn = await AuthService.instance.signIn(
        email: teacherEmail,
        password: temporaryPassword,
        role: 'teacher',
      );
      expect(forcedSignIn.forcePasswordReset, isTrue);
      expect(
        (await DbHelper.instance.authenticateLocalUser(
          email: teacherEmail,
          password: temporaryPassword,
          role: 'teacher',
        ))?['display_name'],
        'Teacher Account',
      );
      await DbHelper.instance.completeTeacherPasswordReset(
        userId: teacherRecord!['id']! as String,
        email: teacherEmail,
        password: 'NewTeacherPass123!',
      );
      expect(
        (await DbHelper.instance.getUserByEmail(
          teacherEmail,
        ))?['force_password_reset'],
        0,
      );
      expect(
        (await DbHelper.instance.authenticateLocalUser(
          email: teacherEmail,
          password: 'NewTeacherPass123!',
          role: 'teacher',
        ))?['display_name'],
        'Teacher Account',
      );
      final completedSignIn = await AuthService.instance.signIn(
        email: teacherEmail,
        password: 'NewTeacherPass123!',
        role: 'teacher',
      );
      expect(completedSignIn.forcePasswordReset, isFalse);
    },
  );

  test('admin performance filters honor ministry cutoffs', () async {
    final suffix = DateTime.now().microsecondsSinceEpoch.toString();
    final database = await DbHelper.instance.database;
    final cutoffCases = [
      (score: 49, tier: 'At Risk'),
      (score: 74, tier: 'Good'),
      (score: 75, tier: 'Excellent'),
    ];

    for (final (index, testCase) in cutoffCases.indexed) {
      final email = 'admin-cutoff-$index-$suffix@example.org';
      await DbHelper.instance.registerUser(
        email: email,
        displayName: 'Cutoff Student $index',
        password: 'StudentPass123!',
        role: 'student',
      );
      final user = await DbHelper.instance.getUserByEmail(email);
      final username = user!['student_username']! as String;
      await database.insert('exam_results', {
        'id': 'admin-cutoff-$index-$suffix',
        'student_username': username,
        'subject_name': 'Ministry baseline test',
        'score_percentage': testCase.score,
        'completed_at': DateTime.now().toUtc().toIso8601String(),
      });
      final filtered = await DbHelper.instance.filterStudents(
        scoreTier: testCase.tier,
        search: username,
      );
      expect(filtered, hasLength(1));
      expect(filtered.single['average_score'], testCase.score);
    }
  });

  test(
    'AdminProvider reacts to verification and database filter actions',
    () async {
      final suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final approvedEmail = 'provider-approved-$suffix@example.org';
      final rejectedEmail = 'provider-rejected-$suffix@example.org';
      await DbHelper.instance.registerUser(
        email: approvedEmail,
        displayName: 'Provider Student',
        password: 'StudentPass123!',
        role: 'student',
        section: 'Section B',
        gender: 'Female',
      );
      await DbHelper.instance.registerUser(
        email: rejectedEmail,
        displayName: 'Provider Rejected Student',
        password: 'StudentPass123!',
        role: 'student',
      );
      final approvedRecord = await DbHelper.instance.getUserByEmail(
        approvedEmail,
      );
      final rejectedRecord = await DbHelper.instance.getUserByEmail(
        rejectedEmail,
      );
      final provider = AdminProvider();
      var notifications = 0;
      provider.addListener(() => notifications++);

      await provider.fetchDashboardStats();
      final studentId = approvedRecord!['id']! as String;
      expect(
        provider.pendingStudentsList.any(
          (student) => student['id'] == studentId,
        ),
        isTrue,
      );
      await provider.applyDatabaseFilters('Section B', 'Female', 'All');
      expect(
        provider.filteredStudentsList.any(
          (student) => student['id'] == studentId,
        ),
        isTrue,
      );
      await provider.approveStudent(studentId);
      expect(
        provider.activeStudentsList.any(
          (student) => student['id'] == studentId,
        ),
        isTrue,
      );
      await provider.blockStudent(studentId);
      expect(
        provider.blockedStudentsList.any(
          (student) => student['id'] == studentId,
        ),
        isTrue,
      );
      await provider.unblockStudent(studentId);
      expect(
        provider.activeStudentsList.any(
          (student) => student['id'] == studentId,
        ),
        isTrue,
      );
      await provider.rejectStudent(rejectedRecord!['id']! as String);
      expect(
        provider.studentsList.any(
          (student) => student['id'] == rejectedRecord['id'],
        ),
        isFalse,
      );
      expect(notifications, greaterThan(6));
      provider.dispose();
    },
  );

  test(
    'forced sample seeding preserves account decisions and refreshes data',
    () async {
      await DbHelper.instance.database;
      final kidus = await DbHelper.instance.getUserByEmail(
        'kidus.y@example.org',
      );
      expect(kidus, isNotNull);
      await DbHelper.instance.updateUserStatus(
        kidus!['id']! as String,
        'blocked',
      );

      await DbHelper.instance.seedInitialDataIfEmpty(force: true);

      expect(
        (await DbHelper.instance.getUserByEmail(
          'kidus.y@example.org',
        ))?['status'],
        'blocked',
      );
      final summary = await DbHelper.instance.getAdminCurriculumSummary();
      expect(summary['subjects'], contains('General Science'));
      expect(summary['years'], isNotEmpty);
      final database = await DbHelper.instance.database;
      expect(
        await database.rawQuery(
          "SELECT id FROM exam_results WHERE id = 'sample-exam-result-0'",
        ),
        hasLength(1),
      );
    },
  );
}
