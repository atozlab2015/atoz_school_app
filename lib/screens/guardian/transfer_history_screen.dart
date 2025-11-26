import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../models/student_model.dart';
import '../../models/ticket_model.dart';

class TransferHistoryScreen extends StatelessWidget {
  const TransferHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('振替・欠席履歴'),
        backgroundColor: Colors.blueGrey,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('students')
            .where('parentId', isEqualTo: uid)
            .snapshots(),
        builder: (context, studentSnap) {
          if (studentSnap.hasError) {
            return Center(child: Text('エラー: ${studentSnap.error}'));
          }
          if (studentSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (!studentSnap.hasData || studentSnap.data!.docs.isEmpty) {
            return const Center(child: Text('生徒情報が見つかりません'));
          }

          final students = studentSnap.data!.docs.map((doc) => Student.fromMap(doc.data() as Map<String, dynamic>, doc.id)).toList();
          final studentIds = students.map((s) => s.id).toList();
          final studentMap = {for (var s in students) s.id: s.fullName};

          if (studentIds.isEmpty) return const Center(child: Text('生徒データがありません'));

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('tickets')
                .where('studentId', whereIn: studentIds)
                .orderBy('issueDate', descending: true) // 新しい順
                .snapshots(),
            builder: (context, ticketSnap) {
              // ★修正: エラーチェックを追加
              if (ticketSnap.hasError) {
                // コンソールにリンクを出すためにprint
                print("History Error: ${ticketSnap.error}");
                return Center(child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text('読み込みエラーが発生しました。\n開発者コンソールを確認してインデックスを作成してください。\n${ticketSnap.error}'),
                ));
              }

              if (ticketSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = ticketSnap.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Center(child: Text('履歴はありません'));
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final ticket = Ticket.fromMap(docs[index].data() as Map<String, dynamic>, docs[index].id);
                  final name = studentMap[ticket.studentId] ?? '';
                  
                  // ステータス判定
                  String status = '';
                  Color color = Colors.grey;
                  if (ticket.validLevelId == 'forfeited') {
                    status = '振替なし欠席';
                    color = Colors.grey;
                  } else if (ticket.isUsed) {
                    status = '振替済み';
                    color = Colors.blue;
                  } else {
                    status = '振替待ち (保留)';
                    color = Colors.green;
                  }

                  // 元の日付
                  String originText = ticket.originTimeRange ?? DateFormat('yyyy/MM/dd').format(ticket.originDate ?? ticket.issueDate);
                  if (ticket.originDate != null) {
                     originText = DateFormat('M/d(E)', 'ja').format(ticket.originDate!);
                     if (ticket.originTimeRange != null) {
                       originText += ' ${ticket.originTimeRange}';
                     }
                  }

                  return Card(
                    child: ListTile(
                      leading: Icon(Icons.history, color: color),
                      title: Text('$name ($status)', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text('元: $originText'),
                          if (ticket.usedForDate != null)
                            Text('先: ${DateFormat('M/d(E)', 'ja').format(ticket.usedForDate!)} ${ticket.usedForTimeRange ?? ''}', 
                                style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text('操作: ${DateFormat('MM/dd HH:mm').format(ticket.issueDate)}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}