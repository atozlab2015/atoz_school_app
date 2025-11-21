import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ▼ Adminメニューで使う全画面をインポート
import 'subject_list_screen.dart';
import 'calendar_generation_screen.dart';
import 'holiday_management_screen.dart';
import 'approval_dashboard_screen.dart';
import 'student_registration_screen.dart';
import 'student_list_screen.dart'; // ★追加: 生徒一覧・編集

// AdminDashboardScreen: 管理者が操作するホーム画面です
class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('管理者ダッシュボード'),
        backgroundColor: Colors.indigo,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView( // ボタンが増えたのでスクロール可能に
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('管理者メニューへようこそ。', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 30),
              
              // 1. マスタ管理
              _buildMenuButton(
                context,
                icon: Icons.category,
                label: '1. クラス・マスタ設定',
                destination: const SubjectListScreen(),
              ),
              
              // 2. カレンダー生成
              _buildMenuButton(
                context,
                icon: Icons.calendar_month,
                label: '2. 年間カレンダー生成',
                destination: const CalendarGenerationScreen(),
              ),
              
              // 3. 休日・休講設定
              _buildMenuButton(
                context,
                icon: Icons.event_busy,
                label: '3. 休日・休講設定',
                destination: const HolidayManagementScreen(),
              ),

              // 4. 振替予約の承認
              _buildMenuButton(
                context,
                icon: Icons.check_circle_outline,
                label: '4. 振替予約の承認',
                destination: const ApprovalDashboardScreen(),
              ),

              const Divider(height: 40), // 区切り線

              // 5. 生徒の新規登録
              _buildMenuButton(
                context,
                icon: Icons.person_add,
                label: '5. 生徒の新規登録',
                destination: const StudentRegistrationScreen(),
                color: Colors.teal,
              ),

              // 6. 生徒情報の編集・検索 (★新規追加)
              _buildMenuButton(
                context,
                icon: Icons.manage_accounts,
                label: '6. 生徒情報の編集・検索',
                destination: const StudentListScreen(),
                color: Colors.orange,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ボタン作成用ヘルパー関数 (コードをスッキリさせるため)
  Widget _buildMenuButton(BuildContext context, {required IconData icon, required String label, required Widget destination, Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: ElevatedButton.icon(
        icon: Icon(icon),
        label: Text(label, style: const TextStyle(fontSize: 18)),
        onPressed: () {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => destination));
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: color, // 指定がなければテーマカラー
          minimumSize: const Size(double.infinity, 50), // 幅いっぱい
        ),
      ),
    );
  }
}