import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../models/ticket_model.dart';
import '../../models/student_model.dart';
import '../../models/lesson_model.dart'; 
import 'transfer_lesson_selector_screen.dart';

class TicketListScreen extends StatelessWidget {
  const TicketListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('振替チケット一覧'),
        backgroundColor: Colors.blue.shade700,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('students')
            .where('parentId', isEqualTo: uid)
            .snapshots(),
        builder: (context, studentSnap) {
          if (studentSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (!studentSnap.hasData || studentSnap.data!.docs.isEmpty) {
            return const Center(child: Text('生徒情報が見つかりません'));
          }

          final students = studentSnap.data!.docs.map((doc) {
             return Student.fromMap(doc.data() as Map<String, dynamic>, doc.id);
          }).toList();
          
          final studentIds = students.map((s) => s.id).toList();
          final studentMap = {for (var s in students) s.id: s}; 

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('tickets')
                .where('studentId', whereIn: studentIds)
                .orderBy('expiryDate', descending: false) 
                .snapshots(),
            builder: (context, ticketSnap) {
              if (ticketSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = ticketSnap.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Center(child: Text('チケットを持っていません'));
              }

              final tickets = docs
                  .map((d) => Ticket.fromMap(d.data() as Map<String, dynamic>, d.id))
                  .toList();

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: tickets.length,
                itemBuilder: (context, index) {
                  final ticket = tickets[index];
                  final student = studentMap[ticket.studentId];
                  final studentName = student != null ? student.fullName : '不明';
                  
                  final isExpired = ticket.expiryDate.isBefore(DateTime.now());
                  final isAvailable = !ticket.isUsed && !isExpired;

                  Color cardColor = Colors.white;
                  if (ticket.isUsed) cardColor = Colors.grey.shade300;
                  else if (isExpired) cardColor = Colors.red.shade50;
                  else cardColor = Colors.green.shade50;

                  String statusText = '利用可能';
                  if (ticket.isUsed) statusText = '使用済み';
                  else if (isExpired) statusText = '期限切れ';
                  
                  // ★表記の作成
                  // 元の日程
                  String originText = '日付不明';
                  if (ticket.originDate != null) {
                    final dateStr = DateFormat('M/d(E)', 'ja').format(ticket.originDate!);
                    // 時間範囲があればそれを使う、なければ日付のみ
                    final timeStr = ticket.originTimeRange ?? ''; 
                    originText = '$dateStr $timeStr';
                  } else {
                    originText = DateFormat('M/d(E)', 'ja').format(ticket.issueDate) + ' 発行';
                  }

                  // 振替先の日程 (使用済みの場合)
                  String usedText = '';
                  if (ticket.isUsed && ticket.usedForDate != null) {
                    final dateStr = DateFormat('M/d(E)', 'ja').format(ticket.usedForDate!);
                    final timeStr = ticket.usedForTimeRange ?? '';
                    usedText = ' → $dateStr $timeStr に振替済';
                  }

                  return Card(
                    color: cardColor,
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      children: [
                        ListTile(
                          title: Text('$studentName さん : ${ticket.validLevelName}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.event_busy, size: 16, color: Colors.orange),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      originText + usedText, // ★元→先 を結合して表示
                                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text('有効期限: ${DateFormat('yyyy/MM/dd').format(ticket.expiryDate)}'),
                            ],
                          ),
                          trailing: Chip(
                            label: Text(statusText, style: const TextStyle(fontSize: 12)),
                            backgroundColor: isAvailable ? Colors.green : Colors.grey,
                            labelStyle: const TextStyle(color: Colors.white),
                          ),
                        ),
                        if (isAvailable && student != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.check_circle_outline),
                                label: const Text('このチケットを使う (予約する)'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => TransferLessonSelectorScreen(
                                        student: student,
                                        currentLesson: LessonInstance(
                                          id: 'ticket_placeholder', 
                                          classGroupId: '', 
                                          levelId: ticket.validLevelId, 
                                          teacherName: '', 
                                          startTime: DateTime.now(), 
                                          endTime: DateTime.now(), 
                                          capacity: 0, 
                                          currentBookings: 0, 
                                          isCancelled: false
                                        ),
                                        targetLevelId: ticket.validLevelId,
                                        useTicket: ticket,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                      ],
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