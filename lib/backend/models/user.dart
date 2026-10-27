class User {
  const User({
    required this.id,
    required this.email,
    required this.displayName,
    required this.role,
    required this.createdAt,
    this.parentEmail,
    this.school = 'AMU Community School',
    this.studentUsername,
    this.section,
    this.gender,
    this.teacherSubject,
    this.status = 'active',
    this.parentLinks = const [],
  });

  final String id;
  final String email;
  final String displayName;
  final String role;
  final String? parentEmail;
  final String school;
  final String? studentUsername;
  final String? section;
  final String? gender;
  final String? teacherSubject;
  final String status;
  final List<ParentLink> parentLinks;
  final DateTime createdAt;

  factory User.fromMap(Map<String, Object?> map) => User(
    id: map['id']! as String,
    email: map['email']! as String,
    displayName: map['display_name']! as String,
    role: map['role']! as String,
    parentEmail: map['parent_email'] as String?,
    school: map['school'] as String? ?? 'AMU Community School',
    studentUsername: map['student_username'] as String?,
    section: map['section'] as String?,
    gender: map['gender'] as String?,
    teacherSubject: map['assigned_subjects'] as String?,
    parentLinks: (map['parent_links'] as List<Object?>? ?? [])
        .whereType<Map<String, Object?>>()
        .map(ParentLink.fromMap)
        .toList(growable: false),
    status: switch (map['status'] ?? map['account_status']) {
      'pending' => 'pending',
      'blocked' || 'rejected' => 'blocked',
      _ => 'active',
    },
    createdAt: DateTime.parse(map['created_at']! as String),
  );

  Map<String, Object?> toMap({bool isSynced = false}) => {
    'id': id,
    'email': email,
    'display_name': displayName,
    'role': role,
    'parent_email': parentEmail,
    'school': school,
    'student_username': studentUsername,
    'section': section,
    'gender': gender,
    'assigned_subjects': teacherSubject,
    'parent_links': parentLinks.map((link) => link.toMap()).toList(),
    'account_status': switch (status) {
      'pending' => 'pending',
      'blocked' => 'blocked',
      _ => 'approved',
    },
    'status': status,
    'created_at': createdAt.toUtc().toIso8601String(),
    'is_synced': isSynced ? 1 : 0,
  };
}

class ParentLink {
  const ParentLink({
    required this.id,
    required this.parentEmail,
    required this.studentUsername,
    required this.status,
    required this.requestedAt,
  });

  final String id;
  final String parentEmail;
  final String studentUsername;
  final String status;
  final DateTime requestedAt;

  factory ParentLink.fromMap(Map<String, Object?> map) => ParentLink(
    id: map['id']! as String,
    parentEmail: map['parent_email']! as String,
    studentUsername: map['student_username']! as String,
    status: map['status']! as String,
    requestedAt: DateTime.parse(map['requested_at']! as String),
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'parent_email': parentEmail,
    'student_username': studentUsername,
    'status': status,
    'requested_at': requestedAt.toUtc().toIso8601String(),
  };
}
