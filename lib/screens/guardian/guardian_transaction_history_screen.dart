import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../models/student_model.dart';
import '../../models/lesson_transaction_model.dart';

class GuardianTransactionHistoryScreen extends StatefulWidget {
  const GuardianTransactionHistoryScreen({Key? key}) : super(key: key);

  @override
  _GuardianTransactionHistoryScreenState createState() => _GuardianTransactionHistoryScreenState();
}

class _GuardianTransactionHistoryScreenState extends State<GuardianTransactionHistoryScreen> {
  DateTime _currentMonth = DateTime.now();
  List<Student> _myChildren = [];
  Map<String, String> _studentNames = {}; 
  bool _isLoading = true;

  // ★フィルター用変数
  String? _selectedStudentId; // 選択中の子供 (nullなら全員)
  String? _selectedClassName; // 選択中のクラス名 (nullなら全クラス)
  Set<String> _availableClassNames = {}; // 履歴にあるクラス名のリスト

  @override
  void initState() {
    super.initState();
    _fetchMyData();
  }

  Future<void> _fetchMyData() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('students')
          .where('parentId', isEqualTo: uid)
          .get();
      
      final children = snapshot.docs.map((doc) => Student.fromMap(doc.data(), doc.id)).toList();
      final Map<String, String> names = {};
      
      for (var child in children) {
        names[child.id] = child.firstName;
      }

      if (mounted) {
        setState(() {
          _myChildren = children;
          _studentNames = names;
          // 子供が1人だけなら最初から選択しておく
          if (children.length == 1) {
            _selectedStudentId = children.first.id;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _changeMonth(int offset) {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + offset, 1);
      // 月を変えたらクラスフィルターはリセットするのが自然
      _selectedClassName = null;
      _availableClassNames.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_myChildren.isEmpty) return const Scaffold(body: Center(child: Text('生徒データがありません')));

    final studentIds = _myChildren.map((s) => s.id).toList();
    final startOfMonth = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final endOfMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 0, 23, 59, 59);

    return Scaffold(
      appBar: AppBar(
        title: const Text('チケット履歴'),
        backgroundColor: Colors.blue.shade700,
      ),
      body: Column(
        children: [
          // 月選択
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.grey[100],
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _changeMonth(-1)),
                Text(DateFormat('yyyy年 M月').format(_currentMonth), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _changeMonth(1)),
              ],
            ),
          ),
          
          // ★フィルターエリア
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            color: Colors.white,
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. 子供フィルター (兄弟がいる場合のみ便利)
                if (_myChildren.length > 1) ...[
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        const Text('生徒: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: ChoiceChip(
                            label: const Text('全員'),
                            selected: _selectedStudentId == null,
                            onSelected: (val) => setState(() => _selectedStudentId = null),
                          ),
                        ),
                        ..._myChildren.map((child) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: ChoiceChip(
                              label: Text(child.firstName),
                              selected: _selectedStudentId == child.id,
                              onSelected: (val) => setState(() => _selectedStudentId = val ? child.id : null),
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                ],

                // 2. クラスフィルター (履歴にクラス名が含まれている場合のみ表示)
                if (_availableClassNames.isNotEmpty)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        const Text('クラス: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: FilterChip(
                            label: const Text('すべて'),
                            selected: _selectedClassName == null,
                            onSelected: (val) => setState(() => _selectedClassName = null),
                          ),
                        ),
                        ..._availableClassNames.map((clsName) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: FilterChip(
                              label: Text(clsName),
                              selected: _selectedClassName == clsName,
                              onSelected: (val) => setState(() => _selectedClassName = val ? clsName : null),
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),

          // リスト
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('lessonTransactions')
                  .where('studentId', whereIn: studentIds)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('履歴はありません'));
                }

                // 全データを取得後にフィルタリングとソート
                final allDocs = snapshot.data!.docs.map((doc) {
                  return LessonTransaction.fromMap(doc.data() as Map<String, dynamic>, doc.id);
                }).toList();

                // フィルター適用
                final filteredDocs = allDocs.where((history) {
                  // 月フィルター
                  if (history.createdAt.isBefore(startOfMonth) || history.createdAt.isAfter(endOfMonth)) return false;
                  // 生徒フィルター
                  if (_selectedStudentId != null && history.studentId != _selectedStudentId) return false;
                  // クラスフィルター
                  if (_selectedClassName != null && history.className != _selectedClassName) return false;
                  return true;
                }).toList();

                // 利用可能なクラス名を更新 (今月の全履歴から抽出)
                // ※ビルド完了後にsetStateするためにaddPostFrameCallbackを使用
                final classNamesInMonth = allDocs
                    .where((h) => h.createdAt.isAfter(startOfMonth) && h.createdAt.isBefore(endOfMonth))
                    .map((h) => h.className) // classNameが入っているものだけ
                    .where((name) => name != null && name.isNotEmpty)
                    .map((name) => name!)
                    .toSet();
                
                if (mounted && _availableClassNames.length != classNamesInMonth.length) {
                   // リストの内容が変わった時だけ更新（無限ループ防止）
                   WidgetsBinding.instance.addPostFrameCallback((_) {
                     if (mounted) setState(() => _availableClassNames = classNamesInMonth);
                   });
                }

                // ソート
                filteredDocs.sort((a, b) => b.createdAt.compareTo(a.createdAt));

                if (filteredDocs.isEmpty) {
                  return const Center(child: Text('条件に一致する履歴はありません'));
                }

                return ListView.separated(
                  itemCount: filteredDocs.length,
                  separatorBuilder: (ctx, i) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    return _buildHistoryTile(filteredDocs[index]);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTile(LessonTransaction history) {
    IconData icon;
    Color color;
    String title;
    
    if (history.type == 'purchase') {
      icon = Icons.add_circle_outline;
      color = Colors.green;
      title = 'チケット購入';
    } else if (history.type == 'use') {
      icon = Icons.confirmation_number_outlined;
      color = Colors.orange;
      title = 'レッスン予約';
    } else if (history.type == 'cancel_refund') {
      icon = Icons.undo;
      color = Colors.blue;
      title = 'キャンセル返還';
    } else {
      icon = Icons.info_outline;
      color = Colors.grey;
      title = '残高調整';
    }

    final amountText = history.amount > 0 ? '+${history.amount}' : '${history.amount}';
    final amountColor = history.amount > 0 ? Colors.green[800] : Colors.red[800];
    final studentName = _studentNames[history.studentId] ?? '';
    final className = history.className ?? '';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.1),
        child: Icon(icon, color: color),
      ),
      title: Text('$title ($studentName)', style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(
        '${DateFormat('M/d HH:mm').format(history.createdAt)}' + (className.isNotEmpty ? '\n$className' : ''),
        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
      ),
      trailing: Text(
        '$amountText 枚',
        style: TextStyle(color: amountColor, fontSize: 18, fontWeight: FontWeight.bold),
      ),
      isThreeLine: className.isNotEmpty, 
    );
  }
}