import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../models/student_model.dart';
import '../../models/lesson_transaction_model.dart';

class AdminTransactionHistoryScreen extends StatefulWidget {
  const AdminTransactionHistoryScreen({Key? key}) : super(key: key);

  @override
  _AdminTransactionHistoryScreenState createState() => _AdminTransactionHistoryScreenState();
}

class _AdminTransactionHistoryScreenState extends State<AdminTransactionHistoryScreen> {
  DateTime _currentMonth = DateTime.now();
  bool _showGrantsOnly = false; // フィルター状態
  Map<String, String> _studentNames = {}; // ID -> 名前 のキャッシュ
  bool _isLoadingStudents = true;

  @override
  void initState() {
    super.initState();
    _fetchStudentNames();
  }

  // 生徒IDから名前を引けるように一覧を取得しておく
  Future<void> _fetchStudentNames() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('students').get();
      final Map<String, String> names = {};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final lastName = data['lastName'] ?? '';
        final firstName = data['firstName'] ?? '';
        names[doc.id] = '$lastName $firstName';
      }
      if (mounted) {
        setState(() {
          _studentNames = names;
          _isLoadingStudents = false;
        });
      }
    } catch (e) {
      print('Error fetching students: $e');
      if (mounted) setState(() => _isLoadingStudents = false);
    }
  }

  // 月の切り替え
  void _changeMonth(int offset) {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + offset, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    // 月の初めと終わりを計算
    final startOfMonth = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final endOfMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 0, 23, 59, 59);

    return Scaffold(
      appBar: AppBar(
        title: const Text('チケット受払履歴'),
        backgroundColor: Colors.indigo,
      ),
      body: Column(
        children: [
          // --- 1. ヘッダー (月選択 & フィルター) ---
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.grey[100],
            child: Column(
              children: [
                // 月選択
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => _changeMonth(-1),
                    ),
                    Text(
                      DateFormat('yyyy年 M月').format(_currentMonth),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => _changeMonth(1),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // フィルター切り替え
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FilterChip(
                      label: const Text('すべて'),
                      selected: !_showGrantsOnly,
                      onSelected: (val) => setState(() => _showGrantsOnly = !val),
                      checkmarkColor: Colors.white,
                      selectedColor: Colors.indigo.shade100,
                    ),
                    const SizedBox(width: 12),
                    FilterChip(
                      label: const Text('発行のみ (入金)'),
                      selected: _showGrantsOnly,
                      onSelected: (val) => setState(() => _showGrantsOnly = val),
                      checkmarkColor: Colors.white,
                      selectedColor: Colors.green.shade100,
                      avatar: const Icon(Icons.add_circle, color: Colors.green, size: 18),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // --- 2. リスト表示 ---
          Expanded(
            child: _isLoadingStudents
                ? const Center(child: CircularProgressIndicator())
                : StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('lessonTransactions')
                        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
                        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endOfMonth))
                        .orderBy('createdAt', descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return const Center(child: Text('履歴はありません'));
                      }

                      // クライアント側でフィルター
                      final docs = snapshot.data!.docs.where((doc) {
                        if (!_showGrantsOnly) return true; // 「すべて」なら全部出す
                        
                        final data = doc.data() as Map<String, dynamic>;
                        final type = data['type'] ?? '';
                        final amount = data['amount'] as int? ?? 0;

                        // ★修正: プラスの変動であっても、「キャンセル返還」は除外する
                        // 「購入(purchase)」または「管理者補填(correctionでプラス)」のみを表示
                        return amount > 0 && type != 'cancel_refund';
                      }).toList();

                      if (docs.isEmpty) {
                        return const Center(child: Text('条件に一致する履歴はありません'));
                      }

                      return ListView.separated(
                        itemCount: docs.length,
                        separatorBuilder: (ctx, i) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final data = docs[index].data() as Map<String, dynamic>;
                          final history = LessonTransaction.fromMap(data, docs[index].id);
                          final studentName = _studentNames[history.studentId] ?? '不明な生徒 (${history.studentId})';
                          
                          return _buildHistoryTile(history, studentName);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTile(LessonTransaction history, String studentName) {
    // タイプに応じたアイコンと色
    IconData icon;
    Color color;
    String typeText;
    
    if (history.type == 'purchase') {
      icon = Icons.add_circle;
      color = Colors.green;
      typeText = '購入/付与';
    } else if (history.type == 'use') {
      icon = Icons.remove_circle;
      color = Colors.orange;
      typeText = '予約利用';
    } else if (history.type == 'cancel_refund') {
      icon = Icons.undo;
      color = Colors.blue;
      typeText = 'キャンセル返還';
    } else {
      icon = Icons.info;
      color = Colors.grey;
      typeText = '修正/その他';
    }

    // 枚数の表示 (+5, -1)
    final amountText = history.amount > 0 ? '+${history.amount}' : '${history.amount}';
    final amountColor = history.amount > 0 ? Colors.green[800] : Colors.red[800];

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.1),
        child: Icon(icon, color: color),
      ),
      title: Text(studentName, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(
        '${DateFormat('MM/dd HH:mm').format(history.createdAt)} · $typeText\n${history.note ?? ""}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        '$amountText 枚',
        style: TextStyle(color: amountColor, fontSize: 18, fontWeight: FontWeight.bold),
      ),
      isThreeLine: true,
    );
  }
}