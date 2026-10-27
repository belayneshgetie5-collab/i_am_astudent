import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:i_am_astudent/backend/constants/api_constants.dart';
import 'package:i_am_astudent/backend/services/sync_service.dart';
import 'package:i_am_astudent/core/utils/csv_exporter.dart';
import 'package:i_am_astudent/database/db_helper.dart';
import 'package:i_am_astudent/frontend/constants/app_colors.dart';
import 'package:i_am_astudent/frontend/features/admin/admin_provider.dart';
import 'package:i_am_astudent/frontend/shared/custom_drawer.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({required this.email, super.key});

  final String email;

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => AdminProvider()..fetchDashboardStats(),
    child: _AdminDashboardContent(email: widget.email),
  );
}

class _AdminDashboardContent extends StatefulWidget {
  const _AdminDashboardContent({required this.email});

  final String email;

  @override
  State<_AdminDashboardContent> createState() => _AdminDashboardContentState();
}

class _AdminDashboardContentState extends State<_AdminDashboardContent> {
  static const _tabs = [
    _AdminTab('Stats', Icons.insights_outlined),
    _AdminTab('Students', Icons.school_outlined),
    _AdminTab('Parents', Icons.family_restroom_outlined),
    _AdminTab('Database', Icons.storage_outlined),
    _AdminTab('Teachers', Icons.cast_for_education_outlined),
  ];

  int _selectedTab = 0;
  bool _refreshing = false;
  String _studentStatusFilter = 'Pending Approval';

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final admin = context.read<AdminProvider>();
      await admin.fetchDashboardStats();
      if (admin.loadError != null) {
        throw StateError('Could not reload admin data: ${admin.loadError}');
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not refresh admin data: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _sync() async {
    final dialog = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    var dialogOpen = true;
    try {
      await Future.wait<void>([
        SyncService.instance.syncPending(),
        Future<void>.delayed(const Duration(seconds: 1)),
      ]);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      dialogOpen = false;
      await dialog;
      if (!mounted) return;
      final status = SyncService.instance.status.value;
      final message = switch (status.state) {
        SyncState.synced => 'Cloud sync completed.',
        SyncState.offline =>
          'No network connection. Changes remain saved locally.',
        SyncState.error => status.message ?? 'Cloud sync failed.',
        _ => 'Cloud sync completed.',
      };
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Sync failed: $error')));
    } finally {
      if (dialogOpen && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        await dialog;
      }
    }
  }

  Future<void> _seedSampleData() async {
    try {
      await DbHelper.instance.seedInitialDataIfEmpty(force: true);
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sample students, teachers, and exam results refreshed!',
          ),
          backgroundColor: Color(0xFF059669),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not seed sample data: $error')),
      );
    }
  }

  Future<void> _openContent() async {
    try {
      final summary = await DbHelper.instance.getAdminCurriculumSummary();
      if (!mounted) return;
      final subjects = summary['subjects'] ?? const <String>[];
      final years = summary['years'] ?? const <String>[];
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Grade 8 curriculum'),
          content: SizedBox(
            width: 420,
            child: ListView(
              shrinkWrap: true,
              children: [
                const Text(
                  'Configured subjects',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  subjects.isEmpty
                      ? 'No subjects are configured yet.'
                      : subjects.join(', '),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Exam years',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  years.isEmpty
                      ? 'No exam years are recorded yet.'
                      : years.join(', '),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load curriculum: $error')),
      );
    }
  }

  Future<void> _openSystemHealth() async {
    try {
      await DbHelper.instance.database;
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not inspect local database: $error')),
      );
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('System Health & Diagnostics'),
        content: SizedBox(
          width: 420,
          child: ValueListenableBuilder<SyncStatus>(
            valueListenable: SyncService.instance.status,
            builder: (context, status, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _HealthRow(
                  label: 'SQLite Local DB',
                  value: 'Ready · offline-first storage',
                  color: Color(0xFF10B981),
                ),
                _HealthRow(
                  label: 'Cloud Sync',
                  value: ApiConstants.apiBaseUrl.trim().isEmpty
                      ? 'Offline cache mode · API not configured'
                      : _syncStateLabel(status),
                  color:
                      ApiConstants.apiBaseUrl.trim().isEmpty ||
                          status.state == SyncState.offline ||
                          status.state == SyncState.error
                      ? const Color(0xFFF59E0B)
                      : const Color(0xFF10B981),
                ),
                _HealthRow(
                  label: 'AI Tutor Engine',
                  value: ApiConstants.grokApiKey.trim().isEmpty
                      ? 'Not configured'
                      : 'Configured · live availability not probed',
                  color: ApiConstants.grokApiKey.trim().isEmpty
                      ? const Color(0xFFF59E0B)
                      : const Color(0xFF10B981),
                ),
                if (status.message?.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      status.message!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _navigateToTab(int index) {
    setState(() => _selectedTab = index);
  }

  void _showDetailedPerformance() {
    _navigateToTab(3);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Showing full academic roster')),
    );
  }

  Future<void> _exportFilteredRoster() async {
    try {
      await _exportCsv(context.read<AdminProvider>().filteredStudentsList);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load filtered roster: $error')),
      );
    }
  }

  Future<void> _setStudentStatus(
    Map<String, Object?> student,
    String status,
  ) async {
    try {
      final studentId = student['id'];
      if (studentId is! String || studentId.isEmpty) {
        throw const FormatException('Student record is missing its ID.');
      }
      final admin = context.read<AdminProvider>();
      if (status == 'rejected') {
        await admin.rejectStudent(studentId);
      } else {
        final currentStatus = student['status'] as String? ?? 'active';
        final nextStatus = status == 'toggle'
            ? (currentStatus == 'active' ? 'blocked' : 'active')
            : status;
        if (nextStatus == 'blocked') {
          await admin.blockStudent(studentId);
        } else if (status == 'toggle' && currentStatus != 'active') {
          await admin.unblockStudent(studentId);
        } else if (nextStatus == 'active' || nextStatus == 'approved') {
          await admin.approveStudent(studentId);
        } else {
          await DbHelper.instance.updateUserStatus(studentId, nextStatus);
          await admin.fetchDashboardStats();
        }
      }
      if (!mounted) return;
      final name = student['display_name'] as String? ?? 'Student';
      final currentStatus = student['status'] as String? ?? 'active';
      final message = switch (status == 'toggle'
          ? (currentStatus == 'active' ? 'blocked' : 'active')
          : status) {
        'active' || 'approved' => '$name approved successfully.',
        'rejected' => '$name registration rejected and removed.',
        'blocked' => 'Access revoked for $name.',
        _ => '$name registration is pending.',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update student status: $error')),
      );
    }
  }

  Future<void> _resolveParentRequest(
    Map<String, Object?> request, {
    required bool approve,
  }) async {
    try {
      final id = request['id'];
      if (id is! String || id.isEmpty) {
        throw const FormatException('Parent link request is missing its ID.');
      }
      final admin = context.read<AdminProvider>();
      if (approve) {
        await DbHelper.instance.approveParentLink(id);
      } else {
        await DbHelper.instance.rejectParentLink(id);
      }
      await admin.fetchDashboardStats();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approve
                ? 'Parent-student link approved.'
                : 'Link request rejected.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not resolve link request: $error')),
      );
    }
  }

  Future<void> _createParentRequest() async {
    final draft = await showDialog<_ParentLinkDraft>(
      context: context,
      builder: (_) => const _ParentLinkDialog(),
    );
    if (draft == null || !mounted) return;
    try {
      final admin = context.read<AdminProvider>();
      await DbHelper.instance.createParentLinkRequest(
        parentEmail: draft.email,
        studentId: draft.studentId,
      );
      await admin.fetchDashboardStats();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Parent-student link request added for review.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not add parent link request: $error')),
      );
    }
  }

  Future<void> _addTeacher() async {
    final draft = await showDialog<_TeacherDraft>(
      context: context,
      builder: (_) => const _TeacherDialog(),
    );
    if (draft == null || !mounted) return;
    try {
      final admin = context.read<AdminProvider>();
      await DbHelper.instance.registerUser(
        email: draft.email,
        displayName: draft.name,
        password: draft.password,
        role: 'teacher',
        assignedSubjects: draft.subject,
      );
      await admin.fetchDashboardStats();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Teacher account created'),
          content: SelectableText(
            'Share these credentials securely with ${draft.name}.\n\n'
            'Email: ${draft.email}\nTemporary password: ${draft.password}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not add teacher: $error')));
    }
  }

  Future<void> _resetTeacherPassword(Map<String, Object?> teacher) async {
    try {
      final teacherId = teacher['id'];
      if (teacherId is! String || teacherId.isEmpty) {
        throw const FormatException('Teacher record is missing its ID.');
      }
      final password = await context.read<AdminProvider>().resetTeacherPassword(
        teacherId,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Temporary password generated'),
          content: SelectableText(
            'Share this password securely with '
            '${teacher['display_name']} (${teacher['email']}). '
            'A password change is required at the next sign-in. '
            'This password will not be shown again.\n\n$password',
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: password));
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Temporary password copied.')),
                  );
                }
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copy and close'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not reset teacher password: $error')),
      );
    }
  }

  Future<void> _updateFilters({
    String? section,
    String? gender,
    String? tier,
  }) async {
    try {
      final admin = context.read<AdminProvider>();
      await admin.applyDatabaseFilters(
        section ?? admin.filterSection,
        gender ?? admin.filterGender,
        tier ?? admin.filterScore,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save filters: $error')));
    }
  }

  Future<void> _updateSearch(String search) async {
    try {
      final admin = context.read<AdminProvider>();
      await admin.applyDatabaseFilters(
        admin.filterSection,
        admin.filterGender,
        admin.filterScore,
        search: search,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save search: $error')));
    }
  }

  Future<void> _exportCsv(List<Map<String, Object?>> students) async {
    final headers = [
      'ID',
      'Name',
      'Section',
      'Gender',
      'Average Score',
      'Status',
    ];
    final rows = students.map((student) {
      return [
        student['school_id'] ??
            student['student_username'] ??
            student['id'] ??
            '',
        student['display_name'] ?? '',
        student['section'] ?? '',
        student['gender'] ?? '',
        _score(student)?.toStringAsFixed(1) ?? 'Not assessed',
        student['status'] ?? student['account_status'] ?? 'active',
      ];
    });
    String escape(Object? value) =>
        '"${value.toString().replaceAll('"', '""')}"';
    final csv = [
      headers.map(escape).join(','),
      ...rows.map((row) => row.map(escape).join(',')),
    ].join('\r\n');
    try {
      const filename = 'SAAMEP_Grade8_Roster.csv';
      final location = await exportCsv(filename, csv);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isBrowserDownload(location)
                ? 'Filtered student roster downloaded.'
                : 'CSV saved to $location',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not export CSV: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminProvider>();
    final blueAction = ButtonStyle(
      backgroundColor: const WidgetStatePropertyAll(Color(0xFF00B0FF)),
      foregroundColor: const WidgetStatePropertyAll(Colors.white),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontWeight: FontWeight.w700),
      ),
      shadowColor: const WidgetStatePropertyAll(Color(0x6600B0FF)),
      elevation: const WidgetStatePropertyAll(4),
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
    );
    final adminTheme = Theme.of(context).copyWith(
      elevatedButtonTheme: ElevatedButtonThemeData(style: blueAction),
      filledButtonTheme: FilledButtonThemeData(
        style: blueAction.copyWith(
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(14)),
            ),
          ),
        ),
      ),
    );
    return Theme(
      data: adminTheme,
      child: Scaffold(
        drawer: AppDrawer(role: 'Admin', email: widget.email),
        appBar: AppBar(
          leading: Builder(
            builder: (context) => IconButton(
              tooltip: 'Open navigation menu',
              icon: const Icon(Icons.menu),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
          title: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Text('Admin Panel')],
          ),
          actions: [
            IconButton(
              tooltip: 'Refresh dashboard',
              onPressed: _refreshing ? null : _refresh,
              icon: _refreshing
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) => Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: SizedBox(
                width: math.min(constraints.maxWidth, 1100),
                height: constraints.maxHeight,
                child: admin.loadError != null
                    ? _LoadError(error: admin.loadError!, onRetry: _refresh)
                    : admin.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : Builder(
                        builder: (context) {
                          final data = _AdminData(
                            counts: {
                              'student': admin.totalStudents,
                              'teacher': admin.totalTeachers,
                              'parent': admin.totalParents,
                              'teachers': admin.totalTeachers,
                              'parents': admin.totalParents,
                            },
                            students: admin.studentsList,
                            distribution: admin.gradeDistribution,
                            teachers: admin.teachersList,
                            parents: admin.parentsList,
                            parentRequests: admin.parentRequestsList,
                            parentLinks: admin.parentLinksList,
                          );
                          return IndexedStack(
                            index: _selectedTab,
                            children: [
                              _StatsTab(
                                data: data,
                                onOpenProgress: _showDetailedPerformance,
                                onOpenContent: _openContent,
                                onSync: _sync,
                                onSeedSampleData: _seedSampleData,
                                onExport: _exportFilteredRoster,
                                onNavigateToTab: _navigateToTab,
                                onSystemHealth: _openSystemHealth,
                                onAtRiskTap: () {
                                  _updateFilters(tier: 'at_risk');
                                  _navigateToTab(3);
                                },
                              ),
                              _StudentsTab(
                                students: data.students,
                                statusFilter: _studentStatusFilter,
                                onStatusFilterChanged: (filter) => setState(
                                  () => _studentStatusFilter = filter,
                                ),
                                onStatusChanged: _setStudentStatus,
                              ),
                              _ParentsTab(
                                parents: data.parents,
                                requests: data.parentRequests,
                                links: data.parentLinks,
                                onAddRequest: _createParentRequest,
                                onResolve: _resolveParentRequest,
                              ),
                              _DatabaseTab(
                                students: admin.filteredStudentsList,
                                section: admin.filterSection,
                                gender: admin.filterGender,
                                tier: admin.filterScore,
                                onSectionChanged: (value) =>
                                    _updateFilters(section: value),
                                onGenderChanged: (value) =>
                                    _updateFilters(gender: value),
                                onTierChanged: (value) =>
                                    _updateFilters(tier: value),
                                search: admin.searchQuery,
                                onSearchChanged: _updateSearch,
                                onExport: _exportCsv,
                              ),
                              _TeachersTab(
                                teachers: data.teachers,
                                onResetPassword: _resetTeacherPassword,
                                onAddTeacher: _addTeacher,
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ),
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedTab,
          onDestinationSelected: (index) =>
              setState(() => _selectedTab = index),
          destinations: [
            for (final tab in _tabs)
              NavigationDestination(icon: Icon(tab.icon), label: tab.label),
          ],
        ),
      ),
    );
  }
}

class _StatsTab extends StatelessWidget {
  const _StatsTab({
    required this.data,
    required this.onOpenProgress,
    required this.onOpenContent,
    required this.onSync,
    required this.onSeedSampleData,
    required this.onExport,
    required this.onNavigateToTab,
    required this.onSystemHealth,
    required this.onAtRiskTap,
  });

  final _AdminData data;
  final VoidCallback onOpenProgress;
  final VoidCallback onOpenContent;
  final VoidCallback onSync;
  final VoidCallback onSeedSampleData;
  final Future<void> Function() onExport;
  final ValueChanged<int> onNavigateToTab;
  final VoidCallback onSystemHealth;
  final VoidCallback onAtRiskTap;

  @override
  Widget build(BuildContext context) {
    final registeredCount = data.students.length;
    final activeStudents = data.students
        .where(
          (student) =>
              student['status'] == 'active' ||
              student['account_status'] == 'approved',
        )
        .toList();
    final assessedCount =
        (data.distribution['total_assessed'] as int?) ??
        activeStudents.where((student) => _score(student) != null).length;
    final excellent =
        data.distribution['excellent'] as int? ??
        activeStudents.where((student) => (_score(student) ?? -1) >= 75).length;
    final good =
        data.distribution['good'] as int? ??
        activeStudents.where((student) {
          final score = _score(student) ?? -1;
          return score >= 50 && score < 75;
        }).length;
    final atRisk =
        data.distribution['at_risk'] as int? ??
        (assessedCount - excellent - good);
    final excellentPercent =
        (data.distribution['excellent_pct'] as num?)?.round() ??
        _percent(excellent, assessedCount);
    final goodPercent =
        (data.distribution['good_pct'] as num?)?.round() ??
        _percent(good, assessedCount);
    final atRiskPercent =
        (data.distribution['at_risk_pct'] as num?)?.round() ??
        _percent(atRisk, assessedCount);

    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 30),
      children: [
        const Text(
          'Platform Analytics',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          'Real-time data across all roles',
          style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 13),
        ),
        const SizedBox(height: 22),
        const _SectionHeading(
          title: 'Community Overview',
          subtitle: 'Accounts and platform availability',
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth > 650 ? 4 : 2;
            return GridView(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisExtent: 140,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _StatCard(
                  label: 'Total Students',
                  value: '$registeredCount',
                  caption: '$atRisk At-Risk / $registeredCount Registered',
                  icon: Icons.school_outlined,
                  color: const Color(0xFF4F46E5),
                  onTap: () => onNavigateToTab(1),
                ),
                _StatCard(
                  label: 'Total Teachers',
                  value: '${data.counts['teacher'] ?? 0}',
                  caption: 'Registered educators',
                  icon: Icons.cast_for_education_outlined,
                  color: const Color(0xFF0284C7),
                  onTap: () => onNavigateToTab(4),
                ),
                _StatCard(
                  label: 'Total Parents',
                  value: '${data.counts['parent'] ?? 0}',
                  caption: 'Linked parent accounts',
                  icon: Icons.family_restroom_outlined,
                  color: const Color(0xFF7C3AED),
                  onTap: () => onNavigateToTab(2),
                ),
                _StatCard(
                  label: 'Platform Status',
                  value: 'Online',
                  caption: 'Local services available',
                  icon: Icons.cloud_done_outlined,
                  color: const Color(0xFF059669),
                  online: true,
                  onTap: onSystemHealth,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 26),
        const _SectionHeading(
          title: 'Grade Distribution',
          subtitle: 'How all students are performing across the platform',
        ),
        const SizedBox(height: 13),
        Row(
          children: [
            Expanded(
              child: _GradeCard(
                percent: excellentPercent,
                label: 'Excellent',
                detail: 'Score ≥ 75%',
                color: const Color(0xFF059669),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: _GradeCard(
                percent: goodPercent,
                label: 'Good',
                detail: 'Score 50–74%',
                color: const Color(0xFFF59E0B),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: _GradeCard(
                percent: atRiskPercent,
                label: 'At Risk',
                detail: 'Score < 50%',
                color: const Color(0xFFE11D48),
                onTap: onAtRiskTap,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00E5FF).withValues(alpha: 0.18),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 17, 16, 15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Platform-Wide Student Performance',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$assessedCount assessed of $registeredCount registered students · at-risk indicates '
                  'below the Ministry exam baseline',
                  style: TextStyle(
                    color: const Color(0xFFCBD5E1),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 150,
                  width: double.infinity,
                  child: Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      CustomPaint(
                        size: const Size(double.infinity, 148),
                        painter: _DistributionGauge(
                          excellent: excellent,
                          good: good,
                          atRisk: atRisk,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$assessedCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'assessed',
                              style: TextStyle(
                                color: const Color(0xFFCBD5E1),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 14,
                  runSpacing: 8,
                  children: [
                    _LegendDot(
                      color: const Color(0xFF059669),
                      label: 'Excellent $excellentPercent%',
                    ),
                    _LegendDot(
                      color: const Color(0xFFF59E0B),
                      label: 'Good $goodPercent%',
                    ),
                    _LegendDot(
                      color: const Color(0xFFE11D48),
                      label: 'At Risk $atRiskPercent%',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: onOpenProgress,
          icon: const Icon(Icons.analytics_outlined),
          label: const Text('View detailed exam performance'),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: onSeedSampleData,
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('Seed sample data'),
            ),
            OutlinedButton.icon(
              onPressed: onExport,
              icon: const Icon(Icons.download_outlined),
              label: const Text('Export roster CSV'),
            ),
            OutlinedButton.icon(
              onPressed: onOpenContent,
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('Manage content'),
            ),
            FilledButton.tonalIcon(
              onPressed: onSync,
              icon: const Icon(Icons.sync),
              label: const Text('Sync cloud'),
            ),
          ],
        ),
      ],
    );
  }
}

class _StudentsTab extends StatelessWidget {
  const _StudentsTab({
    required this.students,
    required this.statusFilter,
    required this.onStatusFilterChanged,
    required this.onStatusChanged,
  });

  final List<Map<String, Object?>> students;
  final String statusFilter;
  final ValueChanged<String> onStatusFilterChanged;
  final Future<void> Function(Map<String, Object?>, String) onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final visibleStudents = students.where((student) {
      final status =
          student['status'] as String? ??
          student['account_status'] as String? ??
          'active';
      return switch (statusFilter) {
        'Pending Approval' => status == 'pending',
        'Active' => status == 'active' || status == 'approved',
        'Blocked' => status == 'blocked' || status == 'rejected',
        _ => false,
      };
    }).toList();
    final isPending = statusFilter == 'Pending Approval';
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const _SectionHeading(
          title: 'Verification Console',
          subtitle: 'Student Verification Console · UC-07 · Review registrations and control access',
        ),
        const SizedBox(height: 14),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'Pending Approval',
              label: Text('Pending Approval'),
              icon: Icon(Icons.pending_actions_outlined),
            ),
            ButtonSegment(
              value: 'Active',
              label: Text('Active'),
              icon: Icon(Icons.verified_outlined),
            ),
            ButtonSegment(
              value: 'Blocked',
              label: Text('Blocked'),
              icon: Icon(Icons.block_outlined),
            ),
          ],
          selected: {statusFilter},
          onSelectionChanged: (selection) =>
              onStatusFilterChanged(selection.first),
        ),
        const SizedBox(height: 14),
        _CountBanner(
          count: visibleStudents.length,
          label: switch (statusFilter) {
            'Pending Approval' => 'registrations awaiting review',
            'Active' => 'active student accounts',
            _ => 'blocked student accounts',
          },
          color: isPending
              ? const Color(0xFFB45309)
              : statusFilter == 'Active'
              ? const Color(0xFF059669)
              : const Color(0xFFE11D48),
        ),
        const SizedBox(height: 10),
        if (visibleStudents.isEmpty)
          const _EmptyCard(
            icon: Icons.fact_check_outlined,
            message: 'No student accounts match this status.',
          ),
        _StudentCardsGrid(
          students: visibleStudents,
          onStatusChanged: onStatusChanged,
          showDecisionActions: isPending,
        ),
      ],
    );
  }
}

class _StudentCard extends StatelessWidget {
  const _StudentCard({
    required this.student,
    required this.onStatusChanged,
    required this.showDecisionActions,
  });

  final Map<String, Object?> student;
  final Future<void> Function(Map<String, Object?>, String) onStatusChanged;
  final bool showDecisionActions;

  @override
  Widget build(BuildContext context) {
    final name = student['display_name'] as String? ?? 'Student';
    final schoolId = student['school_id'] as String? ?? '';
    final section = student['section'] as String? ?? '';
    final gender = student['gender'] as String? ?? '';
    final status =
        student['status'] as String? ??
        student['account_status'] as String? ??
        'active';
    final approved = status == 'active' || status == 'approved';
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE8EAF2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.powderBlue,
                  foregroundColor: AppColors.ink,
                  child: Text(name.isEmpty ? '?' : name[0].toUpperCase()),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        student['email'] as String? ?? '',
                        style: TextStyle(
                          color: Colors.blueGrey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusChip(status: status),
              ],
            ),
            const SizedBox(height: 12),
            _DetailLine(
              icon: Icons.alternate_email,
              label: 'Student username',
              value: '@${student['student_username'] ?? 'Not assigned'}',
            ),
            _DetailLine(
              icon: Icons.account_balance_outlined,
              label: 'School',
              value: student['school'] as String? ?? 'AMU Community School',
            ),
            _DetailLine(
              icon: Icons.badge_outlined,
              label: 'AMU Community School ID',
              value: schoolId.isNotEmpty ? schoolId : 'Not provided',
            ),
            _DetailLine(
              icon: Icons.class_outlined,
              label: 'Grade 8 section',
              value: section.isNotEmpty ? section : 'Not specified',
            ),
            _DetailLine(
              icon: Icons.person_outline,
              label: 'Gender',
              value: gender.isNotEmpty ? gender : 'Not specified',
            ),
            _DetailLine(
              icon: Icons.calendar_today_outlined,
              label: 'Registration date',
              value: _formatDate(student['created_at'] as String?),
            ),
            if (approved && student['approved_at'] is String)
              _DetailLine(
                icon: Icons.verified_outlined,
                label: 'Approved',
                value: _formatDate(student['approved_at'] as String?),
              ),
            const SizedBox(height: 10),
            if (showDecisionActions)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => onStatusChanged(student, 'active'),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Approve'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => onStatusChanged(student, 'rejected'),
                    icon: const Icon(Icons.close),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFE11D48),
                    ),
                  ),
                ],
              )
            else
              Wrap(
                spacing: 8,
                children: [
                  if (approved)
                    OutlinedButton.icon(
                      onPressed: () => onStatusChanged(student, 'toggle'),
                      icon: const Icon(Icons.block_outlined),
                      label: const Text('Block / Revoke Access'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFE11D48),
                      ),
                    ),
                  if (status == 'blocked' || status == 'rejected')
                    OutlinedButton.icon(
                      onPressed: () => onStatusChanged(student, 'active'),
                      icon: const Icon(Icons.lock_open_outlined),
                      label: const Text('Unblock / Restore Access'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _StudentCardsGrid extends StatelessWidget {
  const _StudentCardsGrid({
    required this.students,
    required this.onStatusChanged,
    required this.showDecisionActions,
  });

  final List<Map<String, Object?>> students;
  final Future<void> Function(Map<String, Object?>, String) onStatusChanged;
  final bool showDecisionActions;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 760 ? 2 : 1;
      final itemWidth = (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final student in students)
            SizedBox(
              width: itemWidth,
              child: _StudentCard(
                student: student,
                onStatusChanged: onStatusChanged,
                showDecisionActions: showDecisionActions,
              ),
            ),
        ],
      );
    },
  );
}

class _ParentsTab extends StatelessWidget {
  const _ParentsTab({
    required this.parents,
    required this.requests,
    required this.links,
    required this.onAddRequest,
    required this.onResolve,
  });

  final List<Map<String, Object?>> parents;
  final List<Map<String, Object?>> requests;
  final List<Map<String, Object?>> links;
  final VoidCallback onAddRequest;
  final Future<void> Function(Map<String, Object?>, {required bool approve})
  onResolve;

  @override
  Widget build(BuildContext context) {
    final pending = requests
        .where((request) => request['status'] == 'pending')
        .toList();
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const _SectionHeading(
          title: 'Parent Accounts',
          subtitle: 'Manage families and student access links',
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onAddRequest,
          icon: const Icon(Icons.link),
          label: const Text('Add parent-student link request'),
        ),
        const SizedBox(height: 20),
        const _SectionHeading(
          title: 'Linking Requests',
          subtitle: 'Verify parent email and Student ID before approval',
        ),
        const SizedBox(height: 10),
        if (pending.isEmpty)
          const _EmptyCard(
            icon: Icons.link_off_outlined,
            message: 'There are no pending parent-student link requests.',
          ),
        for (final request in pending)
          Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: Color(0xFFE8EAF2)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    request['parent_name'] as String? ??
                        request['parent_email'] as String? ??
                        'Parent',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(request['parent_email'] as String? ?? ''),
                  const SizedBox(height: 8),
                  Text(
                    'Student: ${request['student_name'] ?? 'Unknown student'} · '
                    '@${request['student_username'] ?? request['student_id']}',
                  ),
                  Text(
                    'Requested ${_formatDate(request['created_at'] as String?)}',
                    style: TextStyle(
                      color: Colors.blueGrey.shade600,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: () => onResolve(request, approve: true),
                        icon: const Icon(Icons.check),
                        label: const Text('Approve link'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => onResolve(request, approve: false),
                        icon: const Icon(Icons.close),
                        label: const Text('Reject'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 18),
        _SectionHeading(
          title: 'Verified Parent-Student Links',
          subtitle: '${links.length} approved view-only links',
        ),
        const SizedBox(height: 10),
        if (links.isEmpty)
          const _EmptyCard(
            icon: Icons.family_restroom_outlined,
            message: 'There are no approved parent-student links yet.',
          ),
        for (final link in links)
          Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.family_restroom_outlined),
              ),
              title: Text(
                link['parent_name'] as String? ??
                    link['parent_email'] as String? ??
                    'Parent',
              ),
              subtitle: Text(
                '${link['parent_email']} · @${link['student_username']}',
              ),
            ),
          ),
        const SizedBox(height: 18),
        _SectionHeading(
          title: 'Parent Accounts',
          subtitle: '${parents.length} registered families',
        ),
        const SizedBox(height: 10),
        if (parents.isEmpty)
          const _EmptyCard(
            icon: Icons.family_restroom_outlined,
            message: 'No parent accounts are registered yet.',
          ),
        for (final parent in parents)
          Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.family_restroom_outlined),
              ),
              title: Text(parent['display_name'] as String? ?? 'Parent'),
              subtitle: Text(parent['email'] as String? ?? ''),
            ),
          ),
      ],
    );
  }
}

class _DatabaseTab extends StatelessWidget {
  const _DatabaseTab({
    required this.students,
    required this.section,
    required this.gender,
    required this.tier,
    required this.search,
    required this.onSectionChanged,
    required this.onGenderChanged,
    required this.onTierChanged,
    required this.onSearchChanged,
    required this.onExport,
  });

  final List<Map<String, Object?>> students;
  final String section;
  final String gender;
  final String tier;
  final String search;
  final ValueChanged<String> onSectionChanged;
  final ValueChanged<String> onGenderChanged;
  final ValueChanged<String> onTierChanged;
  final ValueChanged<String> onSearchChanged;
  final Future<void> Function(List<Map<String, Object?>>) onExport;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const _SectionHeading(
          title: 'Academic Database',
          subtitle:
              'Section 2.10.1 · Filter student rosters for school reports',
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const ValueKey('studentRosterSearch'),
          initialValue: search,
          onChanged: onSearchChanged,
          decoration: const InputDecoration(
            labelText: 'Search students',
            hintText: 'Name or @username',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 760 ? 3 : 1;
            final itemWidth =
                (constraints.maxWidth - (columns - 1) * 12) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: itemWidth,
                  child: _FilterDropdown(
                    label: 'Filter by Section',
                    value: section,
                    values: const [
                      'All',
                      'Section A',
                      'Section B',
                      'Section C',
                    ],
                    onChanged: onSectionChanged,
                  ),
                ),
                SizedBox(
                  width: itemWidth,
                  child: _FilterDropdown(
                    label: 'Filter by Gender',
                    value: gender,
                    values: const ['All', 'Male', 'Female'],
                    onChanged: onGenderChanged,
                  ),
                ),
                SizedBox(
                  width: itemWidth,
                  child: _FilterDropdown(
                    label: 'Filter by Performance',
                    value: tier,
                    values: const [
                      'All',
                      'At Risk',
                      'Good',
                      'Excellent',
                      'Not assessed',
                    ],
                    onChanged: onTierChanged,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: () => onExport(students),
          icon: const Icon(Icons.download_outlined),
          label: const Text('Export to CSV'),
        ),
        const SizedBox(height: 10),
        Text(
          '${students.length} students match these filters.',
          style: TextStyle(color: Colors.blueGrey.shade600),
        ),
        const SizedBox(height: 10),
        if (students.isEmpty)
          const _EmptyCard(
            icon: Icons.filter_alt_off_outlined,
            message: 'No student records match the selected filters.',
          ),
        if (students.isNotEmpty)
          Card(
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('ID')),
                  DataColumn(label: Text('Name')),
                  DataColumn(label: Text('Section')),
                  DataColumn(label: Text('Gender')),
                  DataColumn(label: Text('Average Score')),
                  DataColumn(label: Text('Status')),
                ],
                rows: [
                  for (final student in students)
                    DataRow(
                      cells: [
                        DataCell(
                          Text(
                            student['school_id'] as String? ??
                                student['student_username'] as String? ??
                                student['id'] as String? ??
                                '—',
                          ),
                        ),
                        DataCell(
                          Text(student['display_name'] as String? ?? 'Student'),
                        ),
                        DataCell(Text(student['section'] as String? ?? '—')),
                        DataCell(Text(student['gender'] as String? ?? '—')),
                        DataCell(
                          Text(
                            _score(student)?.toStringAsFixed(1) ??
                                'Not assessed',
                          ),
                        ),
                        DataCell(
                          _StatusChip(
                            status: student['status'] as String? ?? 'active',
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _TeachersTab extends StatelessWidget {
  const _TeachersTab({
    required this.teachers,
    required this.onResetPassword,
    required this.onAddTeacher,
  });

  final List<Map<String, Object?>> teachers;
  final Future<void> Function(Map<String, Object?>) onResetPassword;
  final VoidCallback onAddTeacher;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        _SectionHeading(
          title: 'Teacher Management & Settings',
          subtitle:
              '${teachers.length} assigned teachers · subject assignments and account access',
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: onAddTeacher,
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Add Teacher'),
          ),
        ),
        const SizedBox(height: 12),
        if (teachers.isEmpty)
          const _EmptyCard(
            icon: Icons.cast_for_education_outlined,
            message: 'No teacher accounts are registered yet.',
          ),
        _TeacherCardsGrid(teachers: teachers, onResetPassword: onResetPassword),
      ],
    );
  }
}

class _TeacherCardsGrid extends StatelessWidget {
  const _TeacherCardsGrid({
    required this.teachers,
    required this.onResetPassword,
  });

  final List<Map<String, Object?>> teachers;
  final Future<void> Function(Map<String, Object?>) onResetPassword;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 760 ? 2 : 1;
      final itemWidth = (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final teacher in teachers)
            _teacherCard(teacher, onResetPassword, itemWidth),
        ],
      );
    },
  );
}

Widget _teacherCard(
  Map<String, Object?> teacher,
  Future<void> Function(Map<String, Object?>) onResetPassword,
  double itemWidth,
) {
  final assignedSubjects = teacher['assigned_subjects'] as String? ?? '';
  return SizedBox(
    width: itemWidth,
    child: Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE8EAF2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              teacher['display_name'] as String? ?? 'Teacher',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(
              teacher['email'] as String? ?? '',
              style: TextStyle(color: Colors.blueGrey.shade600),
            ),
            Text(
              teacher['school'] as String? ?? 'AMU Community School',
              style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Chip(
              avatar: const Icon(Icons.menu_book_outlined, size: 16),
              label: Text(
                assignedSubjects.isNotEmpty
                    ? assignedSubjects
                    : 'Subject not assigned',
              ),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: () => onResetPassword(teacher),
              icon: const Icon(Icons.lock_reset_outlined),
              label: const Text('Reset Password'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _TeacherDraft {
  const _TeacherDraft({
    required this.name,
    required this.email,
    required this.subject,
    required this.password,
  });

  final String name;
  final String email;
  final String subject;
  final String password;
}

class _TeacherDialog extends StatefulWidget {
  const _TeacherDialog();

  @override
  State<_TeacherDialog> createState() => _TeacherDialogState();
}

class _TeacherDialogState extends State<_TeacherDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  static const _subjects = [
    'Math',
    'English',
    'General Science',
    'Social Studies',
    'Citizenship',
    'Gamo',
  ];
  String _subject = _subjects.first;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add teacher account'),
    content: Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Full name'),
              validator: (value) => value?.trim().isNotEmpty == true
                  ? null
                  : 'Enter the teacher name.',
            ),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (value) =>
                  value?.contains('@') == true ? null : 'Enter a valid email.',
            ),
            DropdownButtonFormField<String>(
              initialValue: _subject,
              decoration: const InputDecoration(
                labelText: 'Assigned Grade 8 subject',
              ),
              items: _subjects
                  .map(
                    (subject) =>
                        DropdownMenuItem(value: subject, child: Text(subject)),
                  )
                  .toList(),
              onChanged: (subject) {
                if (subject != null) setState(() => _subject = subject);
              },
            ),
            TextFormField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Initial password',
                helperText: 'At least 8 characters',
              ),
              validator: (value) => (value?.length ?? 0) >= 8
                  ? null
                  : 'Use at least 8 characters.',
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!(_formKey.currentState?.validate() ?? false)) return;
          Navigator.pop(
            context,
            _TeacherDraft(
              name: _name.text.trim(),
              email: _email.text.trim(),
              subject: _subject,
              password: _password.text,
            ),
          );
        },
        child: const Text('Create account'),
      ),
    ],
  );
}

class _ParentLinkDraft {
  const _ParentLinkDraft({required this.email, required this.studentId});

  final String email;
  final String studentId;
}

class _ParentLinkDialog extends StatefulWidget {
  const _ParentLinkDialog();

  @override
  State<_ParentLinkDialog> createState() => _ParentLinkDialogState();
}

class _ParentLinkDialogState extends State<_ParentLinkDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _email;
  late final TextEditingController _studentId;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController();
    _studentId = TextEditingController();
  }

  @override
  void dispose() {
    _email.dispose();
    _studentId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add linking request'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Parent email'),
              validator: (value) =>
                  value?.contains('@') == true ? null : 'Enter a parent email.',
            ),
            TextFormField(
              controller: _studentId,
              decoration: const InputDecoration(
                labelText: 'Student username, ID, or School ID',
              ),
              validator: (value) => value?.trim().isNotEmpty == true
                  ? null
                  : 'Enter a student ID.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.pop(
              context,
              _ParentLinkDraft(
                email: _email.text.trim(),
                studentId: _studentId.text.trim(),
              ),
            );
          },
          child: const Text('Submit request'),
        ),
      ],
    );
  }
}

class _AdminData {
  const _AdminData({
    required this.counts,
    required this.students,
    required this.distribution,
    required this.teachers,
    required this.parents,
    required this.parentRequests,
    required this.parentLinks,
  });

  final Map<String, int> counts;
  final List<Map<String, Object?>> students;
  final Map<String, Object?> distribution;
  final List<Map<String, Object?>> teachers;
  final List<Map<String, Object?>> parents;
  final List<Map<String, Object?>> parentRequests;
  final List<Map<String, Object?>> parentLinks;
}

class _AdminTab {
  const _AdminTab(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 3),
      Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
      ),
    ],
  );
}

class _HealthRow extends StatelessWidget {
  const _HealthRow({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Icon(Icons.circle, size: 10, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(value, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    ),
  );
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
    required this.color,
    this.online = false,
    this.onTap,
  });

  final String label;
  final String value;
  final String caption;
  final IconData icon;
  final Color color;
  final bool online;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(20);
    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
        ),
        border: Border.all(color: const Color(0xFF334155)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00E5FF).withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        icon,
                        color: online ? const Color(0xFF00E5FF) : color,
                        size: 20,
                      ),
                      const Spacer(),
                      if (online) const _OnlinePulse(),
                    ],
                  ),
                  const Spacer(),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      style: TextStyle(
                        color: online ? const Color(0xFF34D399) : Colors.white,
                        fontSize: online ? 24 : 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFFCBD5E1),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OnlinePulse extends StatefulWidget {
  const _OnlinePulse();

  @override
  State<_OnlinePulse> createState() => _OnlinePulseState();
}

class _OnlinePulseState extends State<_OnlinePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) => Container(
      width: 9 + _controller.value * 3,
      height: 9 + _controller.value * 3,
      decoration: BoxDecoration(
        color: const Color(0xFF10B981),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withValues(alpha: 0.3),
            blurRadius: 4 + _controller.value * 7,
            spreadRadius: 1 + _controller.value * 2,
          ),
        ],
      ),
    ),
  );
}

class _GradeCard extends StatelessWidget {
  const _GradeCard({
    required this.percent,
    required this.label,
    required this.detail,
    required this.color,
    this.onTap,
  });

  final int percent;
  final String label;
  final String detail;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(17);
    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: const LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
        ),
        border: Border.all(color: color.withValues(alpha: 0.65)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.16),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '$percent%',
                      style: TextStyle(
                        color: color,
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DistributionGauge extends CustomPainter {
  const _DistributionGauge({
    required this.excellent,
    required this.good,
    required this.atRisk,
  });

  final int excellent;
  final int good;
  final int atRisk;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = math.min(20.0, size.height * 0.15);
    final radius = math.min(size.width / 2 - stroke, size.height - stroke);
    if (radius <= 0) return;
    final center = Offset(size.width / 2, size.height - stroke / 2);
    final rect = Rect.fromCircle(center: center, radius: radius);
    final track = Paint()
      ..color = const Color(0xFFE9EDF5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, math.pi, math.pi, false, track);

    final total = excellent + good + atRisk;
    if (total == 0) return;
    final values = [
      (excellent, const Color(0xFF059669)),
      (good, const Color(0xFFF59E0B)),
      (atRisk, const Color(0xFFE11D48)),
    ];
    var start = math.pi;
    for (final (value, color) in values) {
      if (value == 0) continue;
      final sweep = math.pi * value / total;
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DistributionGauge oldDelegate) =>
      excellent != oldDelegate.excellent ||
      good != oldDelegate.good ||
      atRisk != oldDelegate.atRisk;
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(fontSize: 10)),
    ],
  );
}

class _CountBanner extends StatelessWidget {
  const _CountBanner({
    required this.count,
    required this.label,
    required this.color,
  });

  final int count;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        Text(
          '$count',
          style: TextStyle(
            color: color,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label, style: TextStyle(color: color)),
        ),
        Icon(Icons.pending_actions_outlined, color: color),
      ],
    ),
  );
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Icon(icon, size: 15, color: Colors.blueGrey.shade500),
        const SizedBox(width: 7),
        Text(
          '$label: ',
          style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 12),
        ),
        Expanded(
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'approved' || 'active' || 'excellent' => const Color(0xFF059669),
      'pending' => const Color(0xFF0284C7),
      'good' => const Color(0xFFF59E0B),
      'blocked' || 'rejected' || 'at_risk' => const Color(0xFFE11D48),
      _ => const Color(0xFF64748B),
    };
    final label = (status == 'approved' ? 'active' : status).replaceAll(
      '_',
      ' ',
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> values;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: values.contains(value) ? value : values.first,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: label,
      filled: true,
      fillColor: AppColors.iceBlue,
    ),
    items: values
        .map(
          (item) => DropdownMenuItem(
            value: item,
            child: Text(
              switch (item) {
                'At Risk' => '<50% At-Risk',
                'Good' => '50–74% Good',
                'Excellent' => '≥75% Excellent',
                _ => item,
              },
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        )
        .toList(),
    onChanged: (item) {
      if (item != null) onChanged(item);
    },
  );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    color: AppColors.iceBlue,
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          Icon(icon, color: Colors.blueGrey.shade400, size: 28),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.blueGrey.shade600),
          ),
        ],
      ),
    ),
  );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 36),
          const SizedBox(height: 10),
          const Text('Could not load the admin dashboard.'),
          const SizedBox(height: 4),
          Text('$error', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}

double? _score(Map<String, Object?> student) {
  final value = student['average_score'];
  if (value is num) return value.toDouble().clamp(0, 100).toDouble();
  final parsed = double.tryParse(value?.toString() ?? '');
  return parsed?.clamp(0, 100).toDouble();
}

String _syncStateLabel(SyncStatus status) => switch (status.state) {
  SyncState.idle => 'Ready · not yet synced',
  SyncState.syncing => 'Syncing',
  SyncState.synced => 'Connected · up to date',
  SyncState.offline => 'Offline · local cache active',
  SyncState.error => status.message ?? 'Sync needs attention',
};

int _percent(int value, int total) =>
    total == 0 ? 0 : (value * 100 / total).round();

String _formatDate(String? value) {
  final date = DateTime.tryParse(value ?? '');
  if (date == null) return 'Unknown';
  final local = date.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

bool _isBrowserDownload(String location) =>
    location.startsWith('SAAMEP_Grade8_Roster.csv');
