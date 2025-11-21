// lib/screens/admin/course_exception_selector_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:atoz_school_app/models/class_model.dart'; 
import 'level_exception_selector_screen.dart';

class CourseExceptionSelectorScreen extends StatelessWidget {
  final String subjectId;
  final String subjectName;

  const CourseExceptionSelectorScreen({
    super.key,
    required this.subjectId,
    required this.subjectName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${subjectName}：コースを選択'),
        backgroundColor: Colors.red.shade700,
      ),
      // Subject IDをフィルタしてコースを取得
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('courses')
            .where('subjectId', isEqualTo: subjectId)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
             return Center(child: Text('${subjectName} には登録されたコースがありません。'));
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
                subtitle: const Text('タップしてレベルを選択'),
                onTap: () {
                  // 修正後: レベル選択画面へ移動
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => LevelExceptionSelectorScreen(
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
    );
  }
}