import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:atoz_school_app/models/class_model.dart';
import 'class_level_list_screen.dart'; // ← これが正しく読み込まれているか重要

class CourseListScreen extends StatelessWidget {
  final String subjectId;
  final String subjectName;
  const CourseListScreen({
    super.key,
    required this.subjectId,
    required this.subjectName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${subjectName}：コース登録'),
        backgroundColor: Colors.teal,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('courses')
            .where('subjectId', isEqualTo: subjectId)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
             return Center(child: Text('${subjectName} にはまだコースがありません。'));
          }
          
          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final course = Course(
                id: docs[index].id,
                subjectId: subjectId,
                name: data['name'] ?? '名称未設定',
              );

              return ListTile(
                title: Text(course.name),
                subtitle: Text('ID: ${course.id}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () => FirebaseFirestore.instance.collection('courses').doc(course.id).delete(),
                ),
                onTap: () {
                  // ▼▼▼ ナビゲーションロジック (ここが正しいコード) ▼▼▼
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ClassLevelListScreen(
                        subjectId: subjectId, 
                        subjectName: subjectName,
                        courseId: course.id,
                        courseName: course.name,
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
  
  // (_showAddDialog 関数は省略 - 中身は正しいと仮定)
  void _showAddDialog(BuildContext context) {
    final TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新しいコースを追加'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: '例：こども英会話'),
        ),
        actions: [
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                await FirebaseFirestore.instance.collection('courses').add({
                  'name': name,
                  'subjectId': subjectId,
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