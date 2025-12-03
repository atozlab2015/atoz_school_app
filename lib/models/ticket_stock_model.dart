import 'package:cloud_firestore/cloud_firestore.dart';

class TicketStock {
  final String id;
  final String studentId;
  final int totalAmount;
  final int remainingAmount;
  final DateTime expiryDate;
  final DateTime createdAt;
  final String status;
  final String? createdByTransactionId;
  
  // ★追加されたフィールド
  final String? classGroupId; // 発行元のクラスID
  final String? className;    // 発行元のクラス名
  final String? validLevelId; // ★有効なレベルID

  TicketStock({
    required this.id,
    required this.studentId,
    required this.totalAmount,
    required this.remainingAmount,
    required this.expiryDate,
    required this.createdAt,
    required this.status,
    this.createdByTransactionId,
    this.classGroupId, // ★追加
    this.className,    // ★追加
    this.validLevelId, // ★追加
  });

  Map<String, dynamic> toMap() {
    return {
      'studentId': studentId,
      'totalAmount': totalAmount,
      'remainingAmount': remainingAmount,
      'expiryDate': expiryDate,
      'createdAt': createdAt,
      'status': status,
      'createdByTransactionId': createdByTransactionId,
      'classGroupId': classGroupId,
      'className': className,
      'validLevelId': validLevelId, // ★追加
    };
  }

  factory TicketStock.fromMap(Map<String, dynamic> data, String id) {
    return TicketStock(
      id: id,
      studentId: data['studentId'] ?? '',
      totalAmount: data['totalAmount'] ?? 0,
      remainingAmount: data['remainingAmount'] ?? 0,
      expiryDate: (data['expiryDate'] as Timestamp).toDate(),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      status: data['status'] ?? 'active',
      createdByTransactionId: data['createdByTransactionId'],
      classGroupId: data['classGroupId'],
      className: data['className'],
      validLevelId: data['validLevelId'], // ★追加
    );
  }
  
  bool get isExpired => DateTime.now().isAfter(expiryDate);
}