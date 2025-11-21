import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart'; 
import 'package:atoz_school_app/models/reservation_model.dart';

// ★修正点：StatelessWidget から StatefulWidget に変更
class ApprovalDashboardScreen extends StatefulWidget {
  const ApprovalDashboardScreen({super.key});

  @override
  State<ApprovalDashboardScreen> createState() => _ApprovalDashboardScreenState();
}

class _ApprovalDashboardScreenState extends State<ApprovalDashboardScreen> {
  
// lib/screens/admin/approval_dashboard_screen.dart 内の _updateStatus メソッド全体を上書き

 Future<void> _updateStatus(String reservationId, String lessonInstanceId, String newStatus) async {
    final currentContext = context;

    try {
      // Firebaseのトランザクション機能を使用（データの矛盾を防ぐため）
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        // 1. 処理対象のドキュメント参照を取得
        final reservationRef = FirebaseFirestore.instance.collection('reservations').doc(reservationId);
        final lessonRef = FirebaseFirestore.instance.collection('lessonInstances').doc(lessonInstanceId);

        // 2. 承認 ('approved') の場合のみ、定員チェックとカウントアップを行う
        if (newStatus == 'approved') {
          final lessonSnapshot = await transaction.get(lessonRef);
          
          if (!lessonSnapshot.exists) {
            throw Exception("対象のレッスンが存在しません。");
          }

          final currentBookings = lessonSnapshot.data()!['currentBookings'] as int? ?? 0;
          final capacity = lessonSnapshot.data()!['capacity'] as int? ?? 0;

          if (currentBookings >= capacity) {
            throw Exception("満席のため承認できません。");
          }

          // 定員に空きがあればカウントアップ
          transaction.update(lessonRef, {
            'currentBookings': currentBookings + 1,
          });
        }

        // 3. リクエストのステータスを更新
        transaction.update(reservationRef, {'status': newStatus});
      });

      // 4. 成功メッセージ
      if (!mounted) return;
      ScaffoldMessenger.of(currentContext).showSnackBar(
        SnackBar(content: Text('リクエストを「$newStatus」に更新し、予約枠を調整しました。')),
      );

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(currentContext).showSnackBar(
        SnackBar(
          content: Text('エラー: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // ステータスが 'pending' の予約リクエストのみを取得
    return Scaffold(
      appBar: AppBar(
        title: const Text('【承認】振替・予約リクエスト'),
        backgroundColor: Colors.redAccent,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('reservations')
            .where('status', isEqualTo: 'pending')
            .orderBy('requestedAt', descending: false)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return Center(child: Text('エラー: ${snapshot.error}'));

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(
              child: Text('現在、承認待ちのリクエストはありません。', style: TextStyle(fontSize: 16)),
            );
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final reservation = Reservation(
                id: docs[index].id,
                lessonInstanceId: data['lessonInstanceId'] ?? 'N/A',
                studentId: data['studentId'] ?? '不明な生徒',
                requestType: data['requestType'] ?? '不明',
                status: data['status'] ?? 'pending',
                requestedAt: data['requestedAt'] as Timestamp,
              );
              
              final requestedTime = DateFormat('M/d HH:mm').format(reservation.requestedAt.toDate());

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Colors.yellow.shade50,
                child: ListTile(
                  title: Text(
                    '生徒ID: ${reservation.studentId} (${reservation.requestType})', 
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text('リクエスト日時: $requestedTime\nレッスンID: ${reservation.lessonInstanceId}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 承認ボタン
                      IconButton(
                        icon: const Icon(Icons.check_circle, color: Colors.green),
                        onPressed: () => _updateStatus(
                          reservation.id, 
                          reservation.lessonInstanceId, // ★ここを追加
                          'approved'
                        ),
                      ),
                      // 否認ボタン
                      IconButton(
                        icon: const Icon(Icons.cancel, color: Colors.red),
                        onPressed: () => _updateStatus(
                          reservation.id, 
                          reservation.lessonInstanceId, // ★ここを追加
                          'rejected'
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}