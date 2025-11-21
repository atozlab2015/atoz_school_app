import 'package:cloud_firestore/cloud_firestore.dart';

class LessonInstance {
  final String id;
  final String classGroupId;
  // ▼▼▼ 追加: レベルID (コース名などを引くために必要) ▼▼▼
  final String levelId; 
  // ▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲
  final String teacherName;
  final DateTime startTime;
  final DateTime endTime;
  final int capacity;
  final int currentBookings;
  final bool isCancelled;

  LessonInstance({
    required this.id,
    required this.classGroupId,
    required this.levelId, // ★追加
    required this.teacherName,
    required this.startTime,
    required this.endTime,
    required this.capacity,
    required this.currentBookings,
    required this.isCancelled,
  });

  // Firestore Mapからの変換処理
  factory LessonInstance.fromMap(Map<String, dynamic> data, String id) {
    return LessonInstance(
      id: id,
      classGroupId: data['classGroupId'] ?? '',
      levelId: data['levelId'] ?? '', // ★追加: データ読み込み
      teacherName: data['teacherName'] ?? '',
      // TimestampをDateTimeに変換
      startTime: (data['startTime'] as Timestamp).toDate(),
      endTime: (data['endTime'] as Timestamp).toDate(),
      capacity: data['capacity'] ?? 0,
      currentBookings: data['currentBookings'] ?? 0,
      isCancelled: data['isCancelled'] ?? false,
    );
  }
}