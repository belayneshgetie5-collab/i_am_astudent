import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import 'database_factory_setup.dart'
    if (dart.library.io) 'database_factory_setup_io.dart'
    if (dart.library.js_interop) 'database_factory_setup_web.dart'
    as database_setup;

class DbHelper {
  DbHelper._();

  static final DbHelper instance = DbHelper._();
  static const _databaseName = 'saamep.db';
  static const _databaseVersion = 17;
  static const _firstRunAdminEmail = 'jerykan@gmail.com';
  static const _firstRunAdminPassword = 'eyerus@1234';
  static const _legacyFirstRunAdminEmail = 'jerykan990@gmail.com';
  static const supportedRoles = <String>[
    'student',
    'teacher',
    'parent',
    'admin',
  ];
  static const _legacyStudentDemoPassword = 'StudentPass123!';
  static const demoAccounts = <String, String>{
    'student': 'student@saamep.com',
    'teacher': 'teacher@saamep.com',
    'parent': 'parent@saamep.com',
    'admin': 'admin@saamep.com',
  };
  static const demoPasswords = <String, String>{
    'student': 'password123',
    'teacher': 'TeacherPass123!',
    'parent': 'ParentPass123!',
    'admin': 'AdminPass123!',
  };
  static const syncableTables = <String>[
    'users',
    'quizzes',
    'questions',
    'user_scores',
    'offline_pdfs',
    'offline_textbooks',
  ];

  static const _credentialIterations = 50000;
  Future<Database>? _database;
  Future<void>? _initializing;

  Future<void> initialize() {
    return _initializing ??= database_setup.initializeDatabaseFactory(
      isWeb: kIsWeb,
    );
  }

  bool isDemoAccount(String email) =>
      demoAccounts.values.contains(_normalizeEmail(email));

  Future<Database> get database {
    return _database ??= _openDatabase();
  }

  Future<Database> _openDatabase() async {
    await initialize();
    final databasesPath = await getDatabasesPath();
    return openDatabase(
      path.join(databasesPath, _databaseName),
      version: _databaseVersion,
      onCreate: _createSchema,
      onUpgrade: _upgradeSchema,
    );
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        email TEXT NOT NULL UNIQUE,
        display_name TEXT NOT NULL,
        role TEXT NOT NULL,
        parent_email TEXT,
        school TEXT NOT NULL DEFAULT 'AMU Community School',
        school_id TEXT,
        section TEXT,
        gender TEXT,
        student_username TEXT,
        assigned_subjects TEXT,
        status TEXT NOT NULL DEFAULT 'active',
        account_status TEXT NOT NULL DEFAULT 'approved',
        approved_at TEXT,
        force_password_reset INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE local_credentials (
        email TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        salt TEXT NOT NULL,
        password_hash TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE quizzes (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT,
        created_by TEXT,
        cached_at TEXT NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE questions (
        id TEXT PRIMARY KEY,
        quiz_id TEXT NOT NULL,
        prompt TEXT NOT NULL,
        options_json TEXT NOT NULL,
        answer TEXT NOT NULL,
        explanation TEXT,
        is_synced INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE user_scores (
        id TEXT PRIMARY KEY,
        student_email TEXT NOT NULL,
        quiz_id TEXT NOT NULL,
        score REAL NOT NULL,
        total REAL NOT NULL,
        completed_at TEXT NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await _createStudentProgressTables(db);
    await db.execute('''
      CREATE TABLE offline_pdfs (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        local_path TEXT NOT NULL,
        cached_at TEXT NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE offline_textbooks (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        created_by TEXT,
        cached_at TEXT NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await _createDeletionQueue(db);
    await db.execute(
      'CREATE INDEX idx_questions_quiz_id ON questions(quiz_id)',
    );
    await db.execute(
      'CREATE INDEX idx_user_scores_student ON user_scores(student_email)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX idx_users_student_username '
      'ON users(lower(trim(student_username))) '
      "WHERE student_username IS NOT NULL AND trim(student_username) != ''",
    );
    await db.execute('''
      CREATE TABLE exam_results (
        id TEXT PRIMARY KEY,
        student_username TEXT NOT NULL,
        subject_name TEXT NOT NULL,
        score_percentage REAL NOT NULL CHECK (score_percentage >= 0 AND score_percentage <= 100),
        completed_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE parent_links (
        id TEXT PRIMARY KEY,
        parent_email TEXT NOT NULL,
        parent_name TEXT NOT NULL,
        student_username TEXT NOT NULL,
        school TEXT NOT NULL DEFAULT 'AMU Community School',
        status TEXT NOT NULL DEFAULT 'pending',
        requested_at TEXT NOT NULL
      )
    ''');
    await _createAdminTables(db);
    await _seedFirstRunAccounts(db);
    await _seedDemoUsers(db);
    await _seedStudyContent(db);
    await _seedInitialAdminData(db);
  }

  Future<void> _upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS local_credentials (
          email TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          salt TEXT NOT NULL,
          password_hash TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS settings (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS offline_textbooks (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          content TEXT NOT NULL,
          created_by TEXT,
          cached_at TEXT NOT NULL,
          is_synced INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await _addColumnIfMissing(db, 'users', 'parent_email', 'TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS user_scores (
          id TEXT PRIMARY KEY,
          student_email TEXT NOT NULL,
          quiz_id TEXT NOT NULL,
          score REAL NOT NULL,
          total REAL NOT NULL,
          completed_at TEXT NOT NULL,
          is_synced INTEGER NOT NULL DEFAULT 0
        )
      ''');
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name = 'student_scores'",
      );
      if (tables.isNotEmpty) {
        await db.execute('''
          INSERT OR IGNORE INTO user_scores
            (id, student_email, quiz_id, score, total, completed_at, is_synced)
          SELECT id, student_email, quiz_id, score, total, completed_at, is_synced
          FROM student_scores
        ''');
      }
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_user_scores_student '
        'ON user_scores(student_email)',
      );
    }
    if (oldVersion < 4) await _createDeletionQueue(db);
    if (oldVersion < 8) await _migrateStudentDemoPassword(db);
    if (oldVersion < 6) await _seedDemoUsers(db);
    if (oldVersion < 10) {
      await _createStudentProgressTables(db);
      await _migrateStudentScores(db);
    }
    if (oldVersion < 13) {
      await _addColumnIfMissing(db, 'users', 'school_id', 'TEXT');
      await _addColumnIfMissing(db, 'users', 'section', 'TEXT');
      await _addColumnIfMissing(db, 'users', 'gender', 'TEXT');
      await _addColumnIfMissing(db, 'users', 'assigned_subjects', 'TEXT');
      await _addColumnIfMissing(
        db,
        'users',
        'account_status',
        "TEXT NOT NULL DEFAULT 'approved'",
      );
      await _createAdminTables(db);
    }
    if (oldVersion < 14) {
      await _addColumnIfMissing(
        db,
        'users',
        'school',
        "TEXT NOT NULL DEFAULT 'AMU Community School'",
      );
      await _addColumnIfMissing(db, 'users', 'student_username', 'TEXT');
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_users_student_username '
        'ON users(lower(trim(student_username))) '
        "WHERE student_username IS NOT NULL AND trim(student_username) != ''",
      );
      final students = await db.query(
        'users',
        columns: ['id', 'email'],
        where:
            "lower(trim(role)) = 'student' AND "
            "(student_username IS NULL OR trim(student_username) = '')",
      );
      for (final student in students) {
        final id = student['id']! as String;
        final email = student['email']! as String;
        final localPart = email.split('@').first;
        final base = localPart
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9._-]'), '')
            .replaceAll(RegExp(r'^[._-]+|[._-]+$'), '');
        final safeId = id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
        final suffix = safeId.substring(
          safeId.length > 12 ? safeId.length - 12 : 0,
        );
        final usernameBase = base.isEmpty ? 'student' : base;
        final username =
            '${usernameBase.substring(0, usernameBase.length > 32 - suffix.length - 1 ? 32 - suffix.length - 1 : usernameBase.length)}_$suffix';
        await db.update(
          'users',
          {'student_username': username},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    }
    if (oldVersion < 15) {
      await _addColumnIfMissing(
        db,
        'users',
        'status',
        "TEXT NOT NULL DEFAULT 'active'",
      );
      await db.execute('''
        UPDATE users
        SET status = CASE
          WHEN account_status = 'pending' THEN 'pending'
          WHEN account_status IN ('blocked', 'rejected') THEN 'blocked'
          ELSE 'active'
        END
      ''');
    }
    if (oldVersion < 16) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS exam_results (
          id TEXT PRIMARY KEY,
          student_username TEXT NOT NULL,
          subject_name TEXT NOT NULL,
          score_percentage REAL NOT NULL CHECK (
            score_percentage >= 0 AND score_percentage <= 100
          ),
          completed_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS parent_links (
          id TEXT PRIMARY KEY,
          parent_email TEXT NOT NULL,
          parent_name TEXT NOT NULL,
          student_username TEXT NOT NULL,
          school TEXT NOT NULL DEFAULT 'AMU Community School',
          status TEXT NOT NULL DEFAULT 'pending',
          requested_at TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 17) {
      await _addColumnIfMissing(db, 'users', 'approved_at', 'TEXT');
      await _addColumnIfMissing(
        db,
        'users',
        'force_password_reset',
        'INTEGER NOT NULL DEFAULT 0',
      );
    }
    await _seedFirstRunAccounts(db);
    await _seedStudyContent(db);
    await _seedInitialAdminData(db);
  }

  Future<void> _createAdminTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS parent_link_requests (
        id TEXT PRIMARY KEY,
        parent_email TEXT NOT NULL,
        student_id TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS parent_links (
        id TEXT PRIMARY KEY,
        parent_email TEXT NOT NULL,
        parent_name TEXT NOT NULL,
        student_username TEXT NOT NULL,
        school TEXT NOT NULL DEFAULT 'AMU Community School',
        status TEXT NOT NULL DEFAULT 'pending',
        requested_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      INSERT OR IGNORE INTO parent_links
        (id, parent_email, parent_name, student_username, school, status,
         requested_at)
      SELECT requests.id, requests.parent_email,
        COALESCE(parent.display_name, requests.parent_email),
        COALESCE(student.student_username, requests.student_id),
        COALESCE(student.school, 'AMU Community School'),
        requests.status, requests.created_at
      FROM parent_link_requests AS requests
      LEFT JOIN users AS parent
        ON lower(trim(parent.email)) = lower(trim(requests.parent_email))
      LEFT JOIN users AS student
        ON student.id = requests.student_id
        OR student.school_id = requests.student_id
    ''');
  }

  Future<void> _createStudentProgressTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_stats (
        user_id TEXT PRIMARY KEY,
        total_exams_taken INTEGER NOT NULL DEFAULT 0,
        average_score REAL NOT NULL DEFAULT 0.0,
        study_streak INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS exam_attempts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL,
        subject TEXT NOT NULL,
        year TEXT NOT NULL,
        score REAL NOT NULL DEFAULT 0,
        total_questions INTEGER NOT NULL DEFAULT 0,
        completed_at TEXT NOT NULL,
        status TEXT NOT NULL CHECK (status IN ('completed', 'in_progress')),
        quiz_id TEXT,
        answers_json TEXT NOT NULL DEFAULT '[]',
        question_index INTEGER NOT NULL DEFAULT 0,
        seconds_remaining INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_exam_attempts_user_recent '
      'ON exam_attempts(user_id, completed_at DESC)',
    );
  }

  Future<void> _migrateStudentScores(DatabaseExecutor db) async {
    await db.execute('''
      INSERT INTO exam_attempts
        (user_id, subject, year, score, total_questions, completed_at, status)
      SELECT users.id, COALESCE(quizzes.title, 'Practice exam'), '',
        user_scores.score, CAST(user_scores.total AS INTEGER),
        user_scores.completed_at, 'completed'
      FROM user_scores
      INNER JOIN users ON lower(trim(users.email)) = user_scores.student_email
      LEFT JOIN quizzes ON quizzes.id = user_scores.quiz_id
      WHERE lower(trim(users.role)) = 'student'
        AND user_scores.total > 0
        AND NOT EXISTS (
          SELECT 1 FROM exam_attempts
          WHERE exam_attempts.user_id = users.id
            AND exam_attempts.completed_at = user_scores.completed_at
            AND exam_attempts.score = user_scores.score
        )
    ''');
    final students = await db.query(
      'users',
      columns: ['id'],
      where: 'lower(trim(role)) = ?',
      whereArgs: ['student'],
    );
    for (final student in students) {
      await _updateStudentStats(db, student['id']! as String);
    }
  }

  Future<void> _updateStudentStats(DatabaseExecutor db, String userId) async {
    final totals = await db.rawQuery(
      'SELECT COUNT(*) AS total_exams_taken, '
      'COALESCE(AVG(score * 100.0 / total_questions), 0.0) AS average_score '
      'FROM exam_attempts '
      "WHERE user_id = ? AND status = 'completed' AND total_questions > 0",
      [userId],
    );
    final studyDays = await db.rawQuery(
      'SELECT date(completed_at) AS study_date FROM exam_attempts '
      "WHERE user_id = ? AND status = 'completed' "
      'GROUP BY date(completed_at) ORDER BY study_date DESC',
      [userId],
    );
    var streak = studyDays.isEmpty ? 1 : 0;
    if (studyDays.isNotEmpty) {
      final today = DateTime.now().toUtc();
      var expected = DateTime.utc(today.year, today.month, today.day);
      final mostRecent = DateTime.tryParse(
        studyDays.first['study_date'] as String? ?? '',
      );
      if (mostRecent != null) {
        final recentDay = DateTime.utc(
          mostRecent.year,
          mostRecent.month,
          mostRecent.day,
        );
        if (recentDay == expected.subtract(const Duration(days: 1))) {
          expected = expected.subtract(const Duration(days: 1));
        } else if (recentDay != expected) {
          expected = recentDay;
          streak = 0;
        }
        for (final row in studyDays) {
          final parsed = DateTime.tryParse(row['study_date'] as String? ?? '');
          if (parsed == null) break;
          final day = DateTime.utc(parsed.year, parsed.month, parsed.day);
          if (day != expected) break;
          streak++;
          expected = expected.subtract(const Duration(days: 1));
        }
        if (streak == 0) streak = 1;
      }
    }
    await db.insert('user_stats', {
      'user_id': userId,
      'total_exams_taken': totals.first['total_exams_taken'],
      'average_score': totals.first['average_score'],
      'study_streak': streak,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _seedFirstRunAccounts(DatabaseExecutor db) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final accounts = [
      (
        id: 'first-run-admin',
        email: _firstRunAdminEmail,
        name: 'SAAMEP Administrator',
        role: 'admin',
        password: _firstRunAdminPassword,
      ),
      (
        id: 'demo-student',
        email: demoAccounts['student']!,
        name: 'Mina Student',
        role: 'student',
        password: demoPasswords['student']!,
      ),
    ];
    for (final account in accounts) {
      if (account.role == 'admin') {
        final legacyAdmin = await db.query(
          'users',
          columns: ['email'],
          where: 'lower(trim(email)) = ?',
          whereArgs: [_legacyFirstRunAdminEmail],
          limit: 1,
        );
        final currentAdmin = await db.query(
          'users',
          columns: ['email'],
          where: 'lower(trim(email)) = ?',
          whereArgs: [_normalizeEmail(account.email)],
          limit: 1,
        );
        if (legacyAdmin.isNotEmpty && currentAdmin.isEmpty) {
          await db.update(
            'users',
            {
              'email': account.email,
              'display_name': account.name,
              'role': account.role,
            },
            where: 'lower(trim(email)) = ?',
            whereArgs: [_legacyFirstRunAdminEmail],
          );
          await db.update(
            'local_credentials',
            {'email': account.email},
            where: 'lower(trim(email)) = ?',
            whereArgs: [_legacyFirstRunAdminEmail],
          );
        }

        final adminUsers = await db.query(
          'users',
          columns: ['id'],
          where: 'lower(trim(email)) = ?',
          whereArgs: [_normalizeEmail(account.email)],
          limit: 1,
        );
        if (adminUsers.isNotEmpty) continue;

        await db.insert('users', {
          'id': account.id,
          'email': account.email,
          'display_name': account.name,
          'role': account.role,
          'created_at': now,
          'is_synced': 1,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);

        final insertedAdmin = await db.query(
          'users',
          columns: ['id'],
          where: 'lower(trim(email)) = ?',
          whereArgs: [_normalizeEmail(account.email)],
          limit: 1,
        );
        if (insertedAdmin.isEmpty) {
          throw StateError('Could not seed the default administrator.');
        }
        final adminId = insertedAdmin.first['id']! as String;
        final saltBytes = List<int>.generate(
          16,
          (_) => Random.secure().nextInt(256),
        );
        await db.insert('local_credentials', {
          'email': _normalizeEmail(account.email),
          'user_id': adminId,
          'salt': base64Encode(saltBytes),
          'password_hash': _derivePasswordHash(account.password, saltBytes),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        continue;
      }

      final existingUser = await db.query(
        'users',
        columns: ['id', 'email', 'role'],
        where: 'lower(trim(email)) = ?',
        whereArgs: [_normalizeEmail(account.email)],
        limit: 1,
      );

      if (existingUser.isNotEmpty) {
        final existingRole = (existingUser.first['role'] as String? ?? '')
            .trim();
        final email = (existingUser.first['email'] as String? ?? '').trim();
        if (existingRole.toLowerCase() == account.role &&
            _normalizeEmail(email) == _normalizeEmail(account.email)) {
          continue;
        }
      }

      final saltBytes = List<int>.generate(
        16,
        (_) => Random.secure().nextInt(256),
      );
      await db.insert('users', {
        'id': account.id,
        'email': account.email,
        'display_name': account.name,
        'role': account.role,
        'created_at': now,
        'is_synced': 1,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
      await db.insert('local_credentials', {
        'email': account.email,
        'user_id': account.id,
        'salt': base64Encode(saltBytes),
        'password_hash': _derivePasswordHash(account.password, saltBytes),
      }, conflictAlgorithm: ConflictAlgorithm.abort);
    }
  }

  Future<void> _migrateStudentDemoPassword(DatabaseExecutor db) async {
    final rows = await db.rawQuery(
      'SELECT local_credentials.salt, local_credentials.password_hash '
      'FROM local_credentials '
      'INNER JOIN users ON users.id = local_credentials.user_id '
      'WHERE lower(trim(users.email)) = ? '
      'AND lower(trim(users.role)) = ? AND users.id = ? LIMIT 1',
      [demoAccounts['student'], 'student', 'demo-student'],
    );
    if (rows.isEmpty) return;

    final current = rows.first;
    final salt = base64Decode(current['salt']! as String);
    if (!_constantTimeEquals(
      _derivePasswordHash(_legacyStudentDemoPassword, salt),
      current['password_hash']! as String,
    )) {
      return;
    }

    final newSalt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    await db.update(
      'local_credentials',
      {
        'salt': base64Encode(newSalt),
        'password_hash': _derivePasswordHash(
          demoPasswords['student']!,
          newSalt,
        ),
      },
      where: 'email = ?',
      whereArgs: [demoAccounts['student']],
    );
  }

  Future<void> _seedDemoUsers(DatabaseExecutor db) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final users = <(String, String, String)>[
      ('student', 'Mina Student', demoAccounts['student']!),
      ('teacher', 'Tr. Abebe', demoAccounts['teacher']!),
      ('parent', 'Ato Assefa', demoAccounts['parent']!),
      ('admin', 'Amina Admin', demoAccounts['admin']!),
    ];
    for (final (role, name, email) in users) {
      await db.delete(
        'local_credentials',
        where: 'user_id = ?',
        whereArgs: ['demo-$role'],
      );
      await db.insert('users', {
        'id': 'demo-$role',
        'email': email,
        'display_name': name,
        'role': role,
        'parent_email': role == 'student' ? demoAccounts['parent'] : null,
        'school': 'AMU Community School',
        'student_username': role == 'student' ? 'student' : null,
        'section': role == 'student' ? 'Section A' : null,
        'gender': role == 'student' ? 'Male' : null,
        'assigned_subjects': role == 'teacher' ? 'Mathematics' : null,
        'status': 'active',
        'account_status': 'approved',
        'created_at': now,
        'is_synced': 1,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      final saltBytes = List<int>.generate(
        16,
        (_) => Random.secure().nextInt(256),
      );
      await db.insert('local_credentials', {
        'email': email,
        'user_id': 'demo-$role',
        'salt': base64Encode(saltBytes),
        'password_hash': _derivePasswordHash(demoPasswords[role]!, saltBytes),
      });
    }
  }

  Future<void> seedInitialDataIfEmpty({bool force = false}) async {
    final db = await database;
    await _seedInitialAdminData(db, force: force);
  }

  Future<void> _seedInitialAdminData(Database db, {bool force = false}) async {
    const seedKey = 'admin_sample_data_v1';
    final seeded = await db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [seedKey],
      limit: 1,
    );
    if (seeded.isNotEmpty && !force) return;

    final now = DateTime.now().toUtc();
    String date(int daysAgo) =>
        now.subtract(Duration(days: daysAgo)).toIso8601String();
    final sampleUsers =
        <
          ({
            String id,
            String email,
            String name,
            String role,
            String? username,
            String status,
            String? section,
            String? gender,
            String? subject,
          })
        >[
          (
            id: 'sample-student-muluaken',
            email: 'muluaken.a.t@example.org',
            name: 'Muluaken A T',
            role: 'student',
            username: 'MULUAKEN_A_T',
            status: 'active',
            section: 'Section C',
            gender: 'Male',
            subject: null,
          ),
          (
            id: 'sample-student-almaz',
            email: 'almaz.bekele@example.org',
            name: 'Almaz Bekele',
            role: 'student',
            username: 'almaz_bekele',
            status: 'active',
            section: 'Section A',
            gender: 'Female',
            subject: null,
          ),
          (
            id: 'sample-student-kidus',
            email: 'kidus.y@example.org',
            name: 'Kidus Y',
            role: 'student',
            username: 'kidus_y',
            status: 'pending',
            section: 'Section B',
            gender: 'Male',
            subject: null,
          ),
          (
            id: 'sample-student-eden',
            email: 'eden.y@example.org',
            name: 'Eden Y',
            role: 'student',
            username: 'eden_y',
            status: 'pending',
            section: 'Section C',
            gender: 'Female',
            subject: null,
          ),
          (
            id: 'sample-teacher-tigist',
            email: 'tigist.teacher@example.org',
            name: 'Tr. Tigist',
            role: 'teacher',
            username: null,
            status: 'active',
            section: null,
            gender: 'Female',
            subject: 'General Science',
          ),
          (
            id: 'sample-teacher-dawit',
            email: 'dawit.teacher@example.org',
            name: 'Tr. Dawit',
            role: 'teacher',
            username: null,
            status: 'active',
            section: null,
            gender: 'Male',
            subject: 'English',
          ),
          (
            id: 'sample-parent-martha',
            email: 'martha.parent@example.org',
            name: 'W/ro Martha',
            role: 'parent',
            username: null,
            status: 'active',
            section: null,
            gender: 'Female',
            subject: null,
          ),
        ];

    await db.transaction((txn) async {
      for (final user in sampleUsers) {
        await txn.insert('users', {
          'id': user.id,
          'email': user.email,
          'display_name': user.name,
          'role': user.role,
          'school': 'AMU Community School',
          'student_username': user.username,
          'section': user.section,
          'gender': user.gender,
          'assigned_subjects': user.subject,
          'status': user.status,
          'account_status': switch (user.status) {
            'pending' => 'pending',
            'blocked' => 'blocked',
            _ => 'approved',
          },
          'created_at': date(user.status == 'pending' ? 2 : 30),
          'is_synced': 0,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        if (force) {
          await txn.update(
            'users',
            {
              'email': user.email,
              'display_name': user.name,
              'role': user.role,
              'school': 'AMU Community School',
              'student_username': user.username,
              'section': user.section,
              'gender': user.gender,
              'assigned_subjects': user.subject,
              'is_synced': 0,
            },
            where: 'id = ?',
            whereArgs: [user.id],
          );
        }
        final existingCredential = await txn.query(
          'local_credentials',
          columns: ['email'],
          where: 'email = ?',
          whereArgs: [user.email],
          limit: 1,
        );
        if (existingCredential.isEmpty) {
          final salt = List<int>.generate(
            16,
            (_) => Random.secure().nextInt(256),
          );
          await txn.insert('local_credentials', {
            'email': user.email,
            'user_id': user.id,
            'salt': base64Encode(salt),
            'password_hash': _derivePasswordHash('SaamepDemo123!', salt),
          });
        }
      }

      await txn.insert('parent_links', {
        'id': 'sample-parent-link-approved',
        'parent_email': demoAccounts['parent'],
        'parent_name': 'Ato Assefa',
        'student_username': 'MULUAKEN_A_T',
        'school': 'AMU Community School',
        'status': 'approved',
        'requested_at': date(20),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await txn.update(
        'users',
        {'display_name': 'Tr. Abebe', 'assigned_subjects': 'Mathematics'},
        where: 'id = ?',
        whereArgs: ['demo-teacher'],
      );
      await txn.update(
        'users',
        {'parent_email': demoAccounts['parent']},
        where: 'id = ?',
        whereArgs: ['sample-student-muluaken'],
      );
      await txn.insert('parent_links', {
        'id': 'sample-parent-link-pending',
        'parent_email': 'martha.parent@example.org',
        'parent_name': 'W/ro Martha',
        'student_username': 'almaz_bekele',
        'school': 'AMU Community School',
        'status': 'pending',
        'requested_at': date(1),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await txn.insert('parent_link_requests', {
        'id': 'sample-parent-link-pending',
        'parent_email': 'martha.parent@example.org',
        'student_id': 'sample-student-almaz',
        'status': 'pending',
        'created_at': date(1),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);

      const results = <(String, String, double, int)>[
        ('MULUAKEN_A_T', 'Mathematics', 92, 7),
        ('MULUAKEN_A_T', 'General Science', 88, 6),
        ('almaz_bekele', 'English', 68, 5),
        ('almaz_bekele', 'Mathematics', 64, 4),
        ('kidus_y', 'General Science', 42, 3),
        ('kidus_y', 'English', 38, 2),
        ('eden_y', 'Mathematics', 56, 3),
        ('eden_y', 'General Science', 52, 2),
        ('student', 'English', 32, 1),
        ('student', 'Mathematics', 36, 1),
      ];
      for (var index = 0; index < results.length; index++) {
        final (username, subject, score, daysAgo) = results[index];
        await txn.insert(
          'exam_results',
          {
            'id': 'sample-exam-result-$index',
            'student_username': username,
            'subject_name': subject,
            'score_percentage': score,
            'completed_at': date(daysAgo),
          },
          conflictAlgorithm: force
              ? ConflictAlgorithm.replace
              : ConflictAlgorithm.ignore,
        );
      }

      await txn.insert('settings', {
        'key': seedKey,
        'value': 'complete',
        'updated_at': now.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> _createDeletionQueue(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_deletions (
        id TEXT PRIMARY KEY,
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        deleted_at TEXT NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<void> _seedStudyContent(DatabaseExecutor db) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('quizzes', {
      'id': 'sample-ministry-practice',
      'title': 'Ministry Exam Practice',
      'description': 'A short sample quiz available offline.',
      'created_by': 'SAAMEP',
      'cached_at': now,
      'is_synced': 1,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    final questionCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM questions WHERE quiz_id = ?', [
        'sample-ministry-practice',
      ]),
    );
    if (questionCount == 0) {
      final questions = [
        {
          'id': 'sample-q1',
          'prompt': 'Which practice best supports effective public service?',
          'options': [
            'Accountability and transparency',
            'Withholding public information',
            'Avoiding consultation',
            'Ignoring established procedures',
          ],
          'answer': 'Accountability and transparency',
          'explanation':
              'Accountability and transparency build trust and help ensure '
              'public decisions can be reviewed.',
        },
        {
          'id': 'sample-q2',
          'prompt': 'What is an important first step in planning a project?',
          'options': [
            'Define the objective and intended outcomes',
            'Skip stakeholder identification',
            'Begin spending without a plan',
            'Avoid measuring progress',
          ],
          'answer': 'Define the objective and intended outcomes',
          'explanation':
              'Clear objectives guide the scope, activities, and measures of '
              'success for a project.',
        },
      ];
      for (final question in questions) {
        await db.insert('questions', {
          'id': question['id'],
          'quiz_id': 'sample-ministry-practice',
          'prompt': question['prompt'],
          'options_json': jsonEncode(question['options']),
          'answer': question['answer'],
          'explanation': question['explanation'],
          'is_synced': 1,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
    await db.insert('offline_textbooks', {
      'id': 'sample-study-guide',
      'title': 'Public Service Study Guide',
      'content':
          'Foundations of Public Service\n\n'
          'Public service is built on integrity, impartiality, accountability, '
          'and a commitment to serving the public interest.\n\n'
          'Accountability\n\n'
          'Public officials should be able to explain decisions, accept '
          'responsibility for outcomes, and follow lawful review processes.\n\n'
          'Transparent decision-making\n\n'
          'Share relevant information in an accessible way, protect '
          'confidential information, and apply rules consistently.\n\n'
          'Planning and evaluation\n\n'
          'Set measurable objectives, consult affected stakeholders, monitor '
          'progress, and use evidence to improve future work.',
      'created_by': 'SAAMEP',
      'cached_at': now,
      'is_synced': 1,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String declaration,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    if (!columns.any((row) => row['name'] == column)) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $declaration');
    }
  }

  Future<void> cacheUser({
    required String id,
    required String email,
    required String displayName,
    required String role,
    String? parentEmail,
  }) async {
    await upsertUser({
      'id': id,
      'email': _normalizeEmail(email),
      'display_name': displayName,
      'role': role.toLowerCase(),
      'parent_email': parentEmail,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'is_synced': 1,
    });
  }

  Future<void> upsertUser(Map<String, Object?> user) async {
    final db = await database;
    final role = user['role'] as String;
    final email = _normalizeEmail(user['email'] as String);
    final existingUsers = await db.query(
      'users',
      columns: [
        'account_status',
        'status',
        'school',
        'student_username',
        'school_id',
        'section',
        'gender',
        'assigned_subjects',
        'approved_at',
        'force_password_reset',
      ],
      where: 'lower(trim(email)) = ?',
      whereArgs: [email],
      limit: 1,
    );
    final existing = existingUsers.firstOrNull;
    final values = <String, Object?>{
      'id': user['id'],
      'email': email,
      'display_name': user['display_name'] ?? user['displayName'] ?? '',
      'role': role.toLowerCase(),
      'parent_email': _normalizeOptionalEmail(
        user['parent_email'] ?? user['parentEmail'],
      ),
      'school': user['school'] ?? existing?['school'] ?? 'AMU Community School',
      'student_username':
          user['student_username'] ??
          user['studentUsername'] ??
          existing?['student_username'],
      'school_id': user['school_id'] ?? existing?['school_id'],
      'section': user['section'] ?? existing?['section'],
      'gender': user['gender'] ?? existing?['gender'],
      'assigned_subjects':
          user['assigned_subjects'] ?? existing?['assigned_subjects'],
      'status': _canonicalStatus(
        user['status'] ??
            user['account_status'] ??
            existing?['status'] ??
            existing?['account_status'],
      ),
      'account_status': _legacyAccountStatus(
        user['account_status'] ?? user['status'] ?? existing?['account_status'],
      ),
      'approved_at':
          user['approved_at'] ?? user['approvedAt'] ?? existing?['approved_at'],
      'force_password_reset':
          user['force_password_reset'] ??
          user['forcePasswordReset'] ??
          existing?['force_password_reset'] ??
          0,
      'created_at':
          user['created_at'] ??
          user['createdAt'] ??
          DateTime.now().toUtc().toIso8601String(),
      'is_synced': user['is_synced'] ?? user['isSynced'] ?? 1,
    };
    if (values['id'] == null ||
        (values['display_name'] as String).trim().isEmpty ||
        !{
          'student',
          'teacher',
          'parent',
          'admin',
        }.contains(role.toLowerCase())) {
      throw const FormatException(
        'User record is missing its ID or name, or has an invalid role.',
      );
    }
    await db.insert(
      'users',
      values,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> createUser({
    required String id,
    required String email,
    required String displayName,
    required String role,
    String? parentEmail,
  }) async {
    if (!{'student', 'teacher', 'parent', 'admin'}.contains(role)) {
      throw ArgumentError.value(role, 'role', 'Unsupported account role.');
    }
    if (id.trim().isEmpty ||
        displayName.trim().isEmpty ||
        !_isValidEmail(email)) {
      throw ArgumentError('A valid ID, email, and display name are required.');
    }
    final db = await database;
    await db.insert('users', {
      'id': id,
      'email': _normalizeEmail(email),
      'display_name': displayName.trim(),
      'role': role,
      'parent_email': parentEmail == null ? null : _normalizeEmail(parentEmail),
      'school': 'AMU Community School',
      'student_username': role == 'student'
          ? await _newStudentUsername(db, email: email, id: id)
          : null,
      'status': 'active',
      'account_status': 'approved',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'is_synced': 0,
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<void> registerUser({
    required String email,
    required String displayName,
    required String password,
    required String role,
    String? schoolId,
    String? section,
    String? gender,
    String? assignedSubjects,
    String? studentUsername,
    String school = 'AMU Community School',
  }) async {
    final normalizedEmail = _normalizeEmail(email);
    final normalizedRole = role.trim().toLowerCase();
    if (!_isValidEmail(normalizedEmail)) {
      throw ArgumentError.value(email, 'email', 'Enter a valid email address.');
    }
    if (displayName.trim().isEmpty) {
      throw ArgumentError.value(
        displayName,
        'displayName',
        'Name cannot be empty.',
      );
    }
    if (password.length < 8) {
      throw ArgumentError.value(
        password,
        'password',
        'Password must be at least 8 characters.',
      );
    }
    if (!{'student', 'teacher', 'parent', 'admin'}.contains(normalizedRole)) {
      throw ArgumentError.value(role, 'role', 'Unsupported account role.');
    }

    final db = await database;
    final userId = _newId();
    final normalizedUsername = normalizedRole == 'student'
        ? await _newStudentUsername(
            db,
            email: normalizedEmail,
            requested: studentUsername,
            id: userId,
          )
        : null;
    final saltBytes = List<int>.generate(
      16,
      (_) => Random.secure().nextInt(256),
    );
    await db.transaction((txn) async {
      await txn.insert('users', {
        'id': userId,
        'email': normalizedEmail,
        'display_name': displayName.trim(),
        'role': normalizedRole,
        'school': _normalizeOptionalText(school) ?? 'AMU Community School',
        'school_id': _normalizeOptionalText(schoolId),
        'section': _normalizeOptionalText(section),
        'gender': _normalizeOptionalText(gender),
        'student_username': normalizedUsername,
        'assigned_subjects': _normalizeOptionalText(assignedSubjects),
        'status': normalizedRole == 'student' ? 'pending' : 'active',
        'account_status': normalizedRole == 'student' ? 'pending' : 'approved',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'is_synced': 0,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
      await txn.insert('local_credentials', {
        'email': normalizedEmail,
        'user_id': userId,
        'salt': base64Encode(saltBytes),
        'password_hash': _derivePasswordHash(password, saltBytes),
      });
    });
  }

  Future<Map<String, Object?>?> getUserByEmail(String email) async {
    final db = await database;
    final rows = await db.query(
      'users',
      where: 'lower(trim(email)) = ?',
      whereArgs: [_normalizeEmail(email)],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, Object?>>> getUsers() async {
    final db = await database;
    return db.query('users', orderBy: 'display_name COLLATE NOCASE');
  }

  Future<Map<String, int>> getAdminRoleCounts() async {
    final db = await database;
    final rows = await db.rawQuery(
      "SELECT lower(trim(role)) AS role, "
      "COUNT(*) AS count, "
      "SUM(CASE WHEN status = 'active' THEN 1 ELSE 0 END) "
      "AS active_count FROM users "
      "WHERE lower(trim(role)) IN ('student', 'teacher', 'parent') "
      'GROUP BY lower(trim(role))',
    );
    final counts = <String, int>{
      for (final role in const ['student', 'teacher', 'parent'])
        role:
            rows
                .where((row) => row['role'] == role)
                .map(
                  (row) => role == 'student'
                      ? (row['active_count'] as int?) ?? 0
                      : row['count'] as int,
                )
                .firstOrNull ??
            0,
    };
    final students = await getAdminStudents();
    final atRisk = students.where((student) {
      final score = (student['average_score'] as num?)?.toDouble();
      return score != null && score < 50;
    }).length;
    return {
      ...counts,
      'students': counts['student']!,
      'teachers': counts['teacher']!,
      'parents': counts['parent']!,
      'at_risk': atRisk,
    };
  }

  Future<Map<String, Object?>> getGradeDistribution() async {
    final students = await getAdminStudents();
    final assessedScores = students
        .where((student) => student['average_score'] is num)
        .map((student) => (student['average_score'] as num).toDouble())
        .toList(growable: false);
    final excellent = assessedScores.where((score) => score >= 75).length;
    final good = assessedScores
        .where((score) => score >= 50 && score < 75)
        .length;
    final atRisk = assessedScores.where((score) => score < 50).length;
    final total = assessedScores.length;
    return {
      'excellent': excellent,
      'good': good,
      'at_risk': atRisk,
      'excellent_pct': _percentage(excellent, total),
      'good_pct': _percentage(good, total),
      'at_risk_pct': _percentage(atRisk, total),
      'total_assessed': total,
    };
  }

  Future<List<Map<String, Object?>>> getPendingStudents() async =>
      (await getAdminStudents())
          .where((student) => student['status'] == 'pending')
          .toList(growable: false);

  Future<List<Map<String, Object?>>> getActiveStudents() async =>
      (await getAdminStudents())
          .where((student) => student['status'] == 'active')
          .toList(growable: false);

  Future<void> approveStudent(String id) => setStudentStatus(id, 'active');

  Future<void> rejectStudent(String id) => setStudentStatus(id, 'blocked');

  Future<void> updateUserStatus(String id, String status) =>
      setStudentStatus(id, status);

  Future<void> toggleBlockUser(String id, [String? newStatus]) async {
    if (newStatus != null) {
      await setStudentStatus(id, newStatus);
      return;
    }
    final db = await database;
    final users = await db.query(
      'users',
      columns: ['status'],
      where: 'id = ? AND lower(trim(role)) = ?',
      whereArgs: [id, 'student'],
      limit: 1,
    );
    if (users.isEmpty) throw StateError('Student account could not be found.');
    final current = _canonicalStatus(users.first['status'] as String? ?? '');
    await setStudentStatus(id, current == 'active' ? 'blocked' : 'active');
  }

  Future<List<Map<String, Object?>>> filterStudents({
    String section = 'All',
    String gender = 'All',
    String scoreTier = 'All',
    String search = '',
  }) async {
    final query = search.trim().toLowerCase().replaceFirst('@', '');
    final rows = await getAdminStudents();
    return rows
        .where((student) {
          final studentSection = (student['section'] as String?) ?? '';
          final studentGender = (student['gender'] as String?) ?? '';
          final score = (student['average_score'] as num?)?.toDouble();
          final normalizedSection = section
              .replaceFirst('Section ', '')
              .toLowerCase();
          final sectionMatches =
              section == 'All' ||
              section == 'All Sections' ||
              studentSection.toLowerCase() == section.toLowerCase() ||
              studentSection.toLowerCase() == 'section $normalizedSection';
          final genderMatches =
              gender == 'All' ||
              gender == 'All Genders' ||
              studentGender.toLowerCase() == gender.toLowerCase();
          final tier = switch (score) {
            null => 'Not assessed',
            >= 75 => 'Excellent',
            >= 50 => 'Good',
            _ => 'At Risk',
          };
          final tierMatches =
              scoreTier == 'All' ||
              scoreTier == 'All Tiers' ||
              tier.toLowerCase() == scoreTier.toLowerCase() ||
              (scoreTier.toLowerCase().contains('at_risk') &&
                  tier == 'At Risk') ||
              (scoreTier.contains('At-Risk') && tier == 'At Risk') ||
              (scoreTier.contains('Good') && tier == 'Good') ||
              (scoreTier.contains('Excellent') && tier == 'Excellent');
          final searchMatches =
              query.isEmpty ||
              (student['display_name'] as String? ?? '').toLowerCase().contains(
                query,
              ) ||
              (student['student_username'] as String? ?? '')
                  .toLowerCase()
                  .contains(query);
          return sectionMatches &&
              genderMatches &&
              tierMatches &&
              searchMatches;
        })
        .toList(growable: false);
  }

  Future<List<Map<String, Object?>>> getAdminStudents() async {
    final db = await database;
    return db.rawQuery('''
      SELECT users.id, users.email, users.display_name, users.school,
        users.student_username, users.school_id, users.section, users.gender,
        users.status, users.account_status, users.approved_at, users.created_at,
        users.parent_email,
        COALESCE(exam_results.average_score, exam_attempts.average_score)
          AS average_score
      FROM users
      LEFT JOIN (
        SELECT user_id,
          AVG(score * 100.0 / total_questions) AS average_score
        FROM exam_attempts
        WHERE status = 'completed' AND total_questions > 0
        GROUP BY user_id
      ) AS exam_attempts ON exam_attempts.user_id = users.id
      LEFT JOIN (
        SELECT lower(trim(student_username)) AS student_username,
          AVG(score_percentage) AS average_score
        FROM exam_results
        GROUP BY lower(trim(student_username))
      ) AS exam_results
        ON exam_results.student_username = lower(trim(users.student_username))
      WHERE lower(trim(users.role)) = 'student'
      GROUP BY users.id
      ORDER BY users.created_at DESC
    ''');
  }

  int _percentage(int part, int total) =>
      total == 0 ? 0 : (part * 100 / total).round();

  Future<List<Map<String, Object?>>> getAdminTeachers() async {
    final db = await database;
    return db.query(
      'users',
      columns: ['id', 'email', 'display_name', 'school', 'assigned_subjects'],
      where: 'lower(trim(role)) = ?',
      whereArgs: ['teacher'],
      orderBy: 'display_name COLLATE NOCASE',
    );
  }

  Future<List<Map<String, Object?>>> getTeachersList() => getAdminTeachers();

  Future<Map<String, List<String>>> getAdminCurriculumSummary() async {
    final db = await database;
    final attemptSubjects = await db.rawQuery(
      "SELECT DISTINCT trim(subject) AS value FROM exam_attempts "
      "WHERE trim(subject) != ''",
    );
    final resultSubjects = await db.rawQuery(
      "SELECT DISTINCT trim(subject_name) AS value FROM exam_results "
      "WHERE trim(subject_name) != ''",
    );
    final assignedSubjects = await db.rawQuery(
      "SELECT assigned_subjects AS value FROM users "
      "WHERE lower(trim(role)) = 'teacher' "
      "AND assigned_subjects IS NOT NULL AND trim(assigned_subjects) != ''",
    );
    final attemptYears = await db.rawQuery(
      "SELECT DISTINCT trim(year) AS value FROM exam_attempts "
      "WHERE trim(year) != ''",
    );
    final resultYears = await db.rawQuery(
      "SELECT DISTINCT substr(completed_at, 1, 4) AS value "
      "FROM exam_results WHERE trim(completed_at) != ''",
    );
    List<String> values(Iterable<Map<String, Object?>> rows) =>
        rows
            .map((row) => row['value'] as String?)
            .whereType<String>()
            .expand((value) => value.split(','))
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return {
      'subjects': values([
        ...attemptSubjects,
        ...resultSubjects,
        ...assignedSubjects,
      ]),
      'years': values([...attemptYears, ...resultYears]),
    };
  }

  Future<List<Map<String, Object?>>> getAdminParents() async {
    final db = await database;
    return db.query(
      'users',
      columns: ['id', 'email', 'display_name'],
      where: 'lower(trim(role)) = ?',
      whereArgs: ['parent'],
      orderBy: 'display_name COLLATE NOCASE',
    );
  }

  Future<List<Map<String, Object?>>> getParentLinkRequests() async {
    final db = await database;
    return db.rawQuery('''
      SELECT parent_links.*, parent_links.student_username AS student_id,
        parent.display_name AS account_parent_name,
        students.display_name AS student_name, students.school_id,
        students.student_username, parent_links.requested_at AS created_at
      FROM parent_links
      LEFT JOIN users AS parent
        ON lower(trim(parent.email)) = lower(trim(parent_links.parent_email))
      LEFT JOIN users AS students
        ON lower(trim(students.student_username)) =
          lower(trim(parent_links.student_username))
      ORDER BY parent_links.requested_at DESC
    ''');
  }

  Future<List<Map<String, Object?>>> getPendingParentLinks() async =>
      (await getParentLinkRequests())
          .where((link) => link['status'] == 'pending')
          .toList(growable: false);

  Future<List<Map<String, Object?>>> getParentLinks() =>
      getParentLinkRequests();

  Future<List<Map<String, Object?>>> getVerifiedParentLinks() async =>
      (await getParentLinkRequests())
          .where((link) => link['status'] == 'approved')
          .toList(growable: false);

  Future<void> createParentLinkRequest({
    required String parentEmail,
    required String studentId,
  }) async {
    final normalizedEmail = _normalizeEmail(parentEmail);
    final normalizedStudentId = studentId.trim();
    if (!_isValidEmail(normalizedEmail) || normalizedStudentId.isEmpty) {
      throw ArgumentError('A valid parent email and student ID are required.');
    }
    final db = await database;
    final parent = await db.query(
      'users',
      columns: ['id'],
      where: 'lower(trim(email)) = ? AND lower(trim(role)) = ?',
      whereArgs: [normalizedEmail, 'parent'],
      limit: 1,
    );
    if (parent.isEmpty) {
      throw ArgumentError('No parent account exists for that email.');
    }
    final student = await db.query(
      'users',
      columns: ['id', 'parent_email'],
      where:
          '(id = ? OR lower(trim(school_id)) = lower(trim(?)) '
          'OR lower(trim(student_username)) = lower(trim(?))) '
          "AND lower(trim(role)) = 'student'",
      whereArgs: [
        normalizedStudentId,
        normalizedStudentId,
        normalizedStudentId.toLowerCase(),
      ],
      limit: 1,
    );
    if (student.isEmpty) throw ArgumentError('Student ID was not found.');
    final linkedParent = student.first['parent_email'] as String?;
    if (linkedParent != null &&
        linkedParent.trim().isNotEmpty &&
        _normalizeEmail(linkedParent) != normalizedEmail) {
      throw ArgumentError('This student is already linked to another parent.');
    }
    final actualStudentId = student.first['id']! as String;
    final studentUsername = await db.query(
      'users',
      columns: ['student_username', 'school'],
      where: 'id = ?',
      whereArgs: [actualStudentId],
      limit: 1,
    );
    final duplicate = await db.query(
      'parent_link_requests',
      columns: ['id'],
      where: 'parent_email = ? AND student_id = ? AND status = ?',
      whereArgs: [normalizedEmail, actualStudentId, 'pending'],
      limit: 1,
    );
    if (duplicate.isNotEmpty) {
      throw ArgumentError('A matching pending link request already exists.');
    }
    final id = _newId();
    final parentName = await db.query(
      'users',
      columns: ['display_name'],
      where: 'lower(trim(email)) = ?',
      whereArgs: [normalizedEmail],
      limit: 1,
    );
    final requestedAt = DateTime.now().toUtc().toIso8601String();
    await db.insert('parent_links', {
      'id': id,
      'parent_email': normalizedEmail,
      'parent_name': parentName.first['display_name'],
      'student_username': studentUsername.first['student_username'],
      'school': studentUsername.first['school'] ?? 'AMU Community School',
      'status': 'pending',
      'requested_at': requestedAt,
    });
    await db.insert('parent_link_requests', {
      'id': id,
      'parent_email': normalizedEmail,
      'student_id': actualStudentId,
      'status': 'pending',
      'created_at': requestedAt,
    });
  }

  Future<void> resolveParentLinkRequest(
    String requestId, {
    required bool approve,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final requests = await txn.query(
        'parent_links',
        where: 'id = ? AND status = ?',
        whereArgs: [requestId, 'pending'],
        limit: 1,
      );
      if (requests.isEmpty) {
        throw StateError('This parent link request is no longer pending.');
      }
      final request = requests.first;
      if (approve) {
        final updated = await txn.update(
          'users',
          {'parent_email': request['parent_email'], 'is_synced': 0},
          where:
              'lower(trim(student_username)) = ? '
              'AND lower(trim(role)) = ? '
              'AND (parent_email IS NULL OR trim(parent_email) = ? '
              'OR lower(trim(parent_email)) = lower(trim(?)))',
          whereArgs: [
            (request['student_username'] as String).toLowerCase(),
            'student',
            '',
            request['parent_email'],
          ],
        );
        if (updated == 0) {
          throw StateError(
            'Student could not be linked; they may already have another parent.',
          );
        }
      }
      await txn.update(
        'parent_links',
        {'status': approve ? 'approved' : 'rejected'},
        where: 'id = ?',
        whereArgs: [requestId],
      );
      await txn.update(
        'parent_link_requests',
        {'status': approve ? 'approved' : 'rejected'},
        where: 'id = ?',
        whereArgs: [requestId],
      );
    });
  }

  Future<void> approveParentLink(String id) =>
      resolveParentLinkRequest(id, approve: true);

  Future<void> rejectParentLink(String id) =>
      resolveParentLinkRequest(id, approve: false);

  Future<void> setStudentStatus(String userId, String status) async {
    const statuses = {'pending', 'approved', 'active', 'rejected', 'blocked'};
    final canonicalStatus = _canonicalStatus(status);
    final storedStatus = _legacyAccountStatus(status);
    if (!statuses.contains(status)) {
      throw ArgumentError.value(status, 'status', 'Unsupported account state.');
    }
    final db = await database;
    final values = <String, Object?>{
      'status': canonicalStatus,
      'account_status': storedStatus,
      'is_synced': 0,
    };
    if (status == 'active' || status == 'approved') {
      values['approved_at'] = DateTime.now().toUtc().toIso8601String();
    }
    final updated = await db.update(
      'users',
      values,
      where: 'id = ? AND lower(trim(role)) = ?',
      whereArgs: [userId, 'student'],
    );
    if (updated == 0) throw StateError('Student account could not be found.');
  }

  Future<void> rejectPendingStudent(String userId) async {
    final db = await database;
    await db.transaction((txn) async {
      final students = await txn.query(
        'users',
        columns: ['status'],
        where: "id = ? AND lower(trim(role)) = 'student'",
        whereArgs: [userId],
        limit: 1,
      );
      if (students.isEmpty) {
        throw StateError('Student account could not be found.');
      }
      if (students.first['status'] != 'pending') {
        throw StateError('Only pending student registrations can be rejected.');
      }
      await _deleteUserInTransaction(txn, userId);
    });
  }

  Future<void> saveAdminFilters({
    required String section,
    required String gender,
    required String tier,
  }) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      for (final entry in {
        'admin_filter_section': section,
        'admin_filter_gender': gender,
        'admin_filter_tier': tier,
      }.entries) {
        await txn.insert('settings', {
          'key': entry.key,
          'value': entry.value,
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<Map<String, String>> getAdminFilters() async {
    final db = await database;
    final rows = await db.query(
      'settings',
      columns: ['key', 'value'],
      where: 'key IN (?, ?, ?)',
      whereArgs: [
        'admin_filter_section',
        'admin_filter_gender',
        'admin_filter_tier',
      ],
    );
    final saved = {for (final row in rows) row['key']!: row['value']!};
    return {
      'section': (saved['admin_filter_section'] as String?) ?? 'All',
      'gender': (saved['admin_filter_gender'] as String?) ?? 'All',
      'tier': (saved['admin_filter_tier'] as String?) ?? 'All',
    };
  }

  Future<void> saveAdminSearch(String search) async {
    final db = await database;
    await db.insert('settings', {
      'key': 'admin_filter_search',
      'value': search,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String> getAdminSearch() async {
    final db = await database;
    final rows = await db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['admin_filter_search'],
      limit: 1,
    );
    return rows.isEmpty ? '' : rows.first['value']! as String;
  }

  Future<String> resetTeacherPassword(
    String userId, [
    String? temporaryPassword,
  ]) async {
    final db = await database;
    final password = temporaryPassword ?? _generateTemporaryPassword();
    await db.transaction((txn) async {
      final teachers = await txn.query(
        'users',
        columns: ['email'],
        where: 'id = ? AND lower(trim(role)) = ?',
        whereArgs: [userId, 'teacher'],
        limit: 1,
      );
      if (teachers.isEmpty) throw StateError('Teacher account was not found.');
      final email = teachers.first['email'];
      if (email is! String || email.isEmpty) {
        throw const FormatException('Teacher account has no email address.');
      }
      await txn.insert(
        'local_credentials',
        _localCredentialValues(
          email: email,
          password: password,
          userId: userId,
        ),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      final updated = await txn.update(
        'users',
        {'force_password_reset': 1, 'is_synced': 0},
        where: 'id = ?',
        whereArgs: [userId],
      );
      if (updated == 0) throw StateError('Teacher account was not found.');
    });
    return password;
  }

  Future<void> completeTeacherPasswordReset({
    required String userId,
    required String email,
    required String password,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final teachers = await txn.query(
        'users',
        columns: ['email'],
        where: "id = ? AND lower(trim(role)) = 'teacher'",
        whereArgs: [userId],
        limit: 1,
      );
      if (teachers.isEmpty) throw StateError('Teacher account was not found.');
      final storedEmail = teachers.first['email'];
      if (storedEmail is! String ||
          _normalizeEmail(storedEmail) != _normalizeEmail(email)) {
        throw ArgumentError('The teacher ID and email do not match.');
      }
      await txn.insert(
        'local_credentials',
        _localCredentialValues(
          email: email,
          password: password,
          userId: userId,
        ),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.update(
        'users',
        {'force_password_reset': 0, 'is_synced': 0},
        where: 'id = ?',
        whereArgs: [userId],
      );
    });
  }

  String _generateTemporaryPassword() {
    const alphabet =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz'
        '23456789!@#';
    final random = Random.secure();
    return List.generate(
      14,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  Future<void> updateUser(String id, Map<String, Object?> values) async {
    const allowed = {
      'display_name',
      'role',
      'parent_email',
      'school',
      'student_username',
      'school_id',
      'section',
      'gender',
      'assigned_subjects',
    };
    final updates = Map<String, Object?>.fromEntries(
      values.entries.where((entry) => allowed.contains(entry.key)),
    )..['is_synced'] = 0;
    if (updates.length == 1) return;
    if (updates['role'] case final String role
        when !{'student', 'teacher', 'parent', 'admin'}.contains(role)) {
      throw ArgumentError.value(role, 'role', 'Unsupported account role.');
    }
    if (updates['display_name'] case final String name
        when name.trim().isEmpty) {
      throw ArgumentError.value(name, 'display_name', 'Name cannot be empty.');
    }
    if (updates.containsKey('parent_email')) {
      updates['parent_email'] = _normalizeOptionalEmail(
        updates['parent_email'],
      );
    }
    final db = await database;
    await db.update('users', updates, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteUser(String id) async {
    final db = await database;
    await db.transaction((txn) => _deleteUserInTransaction(txn, id));
  }

  Future<void> _deleteUserInTransaction(DatabaseExecutor txn, String id) async {
    final users = await txn.query(
      'users',
      columns: ['email'],
      where: 'id = ?',
      whereArgs: [id],
    );
    if (users.isNotEmpty) {
      final email = users.first['email'];
      await txn.delete(
        'local_credentials',
        where: 'email = ?',
        whereArgs: [email],
      );
      await txn.delete(
        'parent_link_requests',
        where: 'lower(trim(parent_email)) = lower(trim(?))',
        whereArgs: [email],
      );
    }
    await txn.delete(
      'parent_link_requests',
      where: 'student_id = ?',
      whereArgs: [id],
    );
    await _recordDeletion(txn, 'users', id);
    await txn.delete('users', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> saveLocalCredential({
    required String email,
    required String password,
    required String userId,
  }) async {
    final db = await database;
    await db.insert(
      'local_credentials',
      _localCredentialValues(email: email, password: password, userId: userId),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Map<String, Object?> _localCredentialValues({
    required String email,
    required String password,
    required String userId,
  }) {
    if (password.isEmpty) throw ArgumentError('Password cannot be empty.');
    final saltBytes = List<int>.generate(
      16,
      (_) => Random.secure().nextInt(256),
    );
    return {
      'email': _normalizeEmail(email),
      'user_id': userId,
      'salt': base64Encode(saltBytes),
      'password_hash': _derivePasswordHash(password, saltBytes),
    };
  }

  Future<Map<String, Object?>?> authenticateLocalUser({
    required String email,
    required String password,
    required String role,
  }) async {
    final normalizedEmail = _normalizeEmail(email);
    final normalizedRole = role.trim().toLowerCase();
    if (normalizedEmail.isEmpty ||
        password.isEmpty ||
        !{'student', 'teacher', 'parent', 'admin'}.contains(normalizedRole)) {
      _logLoginLookup(
        normalizedEmail,
        normalizedRole,
        accountFound: false,
        credentialFound: false,
        passwordMatched: false,
      );
      return null;
    }
    final db = await database;
    final credentials = await db.rawQuery(
      'SELECT local_credentials.salt, local_credentials.password_hash, '
      'users.id, users.email, users.display_name, users.role, '
      'users.parent_email, users.school, users.student_username, '
      'users.section, users.gender, users.created_at, users.is_synced, '
      'users.account_status, users.force_password_reset '
      'FROM users '
      'LEFT JOIN local_credentials '
      'ON users.id = local_credentials.user_id '
      'WHERE (lower(trim(users.email)) = ? OR '
      "(? = 'student' AND lower(trim(users.student_username)) = ?)) "
      'AND lower(trim(users.role)) = ? LIMIT 1',
      [normalizedEmail, normalizedRole, normalizedEmail, normalizedRole],
    );
    if (credentials.isEmpty) {
      _logLoginLookup(
        normalizedEmail,
        normalizedRole,
        accountFound: false,
        credentialFound: false,
        passwordMatched: false,
      );
      return null;
    }
    final credential = credentials.first;
    final saltValue = credential['salt'];
    final hashValue = credential['password_hash'];
    if (saltValue is! String || hashValue is! String) {
      _logLoginLookup(
        normalizedEmail,
        normalizedRole,
        accountFound: true,
        credentialFound: false,
        passwordMatched: false,
      );
      return null;
    }
    final salt = base64Decode(saltValue);
    final candidate = _derivePasswordHash(password, salt);
    final passwordMatched = _constantTimeEquals(candidate, hashValue);
    _logLoginLookup(
      normalizedEmail,
      normalizedRole,
      accountFound: true,
      credentialFound: true,
      passwordMatched: passwordMatched,
    );
    if (!passwordMatched) {
      return null;
    }
    return {
      for (final entry in credential.entries)
        if (entry.key != 'salt' && entry.key != 'password_hash')
          entry.key: entry.value,
    };
  }

  void _logLoginLookup(
    String email,
    String role, {
    required bool accountFound,
    required bool credentialFound,
    required bool passwordMatched,
  }) {
    if (!kDebugMode) return;
    final separator = email.indexOf('@');
    final maskedEmail = separator > 0
        ? '${email[0]}***${email.substring(separator)}'
        : '<invalid>';
    debugPrint(
      'Login lookup result: enteredEmail=$maskedEmail, enteredRole=$role, '
      'accountFound=$accountFound, credentialFound=$credentialFound, '
      'passwordMatched=$passwordMatched',
    );
  }

  Future<bool> hasLocalCredential({
    required String email,
    required String role,
  }) async {
    final normalizedEmail = _normalizeEmail(email);
    final normalizedRole = role.trim().toLowerCase();
    if (normalizedEmail.isEmpty ||
        !{'student', 'teacher', 'parent', 'admin'}.contains(normalizedRole)) {
      return false;
    }
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT 1 FROM local_credentials '
      'INNER JOIN users ON users.id = local_credentials.user_id '
      'WHERE lower(trim(users.email)) = ? '
      'AND lower(trim(users.role)) = ? LIMIT 1',
      [normalizedEmail, normalizedRole],
    );
    return rows.isNotEmpty;
  }

  String _derivePasswordHash(String password, List<int> salt) {
    final key = utf8.encode(password);
    final hmac = Hmac(sha256, key);
    final block = Uint8List.fromList([...salt, 0, 0, 0, 1]);
    var u = hmac.convert(block).bytes;
    final result = Uint8List.fromList(u);
    for (var iteration = 1; iteration < _credentialIterations; iteration++) {
      u = hmac.convert(u).bytes;
      for (var index = 0; index < result.length; index++) {
        result[index] ^= u[index];
      }
    }
    return base64Encode(result);
  }

  bool _constantTimeEquals(String first, String second) {
    if (first.length != second.length) return false;
    var difference = 0;
    for (var index = 0; index < first.length; index++) {
      difference |= first.codeUnitAt(index) ^ second.codeUnitAt(index);
    }
    return difference == 0;
  }

  Future<void> createQuiz({
    required String id,
    required String title,
    String? description,
    String? createdBy,
  }) async {
    final db = await database;
    await db.insert('quizzes', {
      'id': id,
      'title': title,
      'description': description,
      'created_by': createdBy,
      'cached_at': DateTime.now().toUtc().toIso8601String(),
      'is_synced': 0,
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<void> createQuizWithQuestion({
    required String id,
    required String title,
    String? description,
    String? createdBy,
    required Map<String, Object?> question,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert('quizzes', {
        'id': id,
        'title': title,
        'description': description,
        'created_by': createdBy,
        'cached_at': DateTime.now().toUtc().toIso8601String(),
        'is_synced': 0,
      });
      await createQuestion(question, executor: txn, quizId: id);
    });
  }

  Future<void> cacheQuiz({
    required String id,
    required String title,
    String? description,
    String? createdBy,
    required List<Map<String, Object?>> questions,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert('quizzes', {
        'id': id,
        'title': title,
        'description': description,
        'created_by': createdBy,
        'cached_at': DateTime.now().toUtc().toIso8601String(),
        'is_synced': 1,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      for (final question in questions) {
        await createQuestion(
          question,
          executor: txn,
          quizId: id,
          isSynced: true,
        );
      }
    });
  }

  Future<List<Map<String, Object?>>> getQuizzes() async {
    final db = await database;
    return db.query('quizzes', orderBy: 'title COLLATE NOCASE');
  }

  Future<Map<String, Object?>?> getQuiz(String id) async {
    final db = await database;
    final rows = await db.query('quizzes', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> updateQuiz(String id, Map<String, Object?> values) async {
    const allowed = {'title', 'description', 'created_by'};
    final updates = Map<String, Object?>.fromEntries(
      values.entries.where((entry) => allowed.contains(entry.key)),
    )..['is_synced'] = 0;
    if (updates.length == 1) return;
    final db = await database;
    await db.update('quizzes', updates, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteQuiz(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      final questions = await txn.query(
        'questions',
        columns: ['id'],
        where: 'quiz_id = ?',
        whereArgs: [id],
      );
      for (final question in questions) {
        await _recordDeletion(txn, 'questions', question['id']! as String);
      }
      await _recordDeletion(txn, 'quizzes', id);
      await txn.delete('questions', where: 'quiz_id = ?', whereArgs: [id]);
      await txn.delete('quizzes', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> createQuestion(
    Map<String, Object?> question, {
    DatabaseExecutor? executor,
    String? quizId,
    bool isSynced = false,
  }) async {
    final db = executor ?? await database;
    final options = question['options'];
    final encodedOptions =
        question['options_json'] ??
        (options is String ? options : jsonEncode(options ?? const <String>[]));
    final prompt = question['prompt'];
    final answer = question['answer'];
    if (question['id'] == null || prompt == null || answer == null) {
      throw const FormatException(
        'Question ID, prompt, and answer are required.',
      );
    }
    await db.insert('questions', {
      'id': question['id'],
      'quiz_id': quizId ?? question['quiz_id'],
      'prompt': prompt,
      'options_json': encodedOptions,
      'answer': answer,
      'explanation': question['explanation'],
      'is_synced': isSynced ? 1 : (question['is_synced'] ?? 0),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, Object?>>> getCachedQuestions(String quizId) async {
    final db = await database;
    return db.query(
      'questions',
      where: 'quiz_id = ?',
      whereArgs: [quizId],
      orderBy: 'id',
    );
  }

  Future<void> updateQuestion(String id, Map<String, Object?> values) async {
    const allowed = {
      'quiz_id',
      'prompt',
      'options_json',
      'answer',
      'explanation',
    };
    final updates = Map<String, Object?>.fromEntries(
      values.entries.where((entry) => allowed.contains(entry.key)),
    )..['is_synced'] = 0;
    if (updates.length == 1) return;
    final db = await database;
    await db.update('questions', updates, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteQuestion(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      await _recordDeletion(txn, 'questions', id);
      await txn.delete('questions', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> logStudentScore({
    required String studentEmail,
    required String quizId,
    required double score,
    required double total,
  }) async {
    if (score < 0 || total <= 0 || score > total) {
      throw ArgumentError('Score must be between zero and a positive total.');
    }
    final db = await database;
    await db.insert('user_scores', {
      'id': _newId(),
      'student_email': _normalizeEmail(studentEmail),
      'quiz_id': quizId,
      'score': score,
      'total': total,
      'completed_at': DateTime.now().toUtc().toIso8601String(),
      'is_synced': 0,
    });
  }

  Future<List<Map<String, Object?>>> getScoresForStudent(
    String studentEmail,
  ) async {
    final db = await database;
    return db.rawQuery(
      'SELECT user_scores.*, quizzes.title AS quiz_title FROM user_scores '
      'LEFT JOIN quizzes ON quizzes.id = user_scores.quiz_id '
      'WHERE student_email = ? ORDER BY completed_at DESC',
      [_normalizeEmail(studentEmail)],
    );
  }

  Future<Map<String, Object?>> getStudentStats(String userId) async {
    final normalizedId = userId.trim();
    if (normalizedId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'User ID cannot be empty.');
    }
    final db = await database;
    await _updateStudentStats(db, normalizedId);
    final rows = await db.query(
      'user_stats',
      where: 'user_id = ?',
      whereArgs: [normalizedId],
      limit: 1,
    );
    return rows.single;
  }

  Future<List<Map<String, Object?>>> getRecentExamAttempts(
    String userId, {
    int limit = 5,
  }) async {
    final normalizedId = userId.trim();
    if (normalizedId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'User ID cannot be empty.');
    }
    if (limit < 1) {
      throw ArgumentError.value(limit, 'limit', 'Limit must be positive.');
    }
    final db = await database;
    return db.query(
      'exam_attempts',
      where: 'user_id = ?',
      whereArgs: [normalizedId],
      orderBy: 'completed_at DESC, id DESC',
      limit: limit,
    );
  }

  Future<int> saveExamAttempt(Map<String, dynamic> attemptData) async {
    final userId = attemptData['user_id'];
    final subject = attemptData['subject'];
    final year = attemptData['year'];
    final status = attemptData['status'] ?? 'in_progress';
    final score = attemptData['score'] ?? 0;
    final totalQuestions = attemptData['total_questions'] ?? 0;
    if (userId is! String ||
        userId.trim().isEmpty ||
        subject is! String ||
        year is! String ||
        !{'completed', 'in_progress'}.contains(status) ||
        score is! num ||
        totalQuestions is! num ||
        score < 0 ||
        totalQuestions < 0 ||
        score > totalQuestions) {
      throw ArgumentError('Exam attempt data is invalid.');
    }
    final questionIndex = attemptData['question_index'] ?? 0;
    final secondsRemaining = attemptData['seconds_remaining'] ?? 0;
    final answersJson = attemptData['answers_json'] ?? '[]';
    final completedAt =
        attemptData['completed_at'] ?? DateTime.now().toUtc().toIso8601String();
    if (questionIndex is! int ||
        questionIndex < 0 ||
        secondsRemaining is! int ||
        secondsRemaining < 0 ||
        answersJson is! String ||
        completedAt is! String) {
      throw ArgumentError('Exam attempt progress data is invalid.');
    }
    final attemptId = attemptData['id'];
    if (attemptId != null && attemptId is! int) {
      throw ArgumentError.value(attemptId, 'id', 'Attempt ID must be an int.');
    }

    final db = await database;
    late final int savedId;
    await db.transaction((txn) async {
      final values = <String, Object?>{
        'user_id': userId.trim(),
        'subject': subject.trim(),
        'year': year.trim(),
        'score': score.toDouble(),
        'total_questions': totalQuestions.toInt(),
        'completed_at': completedAt,
        'status': status,
        'quiz_id': attemptData['quiz_id'],
        'answers_json': answersJson,
        'question_index': questionIndex,
        'seconds_remaining': secondsRemaining,
      };
      if (attemptId == null) {
        savedId = await txn.insert('exam_attempts', values);
      } else {
        final updated = await txn.update(
          'exam_attempts',
          values,
          where: 'id = ? AND user_id = ?',
          whereArgs: [attemptId, userId.trim()],
        );
        if (updated == 0) {
          throw StateError(
            'The exam attempt could not be found for this user.',
          );
        }
        savedId = attemptId;
      }
      if (status == 'completed') {
        await _updateStudentStats(txn, userId.trim());
      }
    });
    return savedId;
  }

  Future<List<Map<String, Object?>>> getScoresForParent(
    String parentEmail,
  ) async {
    final db = await database;
    return db.rawQuery(
      'SELECT user_scores.*, users.display_name AS student_name, '
      'quizzes.title AS quiz_title FROM user_scores '
      'LEFT JOIN users ON users.email = user_scores.student_email '
      'LEFT JOIN quizzes ON quizzes.id = user_scores.quiz_id '
      'WHERE users.parent_email = ? ORDER BY completed_at DESC',
      [_normalizeEmail(parentEmail)],
    );
  }

  Future<List<Map<String, Object?>>> getAllScores() async {
    final db = await database;
    return db.rawQuery(
      'SELECT user_scores.*, users.display_name AS student_name, '
      'quizzes.title AS quiz_title FROM user_scores '
      'LEFT JOIN users ON users.email = user_scores.student_email '
      'LEFT JOIN quizzes ON quizzes.id = user_scores.quiz_id '
      'ORDER BY completed_at DESC',
    );
  }

  Future<void> deleteScore(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      await _recordDeletion(txn, 'user_scores', id);
      await txn.delete('user_scores', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> updateScore(String id, Map<String, Object?> values) async {
    const allowed = {'score', 'total'};
    final updates = Map<String, Object?>.fromEntries(
      values.entries.where((entry) => allowed.contains(entry.key)),
    )..['is_synced'] = 0;
    if (updates.length == 1) return;
    final score = updates['score'];
    final total = updates['total'];
    if (score is num &&
        total is num &&
        (score < 0 || total <= 0 || score > total)) {
      throw ArgumentError('Score must be between zero and a positive total.');
    }
    final db = await database;
    if (score is num || total is num) {
      final existing = await db.query(
        'user_scores',
        columns: ['score', 'total'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (existing.isEmpty) return;
      final nextScore = (score ?? existing.first['score']! as num) as num;
      final nextTotal = (total ?? existing.first['total']! as num) as num;
      if (nextScore < 0 || nextTotal <= 0 || nextScore > nextTotal) {
        throw ArgumentError('Score must be between zero and a positive total.');
      }
    }
    await db.update('user_scores', updates, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> saveSetting(String key, String value) async {
    final db = await database;
    await db.insert('settings', {
      'key': key,
      'value': value,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getSetting(String key) async {
    final db = await database;
    final rows = await db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value']! as String;
  }

  Future<List<Map<String, Object?>>> getSettings() async {
    final db = await database;
    return db.query('settings', orderBy: 'key');
  }

  Future<void> deleteSetting(String key) async {
    final db = await database;
    await db.delete('settings', where: 'key = ?', whereArgs: [key]);
  }

  Future<void> cachePdf({
    required String id,
    required String title,
    required String localPath,
  }) async {
    final db = await database;
    await db.insert('offline_pdfs', {
      'id': id,
      'title': title,
      'local_path': localPath,
      'cached_at': DateTime.now().toUtc().toIso8601String(),
      'is_synced': 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deletePdf(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      await _recordDeletion(txn, 'offline_pdfs', id);
      await txn.delete('offline_pdfs', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<List<Map<String, Object?>>> getOfflinePdfs() async {
    final db = await database;
    return db.query('offline_pdfs', orderBy: 'title COLLATE NOCASE');
  }

  Future<void> saveTextbook({
    required String id,
    required String title,
    required String content,
    String? createdBy,
    bool isSynced = false,
  }) async {
    final db = await database;
    await db.insert('offline_textbooks', {
      'id': id,
      'title': title,
      'content': content,
      'created_by': createdBy,
      'cached_at': DateTime.now().toUtc().toIso8601String(),
      'is_synced': isSynced ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, Object?>>> getTextbooks() async {
    final db = await database;
    return db.query('offline_textbooks', orderBy: 'title COLLATE NOCASE');
  }

  Future<void> deleteTextbook(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      await _recordDeletion(txn, 'offline_textbooks', id);
      await txn.delete('offline_textbooks', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<List<Map<String, Object?>>> getPendingRecords(String table) async {
    _validateTable(table);
    final db = await database;
    return db.query(table, where: 'is_synced = ?', whereArgs: [0]);
  }

  Future<void> markRecordsSynced(String table, List<String> ids) async {
    _validateTable(table);
    if (ids.isEmpty) return;
    final db = await database;
    final placeholders = List.filled(ids.length, '?').join(', ');
    await db.rawUpdate(
      'UPDATE $table SET is_synced = 1 WHERE id IN ($placeholders)',
      ids,
    );
  }

  Future<List<Map<String, Object?>>> getPendingDeletions(String table) async {
    _validateTable(table);
    final db = await database;
    return db.query(
      'sync_deletions',
      where: 'table_name = ? AND is_synced = 0',
      whereArgs: [table],
    );
  }

  Future<void> markDeletionsSynced(List<String> deletionIds) async {
    if (deletionIds.isEmpty) return;
    final db = await database;
    final placeholders = List.filled(deletionIds.length, '?').join(', ');
    await db.rawUpdate(
      'UPDATE sync_deletions SET is_synced = 1 WHERE id IN ($placeholders)',
      deletionIds,
    );
  }

  Future<void> mergeSyncedRecords(
    String table,
    List<Map<String, Object?>> records,
  ) async {
    _validateTable(table);
    final db = await database;
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final validColumns = columns.map((column) => column['name']! as String);
    await db.transaction((txn) async {
      for (final record in records) {
        if (record['id'] is! String) {
          throw FormatException('Cloud $table record has no string ID.');
        }
        final existing = await txn.query(
          table,
          columns: ['is_synced'],
          where: 'id = ?',
          whereArgs: [record['id']],
          limit: 1,
        );
        if (existing.isNotEmpty && existing.first['is_synced'] == 0) continue;
        final values = <String, Object?>{
          for (final entry in record.entries)
            if (validColumns.contains(entry.key) && entry.key != 'is_synced')
              entry.key: entry.value,
          'is_synced': 1,
        };
        await txn.insert(
          table,
          values,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  void _validateTable(String table) {
    if (!syncableTables.contains(table)) {
      throw ArgumentError.value(table, 'table', 'Unsupported sync table.');
    }
  }

  Future<void> _recordDeletion(
    DatabaseExecutor db,
    String table,
    String recordId,
  ) async {
    await db.insert('sync_deletions', {
      'id': '$table:$recordId',
      'table_name': table,
      'record_id': recordId,
      'deleted_at': DateTime.now().toUtc().toIso8601String(),
      'is_synced': 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  String _normalizeEmail(String email) => email.trim().toLowerCase();

  Future<String> _newStudentUsername(
    DatabaseExecutor db, {
    required String email,
    required String id,
    String? requested,
  }) async {
    final requestedUsername = _normalizeOptionalText(requested)?.toLowerCase();
    if (requestedUsername != null) {
      if (!RegExp(r'^[a-z0-9._-]{3,32}$').hasMatch(requestedUsername)) {
        throw ArgumentError.value(
          requested,
          'studentUsername',
          'Use 3–32 letters, numbers, dots, underscores, or hyphens.',
        );
      }
      final existing = await db.query(
        'users',
        columns: ['id'],
        where: 'lower(trim(student_username)) = ? AND id != ?',
        whereArgs: [requestedUsername, id],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        throw ArgumentError.value(
          requested,
          'studentUsername',
          'That student username is already in use.',
        );
      }
      return requestedUsername;
    }

    final localPart = email.split('@').first;
    final base = localPart
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9._-]'), '')
        .replaceAll(RegExp(r'^[._-]+|[._-]+$'), '');
    final safeId = id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final suffix = safeId.substring(
      safeId.length > 12 ? safeId.length - 12 : 0,
    );
    final usernameBase = base.isEmpty ? 'student' : base;
    final baseLimit = 32 - suffix.length - 1;
    final candidateBase = usernameBase.length > baseLimit
        ? usernameBase.substring(0, baseLimit)
        : usernameBase;
    return '${candidateBase}_$suffix';
  }

  String _canonicalStatus(Object? status) => switch (status) {
    'pending' => 'pending',
    'blocked' || 'rejected' => 'blocked',
    _ => 'active',
  };

  String _legacyAccountStatus(Object? status) => switch (status) {
    'pending' => 'pending',
    'blocked' => 'blocked',
    'rejected' => 'rejected',
    _ => 'approved',
  };

  String? _normalizeOptionalText(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;

  String? _normalizeOptionalEmail(Object? email) =>
      email is String && email.trim().isNotEmpty
      ? _normalizeEmail(email)
      : null;

  bool _isValidEmail(String email) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim());

  String _newId() {
    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    try {
      final randomSuffix = Random.secure().nextInt(0x7fffffff);
      return '$timestamp-$randomSuffix';
    } on RangeError {
      final fallbackSuffix = Random().nextInt(900000) + 100000;
      return '$timestamp-$fallbackSuffix';
    }
  }
}
