/// Student model representing a person enrolled in the system
class Student {
  final int? id;
  final String name;
  final String rollNumber;
  final String className;
  final DateTime enrollmentDate;

  Student({
    this.id,
    required this.name,
    required this.rollNumber,
    required this.className,
    DateTime? enrollmentDate,
  }) : enrollmentDate = enrollmentDate ?? DateTime.now();

  /// Convert Student to JSON for database storage
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'roll_number': rollNumber,
      'class': className,
      'enrollment_date': enrollmentDate.toIso8601String(),
    };
  }

  /// Create Student from database map
  factory Student.fromMap(Map<String, dynamic> map) {
    return Student(
      id: map['id'] as int?,
      name: map['name'] as String,
      rollNumber: map['roll_number'] as String,
      className: map['class'] as String,
      enrollmentDate: DateTime.parse(map['enrollment_date'] as String),
    );
  }

  @override
  String toString() => 'Student(id: $id, name: $name, rollNumber: $rollNumber, class: $className)';
}
