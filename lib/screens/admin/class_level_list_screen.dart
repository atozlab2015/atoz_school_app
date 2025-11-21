import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:atoz_school_app/models/class_model.dart'; 
import 'class_group_list_screen.dart';

class ClassLevelListScreen extends StatelessWidget {
  final String subjectId;   // ★追加 (親から受け取る)
  final String subjectName; // ★追加 (親から受け取る)
  final String courseId;
  final String courseName;

  const ClassLevelListScreen({
    super.key,
    required this.subjectId,   // ★必須引数に追加
    required this.subjectName, // ★必須引数に追加
    required this.courseId,
    required this.courseName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${courseName}：レベル登録'),
        backgroundColor: Colors.indigo,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('levels')
            .where('courseId', isEqualTo: courseId)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
             return Center(child: Text('${courseName} にはまだレベルがありません。'));
          }
          
          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final level = ClassLevel(
                id: docs[index].id,
                courseId: courseId,
                name: data['name'] ?? '名称未設定',
              );

              return ListTile(
                title: Text(level.name),
                onTap: () {
                  // ClassGroupListScreen へ 全ての親IDを渡す
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ClassGroupListScreen(
                        subjectId: subjectId,     // ★修正後に追加
                        subjectName: subjectName, // ★修正後に追加
                        courseId: courseId,
                        courseName: courseName,
                        levelId: level.id,
                        levelName: level.name,
                      ),
                    ),
                  );
                },
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
  
  // レベル追加ダイアログ (ロジックは省略)
  void _showAddDialog(BuildContext context) {
    final TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新しいレベルを追加'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: '例：Starter, Basic'),
        ),
        actions: [
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                await FirebaseFirestore.instance.collection('levels').add({
                  'name': name,
                  'courseId': courseId, 
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
}