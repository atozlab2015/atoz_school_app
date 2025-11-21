// lib/screens/admin/class_group_exception_screen.dart を以下で上書き

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class ClassGroupExceptionScreen extends StatelessWidget {
  final String subjectId;
  final String courseId;
  final String levelId;
  final String subjectName;
  final String courseName;
  final String levelName;

  const ClassGroupExceptionScreen({
    super.key,
    required this.subjectId,
    required this.courseId,
    required this.levelId,
    required this.subjectName,
    required this.courseName,
    required this.levelName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${subjectName}/${courseName}/${levelName} の例外設定'),
        backgroundColor: Colors.red.shade900,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              '休講日を設定したいクラスの枠を選択してください。',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
            ),
          ),
          
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
              .collection('groups')
                  // ▼▼▼ 修正点: 3つのIDで厳格にフィルタリング ▼▼▼
                  .where('subjectId', isEqualTo: subjectId)
                  .where('courseId', isEqualTo: courseId)
                  .where('levelId', isEqualTo: levelId)
                  // ▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲
                  .orderBy('dayOfWeek') 
                  .orderBy('startTime') 
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (snapshot.hasError) return Center(child: Text('エラー: ${snapshot.error}'));

                final docs = snapshot.data!.docs;
                
                if (docs.isEmpty) {
                  return const Center(child: Text('このレベルにはクラス枠が設定されていません。'));
                }

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    
                    // ▼▼▼ 修正点：DBからStringとして直接取得・利用 ▼▼▼
                    final dayOfWeek = data['dayOfWeek'] as String? ?? '不明'; // "火曜"
                    final startTime = data['startTime'] as String? ?? '00:00'; // "16:25"
                    final duration = data['durationMinutes'] as int? ?? 0;
                    
                    // 終了時刻の計算は複雑なので、ここでは表示のみに留めます（例: 16:25 + 45分）
                    
                    return ListTile(
                      leading: const Icon(Icons.schedule, color: Colors.indigo),
                      title: Text('${dayOfWeek} ${startTime} (${data['teacherName']}先生)'),
                      subtitle: Text('レッスン時間: ${duration}分'),
                      onTap: () => _showExceptionDialog(
                        context, 
                        docs[index].id, // group ID
                        '${dayOfWeek} ${startTime}',
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ■ クラス別休講日追加ダイアログ (ロジックは変更なし)
  void _showExceptionDialog(BuildContext context, String groupId, String groupTime) {
    // ... (ダイアログロジックは省略しませんが、今回は割愛します)
    DateTime _selectedDate = DateTime.now();
    TextEditingController _reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${groupTime} の休講日設定'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 日付選択
            StatefulBuilder(
              builder: (BuildContext context, StateSetter setState) {
                return Row(
                  children: [
                    const Text('休講日: '),
                    Text(DateFormat('yyyy/MM/dd').format(_selectedDate), style: const TextStyle(fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.edit_calendar),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _selectedDate,
                          firstDate: DateTime.now(),
                          lastDate: DateTime(2030),
                        );
                        if (picked != null) {
                          setState(() => _selectedDate = picked);
                        }
                      },
                    ),
                  ],
                );
              },
            ),
            // 理由
            TextField(
              controller: _reasonController,
              decoration: const InputDecoration(labelText: '理由 (例: 講師都合、会場変更)'),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              // Firestoreに例外として追加
              FirebaseFirestore.instance
                  .collection('classExceptions') 
                  .add({
                'levelId': levelId, // ここを levelId に修正
                'date': _selectedDate, 
                'reason': _reasonController.text.trim().isNotEmpty ? _reasonController.text.trim() : '休講',
                'createdAt': FieldValue.serverTimestamp(),
              });
              Navigator.pop(context);
            },
            child: const Text('設定'),
          ),
        ],
      ),
    );
  }
}