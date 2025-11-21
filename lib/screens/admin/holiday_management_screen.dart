import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart'; 
import 'class_exception_selector_screen.dart'; // TODO: クラス別設定時に使う

class HolidayManagementScreen extends StatelessWidget {
  const HolidayManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // 共通の休日 (holidays) コレクションを参照
    return Scaffold(
      appBar: AppBar(
        title: const Text('休日・休講マスタ'),
        backgroundColor: Colors.red.shade800,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
                // ▼▼▼ 追加する新しいボタン ▼▼▼
          Padding(
            padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 10.0),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.class_, size: 18),
              label: const Text('クラス別休講日の設定へ'),
              onPressed: () {
                // クラス選択画面へ遷移
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => ClassExceptionSelectorScreen()));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade100,
                foregroundColor: Colors.red.shade900,
              ),
            ),
          ),
          // ▲▲▲ 追加ここまで ▲▲▲
          // ヘッダー説明
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              '学校全体の休業日を設定します。ここに登録された日は、全てのレッスンが自動的に休講となります。',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
            ),
          ),
          
          // 共通休日リスト (holidaysコレクション)
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('holidays').orderBy('date').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                
                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return const Center(child: Text('共通の休日は登録されていません。'));
                }

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final date = (data['date'] as Timestamp).toDate();
                    final reason = data['reason'] ?? '休講';

                    return ListTile(
                      leading: const Icon(Icons.event_busy, color: Colors.red),
                      title: Text(DateFormat('yyyy年M月d日 (E)').format(date)),
                      subtitle: Text(reason),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_forever),
                        onPressed: () {
                          // 削除ロジック
                          FirebaseFirestore.instance.collection('holidays').doc(docs[index].id).delete();
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () => _showAddDialog(context),
      ),
    );
  }

  // ■ 休日追加ダイアログ
  void _showAddDialog(BuildContext context) {
    DateTime _selectedDate = DateTime.now();
    TextEditingController _reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('共通休日の追加'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 日付選択
            StatefulBuilder(
              builder: (BuildContext context, StateSetter setState) {
                return Row(
                  children: [
                    const Text('日付: '),
                    Text(DateFormat('yyyy/MM/dd').format(_selectedDate), style: const TextStyle(fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.edit_calendar),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _selectedDate,
                          firstDate: DateTime(2025),
                          lastDate: DateTime(2030),
                        );
                        if (picked != null) {
                          setState(() => _selectedDate = picked);
                        }
                      },
                    ),
                  ],
                );
              },
            ),
            // 理由
            TextField(
              controller: _reasonController,
              decoration: const InputDecoration(labelText: '理由 (例: お盆休み、年末年始)'),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              // Firestoreに追加
              FirebaseFirestore.instance.collection('holidays').add({
                'date': _selectedDate, // Timestampとして保存
                'reason': _reasonController.text.trim().isNotEmpty ? _reasonController.text.trim() : '休講',
              });
              Navigator.pop(context);
            },
            child: const Text('追加'),
          ),
        ],
      ),
    );
  }
}