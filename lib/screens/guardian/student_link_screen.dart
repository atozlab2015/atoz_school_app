import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:atoz_school_app/models/student_model.dart';

class StudentLinkScreen extends StatefulWidget {
  const StudentLinkScreen({super.key});

  @override
  State<StudentLinkScreen> createState() => _StudentLinkScreenState();
}

class _StudentLinkScreenState extends State<StudentLinkScreen> {
  final _formKey = GlobalKey<FormState>();
  String _inputStudentId = '';
  bool _isLoading = false;

  // IDを検証して紐付ける処理
  Future<void> _linkStudent() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    setState(() => _isLoading = true);

    try {
      // 1. 入力されたIDの生徒が存在するか確認
      final studentDoc = await FirebaseFirestore.instance
          .collection('students')
          .doc(_inputStudentId)
          .get();

      if (!studentDoc.exists) {
        throw Exception('入力されたIDの生徒が見つかりません。IDを確認してください。');
      }

      final studentData = Student.fromMap(studentDoc.data()!, studentDoc.id);

      // 2. 生徒名を表示して確認ダイアログを出す
      if (!mounted) return;
      final shouldLink = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('生徒情報の確認'),
          content: Text('お子様のお名前は\n「${studentData.fullName}」\nさんですか？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('いいえ'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('はい'),
            ),
          ],
        ),
      );

      if (shouldLink != true) {
        setState(() => _isLoading = false);
        return;
      }

      // 3. 保護者ユーザー(users)に studentId を書き込む
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'studentId': _inputStudentId,
      });
      
      // 4. 生徒データ(students)に parentId を書き込む (双方向リンク)
      await FirebaseFirestore.instance.collection('students').doc(_inputStudentId).update({
        'parentId': uid,
      });

      // 完了メッセージ (RoleBasedRouterが自動で画面を切り替えるため、遷移処理は不要)
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('紐付けが完了しました！')),
        );
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('生徒IDの入力'), backgroundColor: Colors.blue),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.badge, size: 80, color: Colors.blue),
            const SizedBox(height: 20),
            const Text(
              'スクールから配布された\n「生徒ID」を入力してください',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 30),
            
            Form(
              key: _formKey,
              child: TextFormField(
                decoration: const InputDecoration(
                  labelText: '生徒ID',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.vpn_key),
                ),
                onSaved: (val) => _inputStudentId = val?.trim() ?? '',
                validator: (val) => (val == null || val.isEmpty) ? 'IDを入力してください' : null,
              ),
            ),
            const SizedBox(height: 30),
            
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _linkStudent,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                child: _isLoading 
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('確認して紐付ける', style: TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '※IDが分からない場合は、管理者にお問い合わせください。',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}