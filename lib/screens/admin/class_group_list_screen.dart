import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:atoz_school_app/models/class_model.dart'; 
// フォーム画面への相対パス
import '../data_entry/class_group_form_screen.dart'; 

class ClassGroupListScreen extends StatelessWidget {
  // ▼ 全ての親IDを受け取る
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
        title: Text('${levelName}：枠の設定'),
        backgroundColor: Colors.brown,
      ),
      // FirestoreからLevel IDをフィルタして枠を取得
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('groups') 
            // ▼ Level IDでフィルタリング (インデックスが機能する部分)
            .where('levelId', isEqualTo: levelId) 
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return Center(child: Text('エラー: ${snapshot.error}'));

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
             return Center(child: Text('${levelName} にはまだ曜日・時間の枠がありません。右下のボタンから追加してください。'));
          }
          
          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              // ClassGroup モデルを使ってデータを構築 (ここでは簡易表示)
              final group = ClassGroup( 
                id: docs[index].id,
                levelId: levelId,
                teacherName: data['teacherName'] ?? '未設定',
                dayOfWeek: data['dayOfWeek'] ?? '不明',
                startTime: data['startTime'] ?? '00:00',
                durationMinutes: data['durationMinutes'] ?? 0,
                capacity: data['capacity'] ?? 0,
                bookingType: data['bookingType'] ?? 'fixed',
                // ▼ モデルのコンストラクタに追加されたIDも渡す必要があります (暫定値)
                subjectId: data['subjectId'] ?? subjectId,
                courseId: data['courseId'] ?? courseId,
              );

              return ListTile(
                title: Text('${group.dayOfWeek} ${group.startTime}（${group.teacherName}先生）'),
                subtitle: Text('定員: ${group.capacity}名 / ${group.bookingType == 'fixed' ? '固定制' : '都度予約'}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () => FirebaseFirestore.instance.collection('groups').doc(group.id).delete(),
                ),
                onTap: () {
                  // TODO: 編集画面へ移動
                },
              );
            },
          );
        },
      ),
      // フォーム画面への遷移ロジック
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ClassGroupFormScreen(
                // ▼ フォームに全階層IDを渡す
                subjectId: subjectId,
                courseId: courseId,
                levelId: levelId,
                levelName: levelName,
              ),
            ),
          );
        },
      ),
    );
  }
}