import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
// ▼ モデルと画面をインポート
import '../models/user_model.dart'; 
import 'admin/admin_dashboard_screen.dart';       // Admin画面
import 'teacher/teacher_schedule_screen.dart';     // 講師画面
import 'guardian/guardian_home_screen.dart';       // 保護者画面
import 'guardian/student_link_screen.dart';

class RoleBasedRouter extends StatelessWidget {
  const RoleBasedRouter({super.key});

  @override
  Widget build(BuildContext context) {
    // 1. 現在のログインユーザーIDを取得
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Center(child: Text('認証エラー：ユーザーIDが見つかりません'));

    // 2. Firestoreのusersコレクションから、現在のユーザーのroleを監視
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snapshot) {
        // 接続待機中 (初回データ取得時)
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        
        // ユーザーデータが存在しない場合
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Scaffold(body: Center(child: Text('ユーザー情報がありません。管理者にご連絡ください。')));
        }

        // 3. ユーザーデータから役割(role)を取得
        final userData = snapshot.data!.data() as Map<String, dynamic>;
        final userRole = userData['role'] as String? ?? 'parent'; // roleがない場合は保護者と見なす
        
        // ★保護者としてログインした場合に使う Student IDを取得（未登録なら仮ID）
        final studentId = userData['studentId'] as String? ?? 'STUDENT_001'; 


        // 4. 役割に基づいて画面を切り替える
        switch (userRole) {
          case 'admin':
            // Admin: 管理者ダッシュボードへ
            return const AdminDashboardScreen(); 
          case 'teacher':
            // Teacher: 講師専用スケジュールへ
            return const TeacherScheduleScreen();
          case 'parent':
          default:
            // ★修正: 特定のIDを渡さず、親としてホーム画面を開く
            return const GuardianHomeScreen();
            
            // ★修正点: studentId があればホームへ、なければ紐付け画面へ
            if (studentId != null && studentId.isNotEmpty) {
              return const GuardianHomeScreen(); // 引数を削除し、constを付ける
            } else {
              return const StudentLinkScreen();
            }
        }
      },
    );
  }
}