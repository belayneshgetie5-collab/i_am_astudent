class ExamResult {
  const ExamResult({
    required this.id,
    required this.studentEmail,
    required this.quizId,
    required this.score,
    required this.total,
    required this.completedAt,
  });

  final String id;
  final String studentEmail;
  final String quizId;
  final double score;
  final double total;
  final DateTime completedAt;

  factory ExamResult.fromMap(Map<String, Object?> map) => ExamResult(
    id: map['id']! as String,
    studentEmail: map['student_email']! as String,
    quizId: map['quiz_id']! as String,
    score: (map['score']! as num).toDouble(),
    total: (map['total']! as num).toDouble(),
    completedAt: DateTime.parse(map['completed_at']! as String),
  );

  Map<String, Object?> toMap({bool isSynced = false}) => {
    'id': id,
    'student_email': studentEmail,
    'quiz_id': quizId,
    'score': score,
    'total': total,
    'completed_at': completedAt.toUtc().toIso8601String(),
    'is_synced': isSynced ? 1 : 0,
  };
}
