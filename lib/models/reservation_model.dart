import 'package:cloud_firestore/cloud_firestore.dart';

class Reservation {
  final String id;
  final String lessonInstanceId; // 予約対象のレッスン (lessonInstancesのID)
  final String studentId;        // 予約を行う生徒のID
  final String requestType;      // 予約の種類 (例: 'transfer' (振替), 'spot' (都度予約), 'cancellation')
  final String status;           // 予約の状態 (例: 'pending', 'approved', 'rejected', 'cancelled')
  final Timestamp requestedAt;    // リクエスト日時
  
  // 振替予約時に、どのレッスンを休んだかを示すID (オプション)
  final String? originalLessonId; 

  Reservation({
    required this.id,
    required this.lessonInstanceId,
    required this.studentId,
    required this.requestType,
    required this.status,
    required this.requestedAt,
    this.originalLessonId,
  });

  // Firestore Mapへの変換
  Map<String, dynamic> toMap() {
    return {
      'lessonInstanceId': lessonInstanceId,
      'studentId': studentId,
      'requestType': requestType,
      'status': status,
      'requestedAt': requestedAt,
      'originalLessonId': originalLessonId,
    };
  }

  // Firestore Mapからの変換 (今回は省略)
  // factory Reservation.fromMap(...)
}