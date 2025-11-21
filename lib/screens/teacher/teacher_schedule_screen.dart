import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart'; 
import 'package:atoz_school_app/models/lesson_model.dart'; 
import 'package:atoz_school_app/models/student_model.dart'; 
import 'lesson_attendance_screen.dart';

class TeacherScheduleScreen extends StatelessWidget {
  const TeacherScheduleScreen({super.key});

  // ■ レギュラー生徒の数を正確に数える関数
  Future<int> _countRegulars(String classGroupId, DateTime lessonDate) async {
    try {
      // 1. そのクラス枠IDを持っている生徒を検索
      final snapshot = await FirebaseFirestore.instance
          .collection('students')
          .where('enrolledGroupIds', arrayContains: classGroupId)
          .get();

      int count = 0;
      // 2. 有効期間チェック（開始日〜終了日）
      for (var doc in snapshot.docs) {
        final student = Student.fromMap(doc.data(), doc.id);
        for (var enrollment in student.enrollments) {
          if (enrollment.groupId == classGroupId) {
             // 時間を切り捨てて日付のみで比較
             final dateOnly = DateTime(lessonDate.year, lessonDate.month, lessonDate.day);
             final startDate = DateTime(enrollment.startDate.year, enrollment.startDate.month, enrollment.startDate.day);
             
             bool isActive = !dateOnly.isBefore(startDate);
             if (enrollment.endDate != null) {
               final endDate = DateTime(enrollment.endDate!.year, enrollment.endDate!.month, enrollment.endDate!.day);
               if (dateOnly.isAfter(endDate)) isActive = false;
             }
             
             if (isActive) count++;
          }
        }
      }
      return count;
    } catch (e) {
      print('Count Error: $e');
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: const Text('講師ダッシュボード')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        
        final userData = snapshot.data!.data() as Map<String, dynamic>;
        final teacherName = userData['name'] as String? ?? '講師'; 

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('lessonInstances')
              .where('teacherName', isEqualTo: teacherName) 
              .where('startTime', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday))
              .orderBy('startTime') 
              .limit(500) 
              .snapshots(),
          builder: (context, lessonSnapshot) {
            if (!lessonSnapshot.hasData) {
              return Scaffold(
                appBar: AppBar(
                  title: Text('${teacherName}先生のスケジュール'),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.logout),
                      onPressed: () => FirebaseAuth.instance.signOut(),
                    ),
                  ],
                ),
                body: const Center(child: CircularProgressIndicator()),
              );
            }

            final lessonDocs = lessonSnapshot.data!.docs;

            return Scaffold(
              appBar: AppBar(
                title: Text('${teacherName}先生のスケジュール'),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.logout),
                    onPressed: () => FirebaseAuth.instance.signOut(),
                  ),
                ],
              ),
              body: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ようこそ、${teacherName}先生！', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const Divider(),
                    const Text('今後の予定', style: TextStyle(fontSize: 16)),
                    const SizedBox(height: 10),
                    
                    if (lessonDocs.isEmpty)
                       const Expanded(
                         child: Center(child: Text('これからの予定はありません。')),
                       ),

                    Expanded(
                      child: ListView.builder(
                        itemCount: lessonDocs.length,
                        itemBuilder: (context, index) {
                          final doc = lessonDocs[index];
                          final lesson = LessonInstance.fromMap(doc.data() as Map<String, dynamic>, doc.id);
                          final dateFormat = DateFormat('M/d(E) HH:mm', 'ja'); 
                          
                          // ★修正点: 非同期でレギュラー人数を数えて表示
                          return FutureBuilder<int>(
                            future: _countRegulars(lesson.classGroupId, lesson.startTime),
                            builder: (context, countSnapshot) {
                              final regularCount = countSnapshot.data ?? 0; // ロード中は0
                              final transferCount = lesson.currentBookings; // 振替（予約）数

                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                child: ListTile(
                                  leading: const Icon(Icons.calendar_today, color: Colors.indigo),
                                  title: Text(
                                    dateFormat.format(lesson.startTime),
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  // ▼▼▼ ここを変更しました ▼▼▼
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('クラスID: ${lesson.classGroupId}'),
                                      Text(
                                        'レギュラー: $regularCount名、振替: $transferCount名  (計 ${regularCount + transferCount}名)',
                                        style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                  // ▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲
                                  trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => LessonAttendanceScreen(lesson: lesson),
                                      ),
                                    );
                                  },
                                ),
                              );
                            }
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}