// lib/screens/mock_login_screen.dart

import 'package:flutter/material.dart';
import 'admin/admin_dashboard_screen.dart'; // Admin画面のパスを修正
import 'guardian/guardian_home_screen.dart'; // Guardian画面のパスを修正

class MockLoginScreen extends StatelessWidget {
  const MockLoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ログインとロール選択'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'テスト用ログイン：ロールを選択してください',
              style: TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 30),
            
            // 1. 管理者としてログイン
            ElevatedButton.icon(
              icon: const Icon(Icons.admin_panel_settings),
              label: const Text('管理者としてログイン (Admin)'),
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const AdminDashboardScreen(),
                ));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
              ),
            ),
            const SizedBox(height: 20),

            // 2. 保護者としてログイン
            ElevatedButton.icon(
              icon: const Icon(Icons.family_restroom),
              label: const Text('保護者としてログイン (Guardian)'),
              onPressed: () {
                // 仮のStudent IDを使って保護者ホームへ遷移
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const GuardianHomeScreen(), // 引数を削除
              ));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}