import 'package:cloud_firestore/cloud_firestore.dart';

class LessonTransaction {
  final String id;
  final String studentId;
  final int amount;
  final String type;
  final DateTime createdAt;
  final String? adminId;
  final String? note;
  
  // ★追加されたフィールド
  final String? classGroupId;
  final String? className;
  final String? validLevelId; // ★追加

  LessonTransaction({
    required this.id,
    required this.studentId,
    required this.amount,
    required this.type,
    required this.createdAt,
    this.adminId,
    this.note,
    this.classGroupId,
    this.className,
    this.validLevelId, // ★追加
  });

  Map<String, dynamic> toMap() {
    return {
      'studentId': studentId,
      'amount': amount,
      'type': type,
      'createdAt': createdAt,
      'adminId': adminId,
      'note': note,
      'classGroupId': classGroupId,
      'className': className,
      'validLevelId': validLevelId, // ★追加
    };
  }

  factory LessonTransaction.fromMap(Map<String, dynamic> data, String id) {
    return LessonTransaction(
      id: id,
      studentId: data['studentId'] ?? '',
      amount: data['amount'] ?? 0,
      type: data['type'] ?? 'purchase',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      adminId: data['adminId'],
      note: data['note'],
      classGroupId: data['classGroupId'],
      className: data['className'],
      validLevelId: data['validLevelId'], // ★追加
    );
  }
}