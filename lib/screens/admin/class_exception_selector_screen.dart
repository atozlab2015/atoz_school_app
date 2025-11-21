// lib/screens/admin/class_exception_selector_screen.dart を以下で上書き

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:atoz_school_app/models/class_model.dart';
import 'course_exception_selector_screen.dart'; // TODO: 次の画面 (これから作成)

class ClassExceptionSelectorScreen extends StatelessWidget {
  const ClassExceptionSelectorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('科目を選択してください'),
        backgroundColor: Colors.red.shade700,
      ),
      // Firestoreの 'subjects' コレクションからデータを取得
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('subjects').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return const Center(child: Text('エラーが発生しました'));

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text('登録済みの科目がありません。マスタ設定から追加してください。'));
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
                  title: Text(subject.name),
                  onTap: () {
                    // 次の画面 (コース選択) へ Subject ID と名前を渡して移動
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CourseExceptionSelectorScreen(
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
    );
  }
}