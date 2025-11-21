import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:atoz_school_app/models/class_model.dart'; 
// ▼ コース一覧画面へのインポートを追加
import 'course_list_screen.dart'; 

class SubjectListScreen extends StatelessWidget {
  const SubjectListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('マスタ管理：科目一覧'),
        backgroundColor: Colors.blueGrey,
      ),
      // ■ Firestoreのデータをリアルタイム表示
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('subjects').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return const Center(child: Text('エラーが発生しました'));

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(child: Text('科目がありません。\n右下のボタンから追加してください。'));
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              
              final subject = Subject(
                id: docs[index].id,
                name: data['name'] ?? '名称未設定',
              );

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  leading: const Icon(Icons.category, color: Colors.blue),
                  title: Text(
                    subject.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.grey),
                    onPressed: () => _deleteSubject(context, subject.id),
                  ),
                  onTap: () {
                    // 正しいナビゲーションロジック
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CourseListScreen( // ← CourseListScreen に移動
                          subjectId: subject.id,
                          subjectName: subject.name,
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
        onPressed: () => _showAddDialog(context),
      ),
    );
  }

  // ■ 科目追加ダイアログ (ロジックは変更なし)
  void _showAddDialog(BuildContext context) {
    final TextEditingController controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新しい科目を追加'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: '例：英語、プログラミング'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                await FirebaseFirestore.instance.collection('subjects').add({
                  'name': name,
                });
                Navigator.pop(context);
              }
            },
            child: const Text('追加'),
          ),
        ],
      ),
    );
  }

  // ■ 削除処理 (ロジックは変更なし)
  void _deleteSubject(BuildContext context, String docId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('科目を削除'),
        content: const Text('この科目を削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () async {
              await FirebaseFirestore.instance.collection('subjects').doc(docId).delete();
              Navigator.pop(context);
            },
            child: const Text('削除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}