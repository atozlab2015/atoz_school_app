import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
// 相対パスでインポート
import '../../models/student_model.dart';

class StudentRegistrationScreen extends StatefulWidget {
  const StudentRegistrationScreen({super.key});

  @override
  State<StudentRegistrationScreen> createState() => _StudentRegistrationScreenState();
}

class _StudentRegistrationScreenState extends State<StudentRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  
  String _lastName = '';
  String _firstName = '';
  String _lastNameRomaji = '';
  String _firstNameRomaji = '';
  DateTime _dob = DateTime(2018, 4, 2); 
  DateTime _admissionDate = DateTime.now(); 
  
  List<Enrollment> _tempEnrollments = [];
  
  Map<String, String> _courseNames = {};
  Map<String, String> _levelNames = {};
  List<Map<String, dynamic>> _classGroupOptions = [];

  String? _registeredStudentId;
  String? _registeredName;

  @override
  void initState() {
    super.initState();
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

  String _calculateGrade(DateTime dob) {
    final now = DateTime.now();
    int currentSchoolYear = (now.month >= 4) ? now.year : now.year - 1;
    int birthSchoolYear = (dob.month >= 4 || (dob.month == 4 && dob.day >= 2)) ? dob.year : dob.year - 1;
    int diff = currentSchoolYear - birthSchoolYear;

    if (diff == 7) return '小学1年生';
    if (diff == 8) return '小学2年生';
    if (diff == 9) return '小学3年生';
    if (diff == 10) return '小学4年生';
    if (diff == 11) return '小学5年生';
    if (diff == 12) return '小学6年生';
    if (diff == 13) return '中学1年生';
    if (diff == 14) return '中学2年生';
    if (diff == 15) return '中学3年生';
    if (diff >= 16 && diff <= 18) return '高校生';
    
    if (diff == 6) return '年長 (5歳児クラス)';
    if (diff == 5) return '年中 (4歳児クラス)';
    if (diff == 4) return '年少 (3歳児クラス)';
    if (diff == 3) return '2歳児クラス';
    if (diff == 2) return '1歳児クラス';
    if (diff <= 1) return '0歳児クラス';

    if (diff >= 19) return '大学生/社会人';
    return 'その他';
  }

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
                      const Icon(Icons.calendar_today),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('キャンセル')),
              ElevatedButton(
                onPressed: () {
                  if (selectedGroupId != null) {
                    this.setState(() {
                      _tempEnrollments.add(Enrollment(
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

  Future<void> _registerStudent() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    try {
      final newDocRef = FirebaseFirestore.instance.collection('students').doc();
      
      final newStudent = Student(
        id: newDocRef.id,
        parentId: '', 
        firstName: _firstName,
        lastName: _lastName,
        firstNameRomaji: _firstNameRomaji,
        lastNameRomaji: _lastNameRomaji,
        dob: _dob,
        admissionDate: _admissionDate,
        enrollments: _tempEnrollments, 
        // ★追加: モデルのコンストラクタが変わったため
        enrolledGroupIds: _tempEnrollments.map((e) => e.groupId).toList(), 
      );

      await newDocRef.set(newStudent.toMap());

      setState(() {
        _registeredStudentId = newDocRef.id;
        _registeredName = '$_lastName $_firstName';
        _formKey.currentState!.reset();
        _lastName = '';
        _firstName = '';
        _lastNameRomaji = '';
        _firstNameRomaji = '';
        _tempEnrollments = []; 
      });

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('生徒を登録しました')));

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('エラー: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('生徒の新規登録'), backgroundColor: Colors.indigo),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_registeredStudentId != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                child: SelectableText('登録ID: $_registeredStudentId'),
              ),
              const SizedBox(height: 30),
            ],

            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('氏名', style: TextStyle(fontWeight: FontWeight.bold)),
                  Row(children: [
                    Expanded(child: TextFormField(decoration: const InputDecoration(labelText: '姓'), onSaved: (v)=>_lastName=v!)),
                    const SizedBox(width: 16),
                    Expanded(child: TextFormField(decoration: const InputDecoration(labelText: '名'), onSaved: (v)=>_firstName=v!)),
                  ]),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: TextFormField(decoration: const InputDecoration(labelText: 'Surname'), onSaved: (v)=>_lastNameRomaji=v!)),
                    const SizedBox(width: 16),
                    Expanded(child: TextFormField(decoration: const InputDecoration(labelText: 'First Name'), onSaved: (v)=>_firstNameRomaji=v!)),
                  ]),
                  
                  const SizedBox(height: 20),
                  ListTile(
                    title: const Text('生年月日'), 
                    trailing: Text(DateFormat('yyyy/MM/dd').format(_dob)), 
                    onTap: () => _selectDate(true)
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    width: double.infinity,
                    color: Colors.blue.shade50,
                    child: Text(
                      '自動計算: ${_calculateGrade(_dob)}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  const SizedBox(height: 20),
                  ListTile(
                    title: const Text('入会日 (スクール)'), 
                    trailing: Text(DateFormat('yyyy/MM/dd').format(_admissionDate)), 
                    onTap: () => _selectDate(false)
                  ),

                  const Divider(height: 40),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('受講クラス設定', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      TextButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('クラスを追加'),
                        onPressed: _showAddClassDialog,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  
                  if (_tempEnrollments.isEmpty)
                    const Text('受講クラスは追加されていません', style: TextStyle(color: Colors.grey)),
                  
                  ..._tempEnrollments.asMap().entries.map((entry) {
                    final index = entry.key;
                    final enrollment = entry.value;
                    final label = _classGroupOptions.firstWhere(
                      (opt) => opt['id'] == enrollment.groupId, 
                      orElse: () => {'label': '不明なクラス'}
                    )['label'];
                    final dateStr = DateFormat('yyyy/MM/dd').format(enrollment.startDate);

                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.class_, color: Colors.indigo),
                        title: Text(label!),
                        subtitle: Text('開始日: $dateStr'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.grey),
                          onPressed: () {
                            setState(() {
                              _tempEnrollments.removeAt(index);
                            });
                          },
                        ),
                      ),
                    );
                  }),
                  
                  const SizedBox(height: 40),
                  SizedBox(width: double.infinity, height: 50, child: ElevatedButton(onPressed: _registerStudent, child: const Text('登録する'))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}