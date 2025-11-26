import 'package:cloud_firestore/cloud_firestore.dart';

class Ticket {
  final String id;
  final String studentId; 
  
  final String validLevelId;   
  final String validLevelName; 
  
  final DateTime issueDate;          
  final DateTime expiryDate;         
  
  final DateTime? originDate;        // 元の日付
  final String? originTimeRange;     // ★追加: 元の時間範囲表記 (例 "16:25～17:10")
  
  final bool isUsed;                 
  final String? usedForReservationId; 
  
  final DateTime? usedForDate;       // ★追加: 振替先の日付
  final String? usedForTimeRange;    // ★追加: 振替先の時間範囲表記

  // ★追加: キャンセル元のレッスンID (カレンダーのグレー表示判定に使用)
  final String? sourceLessonId;      

  Ticket({
    required this.id,
    required this.studentId,
    required this.validLevelId,
    required this.validLevelName,
    required this.issueDate,
    required this.expiryDate,
    this.originDate,
    this.originTimeRange,
    this.isUsed = false,
    this.usedForReservationId,
    this.usedForDate,
    this.usedForTimeRange,
    this.sourceLessonId,
  });

  factory Ticket.fromMap(Map<String, dynamic> data, String id) {
    return Ticket(
      id: id,
      studentId: data['studentId'] ?? '',
      validLevelId: data['validLevelId'] ?? '',
      validLevelName: data['validLevelName'] ?? '',
      issueDate: (data['issueDate'] as Timestamp).toDate(),
      expiryDate: (data['expiryDate'] as Timestamp).toDate(),
      originDate: data['originDate'] != null ? (data['originDate'] as Timestamp).toDate() : null,
      originTimeRange: data['originTimeRange'],
      isUsed: data['isUsed'] ?? false,
      usedForReservationId: data['usedForReservationId'],
      usedForDate: data['usedForDate'] != null ? (data['usedForDate'] as Timestamp).toDate() : null,
      usedForTimeRange: data['usedForTimeRange'],
      sourceLessonId: data['sourceLessonId'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'studentId': studentId,
      'validLevelId': validLevelId,
      'validLevelName': validLevelName,
      'issueDate': issueDate,
      'expiryDate': expiryDate,
      'originDate': originDate,
      'originTimeRange': originTimeRange,
      'isUsed': isUsed,
      'usedForReservationId': usedForReservationId,
      'usedForDate': usedForDate,
      'usedForTimeRange': usedForTimeRange,
      'sourceLessonId': sourceLessonId,
    };
  }
}