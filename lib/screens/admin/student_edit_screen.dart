import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
// 相対パスでインポート
import '../../models/student_model.dart';

class StudentEditScreen extends StatefulWidget {
  final Student student; 

  const StudentEditScreen({super.key, required this.student});

  @override
  State<StudentEditScreen> createState() => _StudentEditScreenState();
}

class _StudentEditScreenState extends State<StudentEditScreen> {
  final _formKey = GlobalKey<FormState>();
  
  late String _lastName;
  late String _firstName;
  late String _lastNameRomaji;
  late String _firstNameRomaji;
  late DateTime _dob;
  late DateTime _admissionDate;
  // Enrollment型のリストを使う
  late List<Enrollment> _enrollments; 

  Map<String, String> _courseNames = {};
  Map<String, String> _levelNames = {};
  List<Map<String, dynamic>> _classGroupOptions = [];

  @override
  void initState() {
    super.initState();
    _lastName = widget.student.lastName;
    _firstName = widget.student.firstName;
    _lastNameRomaji = widget.student.lastNameRomaji;
    _firstNameRomaji = widget.student.firstNameRomaji;
    _dob = widget.student.dob;
    _admissionDate = widget.student.admissionDate;
    _enrollments = List.from(widget.student.enrollments);
    
    _fetchAllMasterData();
  }

  Future<void> _fetchAllMasterData() async {
    final firestore = FirebaseFirestore.instance;
    final coursesSnap = await firestore.collection('courses').get();
    for (var doc in coursesSnap.docs) _courseNames[doc.id] = doc.data()['name'] ?? '';
    final levelsSnap = await firestore.collection('levels').get();
    for (var doc in levelsSnap.docs) _levelNames[doc.id] = doc.data()['name'] ?? '';

    final groupsSnap = await firestore.collection('groups').get();
    final List<Map<String, dynamic>> options = [];
    for (var doc in groupsSnap.docs) {
      final data = doc.data();
      final courseName = _courseNames[data['courseId']] ?? '不明';
      final levelName = _levelNames[data['levelId']] ?? '不明';
      final label = '$courseName / $levelName / ${data['dayOfWeek']} ${data['startTime']} (${data['teacherName']})';
      options.add({'id': doc.id, 'label': label});
    }
    if (mounted) setState(() => _classGroupOptions = options);
  }

  Future<void> _updateStudent() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    try {
      final updatedStudent = Student(
        id: widget.student.id, 
        parentId: widget.student.parentId,
        firstName: _firstName,
        lastName: _lastName,
        firstNameRomaji: _firstNameRomaji,
        lastNameRomaji: _lastNameRomaji,
        dob: _dob,
        admissionDate: _admissionDate,
        enrollments: _enrollments,
        // ★追加
        enrolledGroupIds: _enrollments.map((e) => e.groupId).toList(), 
      );

      await FirebaseFirestore.instance
          .collection('students')
          .doc(widget.student.id)
          .update(updatedStudent.toMap());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('生徒情報を更新しました')));
        Navigator.pop(context); 
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('エラー: $e')));
    }
  }

  void _showAddClassDialog() {
    String? selectedGroupId;
    DateTime startDate = DateTime.now();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('受講クラスの追加'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'クラスを選択'),
                  items: _classGroupOptions.map((group) {
                    return DropdownMenuItem(
                      value: group['id'] as String,
                      child: Text(group['label'] as String, style: const TextStyle(fontSize: 12)),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => selectedGroupId = val),
                ),
                const SizedBox(height: 20),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: startDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                      locale: const Locale("ja"),
                    );
                    if (picked != null) setState(() => startDate = picked);
                  },
                  child: Row(
                    children: [
                      const Text('開始日: '),
                      Text(DateFormat('yyyy/MM/dd').format(startDate), style: const TextStyle(fontWeight: FontWeight.bold)),
                      const Icon(Icons.calendar_today, size: 16),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  if (selectedGroupId != null) {
                    // 親WidgetのStateを更新
                    this.setState(() {
                      _enrollments.add(Enrollment(
                        groupId: selectedGroupId!,
                        startDate: startDate,
                        endDate: null, 
                      ));
                    });
                    Navigator.pop(context);
                  }
                },
                child: const Text('追加'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEndClassDialog(int index) {
    final rawStartDate = _enrollments[index].startDate;
    final DateTime firstDate = DateTime(rawStartDate.year, rawStartDate.month, rawStartDate.day);
    final rawEndDate = _enrollments[index].endDate ?? DateTime.now();
    DateTime endDate = DateTime(rawEndDate.year, rawEndDate.month, rawEndDate.day);
    if (endDate.isBefore(firstDate)) endDate = firstDate;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('クラス終了日の設定'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('終了日を選択してください'),
                const SizedBox(height: 20),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: endDate,
                      firstDate: firstDate,
                      lastDate: DateTime(2030),
                      locale: const Locale("ja"),
                    );
                    if (picked != null) setState(() => endDate = picked);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(5)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(DateFormat('yyyy/MM/dd').format(endDate), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 10),
                        const Icon(Icons.edit_calendar),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              if (_enrollments[index].endDate != null)
                TextButton(
                  onPressed: () {
                    this.setState(() {
                      final old = _enrollments[index];
                      _enrollments[index] = Enrollment(
                        groupId: old.groupId,
                        startDate: old.startDate,
                        endDate: null, 
                      );
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('終了を取り消す (受講中へ)'),
                ),
              ElevatedButton(
                onPressed: () {
                  this.setState(() {
                    final old = _enrollments[index];
                    _enrollments[index] = Enrollment(
                      groupId: old.groupId,
                      startDate: old.startDate,
                      endDate: endDate,
                    );
                  });
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                child: const Text('設定する'),
              ),
            ],
          );
        },
      ),
    );
  }

  // 日付選択 (生年月日・入会日用)
  Future<void> _selectDate(bool isDob) async {
    final initialDate = isDob ? _dob : _admissionDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1950),
      lastDate: DateTime(2030),
      locale: const Locale("ja"),
    );
    if (picked != null) {
      setState(() {
        if (isDob) _dob = picked;
        else _admissionDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('生徒情報の編集'), backgroundColor: Colors.orange),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('基本情報', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextFormField(initialValue: _lastName, decoration: const InputDecoration(labelText: '姓'), onSaved: (v)=>_lastName=v!)),
                const SizedBox(width: 16),
                Expanded(child: TextFormField(initialValue: _firstName, decoration: const InputDecoration(labelText: '名'), onSaved: (v)=>_firstName=v!)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextFormField(initialValue: _lastNameRomaji, decoration: const InputDecoration(labelText: 'Surname'), onSaved: (v)=>_lastNameRomaji=v!)),
                const SizedBox(width: 16),
                Expanded(child: TextFormField(initialValue: _firstNameRomaji, decoration: const InputDecoration(labelText: 'First Name'), onSaved: (v)=>_firstNameRomaji=v!)),
              ]),
              
              const SizedBox(height: 20),
              ListTile(title: const Text('生年月日'), trailing: Text(DateFormat('yyyy/MM/dd').format(_dob)), onTap: () => _selectDate(true)),
              ListTile(title: const Text('入会日'), trailing: Text(DateFormat('yyyy/MM/dd').format(_admissionDate)), onTap: () => _selectDate(false)),

              const Divider(height: 40),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('受講クラス履歴', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('クラスを追加'),
                    onPressed: _showAddClassDialog,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              
              if (_enrollments.isEmpty)
                const Text('受講クラスはありません', style: TextStyle(color: Colors.grey)),

              ..._enrollments.asMap().entries.map((entry) {
                final index = entry.key;
                final enrollment = entry.value;
                
                final label = _classGroupOptions.firstWhere(
                  (opt) => opt['id'] == enrollment.groupId, 
                  orElse: () => {'label': '読み込み中...'}
                )['label'];
                
                final startStr = DateFormat('yyyy/MM/dd').format(enrollment.startDate);
                final isActive = enrollment.endDate == null;
                final endStr = isActive ? '現在' : DateFormat('yyyy/MM/dd').format(enrollment.endDate!);

                return Card(
                  color: isActive ? Colors.white : Colors.grey.shade200,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(Icons.class_, color: isActive ? Colors.indigo : Colors.grey),
                    title: Text(label!, style: TextStyle(fontWeight: FontWeight.bold, color: isActive ? Colors.black : Colors.grey)),
                    subtitle: Text('$startStr 〜 $endStr'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_calendar, color: Colors.orange),
                          onPressed: () => _showEndClassDialog(index),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.grey),
                          onPressed: () {
                            setState(() {
                              _enrollments.removeAt(index);
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                );
              }),

              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('変更を保存する'),
                  onPressed: _updateStudent,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}