import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:i_am_astudent/database/db_helper.dart';

class AdminProvider extends ChangeNotifier {
  int totalStudents = 0;
  int totalTeachers = 0;
  int totalParents = 0;

  List<Map<String, Object?>> pendingStudentsList = [];
  List<Map<String, Object?>> activeStudentsList = [];
  List<Map<String, Object?>> blockedStudentsList = [];
  List<Map<String, Object?>> studentsList = [];
  List<Map<String, Object?>> filteredStudentsList = [];
  List<Map<String, Object?>> teachersList = [];
  List<Map<String, Object?>> parentsList = [];
  List<Map<String, Object?>> parentRequestsList = [];
  List<Map<String, Object?>> parentLinksList = [];
  Map<String, Object?> gradeDistribution = {};

  String filterSection = 'All';
  String filterGender = 'All';
  String filterScore = 'All';
  String searchQuery = '';

  bool isLoading = true;
  Object? loadError;

  Future<void> fetchDashboardStats() async {
    isLoading = true;
    loadError = null;
    notifyListeners();
    try {
      final counts = await DbHelper.instance.getAdminRoleCounts();
      final students = await DbHelper.instance.getAdminStudents();
      final distribution = await DbHelper.instance.getGradeDistribution();
      final teachers = await DbHelper.instance.getAdminTeachers();
      final parents = await DbHelper.instance.getAdminParents();
      final requests = await DbHelper.instance.getParentLinkRequests();
      final links = await DbHelper.instance.getVerifiedParentLinks();
      final filters = await DbHelper.instance.getAdminFilters();
      final savedSearch = await DbHelper.instance.getAdminSearch();

      totalStudents = students.length;
      totalTeachers = counts['teacher'] ?? teachers.length;
      totalParents = counts['parent'] ?? parents.length;
      studentsList = students;
      pendingStudentsList = _withStatus(students, {'pending'});
      activeStudentsList = _withStatus(students, {'active', 'approved'});
      blockedStudentsList = _withStatus(students, {'blocked', 'rejected'});
      teachersList = teachers;
      parentsList = parents;
      parentRequestsList = requests;
      parentLinksList = links;
      gradeDistribution = distribution;
      filterSection = _safeFilter(filters['section'], const [
        'All',
        'Section A',
        'Section B',
        'Section C',
      ]);
      filterGender = _safeFilter(filters['gender'], const [
        'All',
        'Male',
        'Female',
      ]);
      filterScore = _safeFilter(_normalizeScoreFilter(filters['tier']), const [
        'All',
        'At Risk',
        'Good',
        'Excellent',
        'Not assessed',
      ]);
      searchQuery = savedSearch;
      _updateFilteredStudents();
      isLoading = false;
      notifyListeners();
    } catch (error) {
      isLoading = false;
      loadError = error;
      notifyListeners();
    }
  }

  Future<void> approveStudent(String studentId) async {
    await DbHelper.instance.approveStudent(studentId);
    await fetchDashboardStats();
    _throwLoadError();
  }

  Future<void> rejectStudent(String studentId) async {
    await DbHelper.instance.rejectPendingStudent(studentId);
    await fetchDashboardStats();
    _throwLoadError();
  }

  Future<void> blockStudent(String studentId) async {
    await DbHelper.instance.updateUserStatus(studentId, 'blocked');
    await fetchDashboardStats();
    _throwLoadError();
  }

  Future<void> unblockStudent(String studentId) async {
    await DbHelper.instance.updateUserStatus(studentId, 'active');
    await fetchDashboardStats();
    _throwLoadError();
  }

  Future<String> resetTeacherPassword(String teacherId) async {
    final temporaryPassword = _generateTemporaryPassword();
    final password = await DbHelper.instance.resetTeacherPassword(
      teacherId,
      temporaryPassword,
    );
    await fetchDashboardStats();
    _throwLoadError();
    return password;
  }

  Future<void> applyDatabaseFilters(
    String section,
    String gender,
    String scoreRange, {
    String? search,
  }) async {
    filterSection = _safeFilter(section, const [
      'All',
      'Section A',
      'Section B',
      'Section C',
    ]);
    filterGender = _safeFilter(gender, const ['All', 'Male', 'Female']);
    filterScore = _safeFilter(_normalizeScoreFilter(scoreRange), const [
      'All',
      'At Risk',
      'Good',
      'Excellent',
      'Not assessed',
    ]);
    if (search != null) searchQuery = search;
    _updateFilteredStudents();
    notifyListeners();
    await DbHelper.instance.saveAdminFilters(
      section: filterSection,
      gender: filterGender,
      tier: filterScore,
    );
    if (search != null) await DbHelper.instance.saveAdminSearch(search);
  }

  List<Map<String, Object?>> _withStatus(
    List<Map<String, Object?>> students,
    Set<String> statuses,
  ) => students
      .where((student) => statuses.contains(_studentStatus(student)))
      .toList(growable: false);

  void _updateFilteredStudents() {
    final query = searchQuery.trim().toLowerCase().replaceFirst('@', '');
    filteredStudentsList = studentsList
        .where((student) {
          final section = (student['section']?.toString() ?? '')
              .replaceFirst('Section ', '')
              .toLowerCase();
          final selectedSection = filterSection
              .replaceFirst('Section ', '')
              .toLowerCase();
          final gender = student['gender']?.toString() ?? '';
          final score = _score(student);
          final tier = _scoreTier(score);
          final matchesQuery =
              query.isEmpty ||
              [
                student['display_name'],
                student['student_username'],
                student['email'],
                student['school_id'],
              ].any(
                (value) =>
                    value?.toString().toLowerCase().contains(query) == true,
              );
          return (filterSection == 'All' || section == selectedSection) &&
              (filterGender == 'All' ||
                  gender.toLowerCase() == filterGender.toLowerCase()) &&
              (filterScore == 'All' || tier == filterScore) &&
              matchesQuery;
        })
        .toList(growable: false);
  }

  void _throwLoadError() {
    final error = loadError;
    if (error != null) throw StateError('Could not reload admin data: $error');
  }

  String _generateTemporaryPassword() {
    const alphabet =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#';
    final random = math.Random.secure();
    return List.generate(
      14,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  String _safeFilter(Object? value, List<String> values) =>
      value is String && values.contains(value) ? value : values.first;

  String _normalizeScoreFilter(Object? value) {
    final filter = value?.toString().toLowerCase() ?? 'all';
    return switch (filter) {
      'at_risk' || 'at-risk' || 'at risk' || '<50% at-risk' => 'At Risk',
      'good' || '50-74% good' || '50–74% good' => 'Good',
      'excellent' || '>=75% excellent' || '≥75% excellent' => 'Excellent',
      'not assessed' || 'not_assessed' => 'Not assessed',
      _ => value?.toString() ?? 'All',
    };
  }

  String _studentStatus(Map<String, Object?> student) =>
      (student['status'] as String? ??
              student['account_status'] as String? ??
              'active')
          .toLowerCase();

  double? _score(Map<String, Object?> student) {
    final value = student['average_score'];
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  String _scoreTier(double? score) {
    if (score == null) return 'Not assessed';
    if (score < 50) return 'At Risk';
    if (score < 75) return 'Good';
    return 'Excellent';
  }
}
