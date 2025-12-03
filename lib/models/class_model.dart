import 'package:cloud_firestore/cloud_firestore.dart';

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
  final String subjectId; 
  final String courseId; 
  final String levelId; 
  
  final String teacherName; 
  final String dayOfWeek;
  final String startTime;
  final int durationMinutes;
  final int capacity;

  final String bookingType;
  final String spotLimitType;
  final int monthlyLimitCount;

  // ★追加: 有効期間
  final DateTime? validFrom; // 開始日 (nullなら無期限/最初から)
  final DateTime? validTo;   // 終了日 (nullなら無期限/ずっと続く)

  ClassGroup({
    required this.id,
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
    this.validFrom, // ★追加
    this.validTo,   // ★追加
  });

  Map<String, dynamic> toMap() {
    return {
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
      // ★追加
      'validFrom': validFrom, 
      'validTo': validTo,
    };
  }

  // ★追加: 編集時などに便利なので fromMap を作成
  factory ClassGroup.fromMap(Map<String, dynamic> data, String id) {
    return ClassGroup(
      id: id,
      subjectId: data['subjectId'] ?? '',
      courseId: data['courseId'] ?? '',
      levelId: data['levelId'] ?? '',
      teacherName: data['teacherName'] ?? '',
      dayOfWeek: data['dayOfWeek'] ?? '',
      startTime: data['startTime'] ?? '',
      durationMinutes: data['durationMinutes'] ?? 0,
      capacity: data['capacity'] ?? 0,
      bookingType: data['bookingType'] ?? 'fixed',
      spotLimitType: data['spotLimitType'] ?? 'unlimited',
      monthlyLimitCount: data['monthlyLimitCount'] ?? 0,
      validFrom: (data['validFrom'] as Timestamp?)?.toDate(),
      validTo: (data['validTo'] as Timestamp?)?.toDate(),
    );
  }
}