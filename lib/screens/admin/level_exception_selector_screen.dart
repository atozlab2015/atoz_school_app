// lib/screens/admin/level_exception_selector_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:atoz_school_app/models/class_model.dart'; 
import 'class_group_exception_screen.dart'; // 最終画面へ

class LevelExceptionSelectorScreen extends StatelessWidget {
  final String subjectId;
  final String subjectName;
  final String courseId;
  final String courseName;

  const LevelExceptionSelectorScreen({
    super.key,
    required this.subjectId,
    required this.subjectName,
    required this.courseId,
    required this.courseName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${subjectName} / ${courseName}：レベルを選択'),
        backgroundColor: Colors.red.shade700,
      ),
      // Course IDをフィルタしてレベルを取得
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('levels')
            .where('courseId', isEqualTo: courseId)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
             return Center(child: Text('${courseName} には登録されたレベルがありません。'));
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
                subtitle: const Text('タップしてクラス枠を選択'),
                onTap: () {
                  // 最終画面 (クラス枠選択) へ移動
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ClassGroupExceptionScreen(
                        subjectName: subjectName,
                        courseName: courseName,
                        levelName: level.name,
                        subjectId: subjectId,
                        courseId: courseId,
                        levelId: level.id,
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