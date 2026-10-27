import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_am_astudent/database/db_helper.dart';
import 'package:i_am_astudent/frontend/features/admin/user_management_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('admin role remains a valid user management selection', (
    tester,
  ) async {
    final suffix = DateTime.now().microsecondsSinceEpoch.toString();
    await DbHelper.instance.createUser(
      id: 'admin-role-$suffix',
      email: 'admin-role-$suffix@example.org',
      displayName: 'Admin Role Test',
      role: 'admin',
    );

    await tester.pumpWidget(const MaterialApp(home: UserManagementScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Admin Role Test'));
    await tester.pumpAndSettle();

    final roleDropdown = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>),
    );
    expect(roleDropdown.initialValue, 'admin');
    expect(find.text('Admin'), findsOneWidget);
  });
}
