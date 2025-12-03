import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../models/class_model.dart'; 
import '../data_entry/class_group_form_screen.dart'; 

class ClassGroupListScreen extends StatelessWidget {
  final String subjectId; 
  final String subjectName; 
  final String courseId; 
  final String courseName; 
  final String levelId;
  final String levelName;

  const ClassGroupListScreen({
    super.key,
    required this.subjectId,
    required this.subjectName,
    required this.courseId,
    required this.courseName,
    required this.levelId,
    required this.levelName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('$levelName：枠の設定'),
        backgroundColor: Colors.brown,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('classGroups') // 新しいコレクション
            .where('levelId', isEqualTo: levelId) 
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return Center(child: Text('エラー: ${snapshot.error}'));

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
             return Center(child: Text('$levelName にはまだ曜日・時間の枠がありません。\n右下のボタンから追加してください。', textAlign: TextAlign.center));
          }
          
          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final group = ClassGroup.fromMap(data, docs[index].id);

              String periodText = '';
              if (group.validFrom != null || group.validTo != null) {
                final from = group.validFrom != null ? DateFormat('yyyy/MM/dd').format(group.validFrom!) : '∞';
                final to = group.validTo != null ? DateFormat('yyyy/MM/dd').format(group.validTo!) : '∞';
                periodText = '\n有効期間: $from 〜 $to';
              }

              final typeText = group.bookingType == 'flexible' ? ' [予約制]' : ' [固定制]';

              // ★修正: 曜日を漢字に変換 (マップを使用)
              String dayStr = group.dayOfWeek.toString();
              const days = {'1': '月', '2': '火', '3': '水', '4': '木', '5': '金', '6': '土', '7': '日'};
              if (days.containsKey(dayStr)) {
                dayStr = days[dayStr]!;
              }

              return Card(
                child: ListTile(
                  // 漢字の曜日を表示
                  title: Text('$dayStr ${group.startTime}（${group.teacherName}先生）$typeText'),
                  subtitle: Text('定員: ${group.capacity}名$periodText'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.grey),
                    onPressed: () => _confirmDelete(context, group.id),
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ClassGroupFormScreen(
                          classGroup: group, 
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ClassGroupFormScreen(
                subjectId: subjectId,
                courseId: courseId,
                levelId: levelId,
              ),
            ),
          );
        },
      ),
    );
  }

  void _confirmDelete(BuildContext context, String groupId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('削除確認'),
        content: const Text('このクラス枠を削除しますか？\n（過去のレッスンデータは残ります）'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () async {
              await FirebaseFirestore.instance.collection('classGroups').doc(groupId).delete();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('削除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}