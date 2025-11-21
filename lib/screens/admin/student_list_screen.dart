import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// モデルと編集画面をインポート
import 'package:atoz_school_app/models/student_model.dart';
import 'student_edit_screen.dart'; 

class StudentListScreen extends StatelessWidget {
  const StudentListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('生徒管理（編集・検索）'),
        backgroundColor: Colors.orange,
      ),
      body: StreamBuilder<QuerySnapshot>(
        // 姓（lastName）順に並べて表示
        stream: FirebaseFirestore.instance.collection('students').orderBy('lastName').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('登録されている生徒がいません。'));
          }
          
          final docs = snapshot.data!.docs;
          
          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              // Firestoreデータをモデルに変換
              final student = Student.fromMap(data, docs[index].id);

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text('${student.fullName} (${student.fullNameRomaji})'),
                  subtitle: Text('受講クラス数: ${student.enrollments.length}'),
                  trailing: const Icon(Icons.edit, color: Colors.grey),
                  onTap: () {
                    // 編集画面へ遷移
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => StudentEditScreen(student: student),
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