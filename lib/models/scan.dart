class Scan {
  final String studentId;
  final DateTime timestamp;
  final String studentName;
  final String studentEmail;

  const Scan({
    required this.studentId,
    required this.timestamp,
    required this.studentName,
    required this.studentEmail,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Scan && other.studentId == studentId;
  }

  @override
  int get hashCode => studentId.hashCode;
}

class ScanResult {
  final String code;
  final DateTime timestamp;

  const ScanResult({
    required this.code,
    required this.timestamp,
  });
}