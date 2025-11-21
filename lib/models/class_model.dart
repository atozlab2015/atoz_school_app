// lib/models/class_model.dart (最終版)

class Subject {
  final String id;
  final String name;
  Subject({required this.id, required this.name});
  Map<String, dynamic> toMap() => {'name': name};
}

class Course {
  final String id;
  final String subjectId;
  final String name; 
  Course({required this.id, required this.subjectId, required this.name});
  Map<String, dynamic> toMap() => {'subjectId': subjectId, 'name': name};
}

class ClassLevel {
  final String id;
  final String courseId;
  final String name; 
  ClassLevel({required this.id, required this.courseId, required this.name});
  Map<String, dynamic> toMap() => {
    'courseId': courseId,
    'name': name,
  };
}

class ClassGroup {
  final String id;
  // ▼ 新しく追加・修正されたフィールド
  final String subjectId; 
  final String courseId; 
  final String levelId; 
  // ... (他のフィールド) ...
  final String teacherName; 
  final String dayOfWeek;
  final String startTime;
  final int durationMinutes;
  final int capacity;

  final String bookingType;
  final String spotLimitType;
  final int monthlyLimitCount;

  ClassGroup({
    required this.id,
    // ▼ コンストラクタに必須引数を追加
    required this.subjectId, 
    required this.courseId, 
    required this.levelId,
    required this.teacherName,
    required this.dayOfWeek,
    required this.startTime,
    required this.durationMinutes,
    required this.capacity,
    required this.bookingType,
    this.spotLimitType = 'unlimited',
    this.monthlyLimitCount = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      // ▼ toMapにもフィールドを追加
      'subjectId': subjectId, 
      'courseId': courseId, 
      'levelId': levelId,
      'teacherName': teacherName,
      'dayOfWeek': dayOfWeek,
      'startTime': startTime,
      'durationMinutes': durationMinutes,
      'capacity': capacity,
      'bookingType': bookingType,
      'spotLimitType': spotLimitType,
      'monthlyLimitCount': monthlyLimitCount,
    };
  }
}