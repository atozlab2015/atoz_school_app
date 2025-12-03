import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../models/student_model.dart';
import '../../models/lesson_transaction_model.dart';
import '../../models/ticket_stock_model.dart';
import '../../models/class_model.dart';

class AdminTicketGrantScreen extends StatefulWidget {
  const AdminTicketGrantScreen({Key? key}) : super(key: key);

  @override
  _AdminTicketGrantScreenState createState() => _AdminTicketGrantScreenState();
}

class _AdminTicketGrantScreenState extends State<AdminTicketGrantScreen> {
  final _searchController = TextEditingController();
  List<Student> _searchResults = [];
  bool _isSearching = false;
  Student? _selectedStudent;

  final _formKey = GlobalKey<FormState>();
  int _amountToAdd = 0;
  DateTime _expiryDate = DateTime.now().add(const Duration(days: 180));
  String _adminNote = '';
  
  List<Map<String, dynamic>> _levelOptions = []; 
  String? _selectedLevelId;
  String? _selectedLevelName;

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _fetchLevelOptions();
  }

  Future<void> _fetchLevelOptions() async {
    try {
      final firestore = FirebaseFirestore.instance;
      final Map<String, String> courseNames = {};
      final Map<String, String> levelNames = {};
      
      final cSnap = await firestore.collection('courses').get();
      for (var d in cSnap.docs) courseNames[d.id] = d.data()['name'] ?? '';
      
      final lSnap = await firestore.collection('levels').get();
      for (var d in lSnap.docs) levelNames[d.id] = d.data()['name'] ?? '';

      // classGroupsのみ取得（groupsは削除済みのため除外）
      final classGroupsSnap = await firestore.collection('classGroups').get();

      // ★重複排除用のMap (key: levelId)
      final Map<String, String> uniqueLevels = {}; 

      for (var doc in classGroupsSnap.docs) {
        final g = ClassGroup.fromMap(doc.data() as Map<String, dynamic>, doc.id);
        
        // 予約制(flexible)のみ対象
        if (g.bookingType == 'flexible' && g.levelId.isNotEmpty) {
          final courseName = courseNames[g.courseId] ?? '不明';
          final levelName = levelNames[g.levelId] ?? g.levelId;
          
          // 表示名: "おやこ英会話 / 初級"
          uniqueLevels[g.levelId] = '$courseName / $levelName';
        }
      }

      final List<Map<String, dynamic>> list = uniqueLevels.entries.map((e) {
        return {
          'id': e.key,      // levelId
          'label': e.value, // 表示名
        };
      }).toList();
      
      list.sort((a, b) => (a['label'] as String).compareTo(b['label'] as String));

      if (mounted) {
        setState(() {
          _levelOptions = list;
        });
      }
    } catch (e) {
      print('Error fetching levels: $e');
    }
  }

  Future<void> _searchStudents(String query) async {
    if (query.isEmpty) return;
    setState(() => _isSearching = true);
    try {
      final snapshot = await FirebaseFirestore.instance.collection('students').get();
      final allStudents = snapshot.docs.map((d) => Student.fromMap(d.data() as Map<String, dynamic>, d.id)).toList();
      final results = allStudents.where((s) {
        final q = query.toLowerCase();
        return s.fullName.toLowerCase().contains(q) || s.fullNameRomaji.toLowerCase().contains(q);
      }).toList();
      setState(() { _searchResults = results; _isSearching = false; });
    } catch (e) {
      setState(() => _isSearching = false);
    }
  }

  Future<void> _pickExpiryDate() async {
    final picked = await showDatePicker(
      context: context, initialDate: _expiryDate, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (picked != null) {
      final endOfDay = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
      setState(() => _expiryDate = endOfDay);
    }
  }

  Future<void> _submitGrant() async {
    if (_selectedStudent == null) return;
    if (!_formKey.currentState!.validate()) return;
    if (_amountToAdd <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('1枚以上を入力してください')));
      return;
    }
    if (_selectedLevelId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('対象コース・レベルを選択してください')));
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final studentRef = FirebaseFirestore.instance.collection('students').doc(_selectedStudent!.id);
      final transactionRef = FirebaseFirestore.instance.collection('lessonTransactions').doc();
      final stockRef = FirebaseFirestore.instance.collection('ticket_stocks').doc();

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final sSnapshot = await transaction.get(studentRef);
        final sData = sSnapshot.data();
        final currentTotal = (sSnapshot.exists && sData != null) ? (sData['ticketBalance'] ?? 0) : 0;
        final newTotal = currentTotal + _amountToAdd;

        final history = LessonTransaction(
          id: transactionRef.id,
          studentId: _selectedStudent!.id,
          amount: _amountToAdd,
          type: 'purchase',
          createdAt: DateTime.now(),
          adminId: 'ADMIN',
          note: _adminNote.isEmpty ? '管理者による手動付与' : _adminNote,
          classGroupId: null,
          className: _selectedLevelName, 
          validLevelId: _selectedLevelId,
        );

        final newStock = TicketStock(
          id: stockRef.id,
          studentId: _selectedStudent!.id,
          totalAmount: _amountToAdd,
          remainingAmount: _amountToAdd,
          expiryDate: _expiryDate,
          createdAt: DateTime.now(),
          status: 'active',
          createdByTransactionId: transactionRef.id,
          classGroupId: null, 
          className: _selectedLevelName,
          validLevelId: _selectedLevelId,
        );

        transaction.update(studentRef, {'ticketBalance': newTotal});
        transaction.set(transactionRef, history.toMap());
        transaction.set(stockRef, newStock.toMap());
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_selectedStudent!.fullName}さんに $_amountToAdd枚 付与しました')),
      );

      setState(() {
        _selectedStudent = null;
        _amountToAdd = 0;
        _adminNote = '';
        _searchController.clear();
        _searchResults = [];
        _expiryDate = DateTime.now().add(const Duration(days: 180));
        _selectedLevelId = null;
        _selectedLevelName = null;
      });

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('エラー: $e')));
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy/MM/dd (E)', 'ja_JP');

    return Scaffold(
      appBar: AppBar(title: const Text('チケット付与 (在庫管理)')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: '生徒名で検索',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _searchStudents(_searchController.text),
                ),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: _searchStudents,
            ),
            const SizedBox(height: 10),

            if (_isSearching)
              const LinearProgressIndicator()
            else if (_selectedStudent == null)
              Expanded(
                child: _searchResults.isEmpty
                    ? const Center(child: Text('生徒を検索してください'))
                    : ListView.builder(
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final student = _searchResults[index];
                          return ListTile(
                            title: Text(student.fullName),
                            subtitle: Text('現在の合計所持数: ${student.ticketBalance}枚'),
                            trailing: ElevatedButton(
                              child: const Text('選択'),
                              onPressed: () {
                                setState(() {
                                  _selectedStudent = student;
                                  _searchResults = [];
                                });
                              },
                            ),
                          );
                        },
                      ),
              )
            else
              Expanded(
                child: Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    child: Card(
                      elevation: 4,
                      color: Colors.blue[50],
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('対象生徒:', style: TextStyle(color: Colors.grey)),
                                    Text(
                                      _selectedStudent!.fullName,
                                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                    ),
                                    Text('現在の合計所持数: ${_selectedStudent!.ticketBalance} 枚'),
                                  ],
                                ),
                                IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _selectedStudent = null))
                              ],
                            ),
                            const Divider(height: 30),
                            
                            // レベル選択
                            if (_levelOptions.isEmpty)
                              const Text('※予約制のコースが見つかりません', style: TextStyle(color: Colors.red))
                            else
                              DropdownButtonFormField<String>(
                                decoration: const InputDecoration(
                                  labelText: '対象コース・レベル (どのクラス用か)',
                                  icon: Icon(Icons.category),
                                  border: OutlineInputBorder(),
                                ),
                                items: _levelOptions.map((opt) {
                                  return DropdownMenuItem(
                                    value: opt['id'] as String,
                                    child: Text(opt['label'] as String, style: const TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis),
                                    onTap: () {
                                      _selectedLevelName = opt['label'] as String;
                                    },
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  setState(() => _selectedLevelId = val);
                                },
                                value: _selectedLevelId,
                              ),
                            const SizedBox(height: 20),

                            // 枚数
                            TextFormField(
                              decoration: const InputDecoration(
                                labelText: '付与する枚数 (回数券)',
                                icon: Icon(Icons.confirmation_number),
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              validator: (val) => (val == null || val.isEmpty || int.tryParse(val) == null) ? '数字のみ' : null,
                              onChanged: (val) => _amountToAdd = int.tryParse(val) ?? 0,
                            ),
                            const SizedBox(height: 20),

                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.calendar_today, color: Colors.indigo),
                              title: const Text('有効期限'),
                              subtitle: Text(dateFormat.format(_expiryDate), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              trailing: TextButton(onPressed: _pickExpiryDate, child: const Text('変更')),
                            ),
                            const SizedBox(height: 20),

                            TextFormField(
                              decoration: const InputDecoration(labelText: '管理者メモ', hintText: '例: 入金確認済', icon: Icon(Icons.note), border: OutlineInputBorder()),
                              onChanged: (val) => _adminNote = val,
                            ),
                            const SizedBox(height: 30),

                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.check),
                                label: _isSubmitting
                                  ? const CircularProgressIndicator(color: Colors.white)
                                  : const Text('この内容で付与する'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.indigo,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: _isSubmitting ? null : _submitGrant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}