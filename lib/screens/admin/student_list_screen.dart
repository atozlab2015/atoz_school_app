import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../models/student_model.dart';
import '../../models/class_model.dart';

class StudentListScreen extends StatefulWidget {
  const StudentListScreen({super.key});

  @override
  State<StudentListScreen> createState() => _StudentListScreenState();
}

class _StudentListScreenState extends State<StudentListScreen> {
  // マスタデータ
  Map<String, String> _courseNames = {};
  Map<String, String> _levelNames = {};
  List<Map<String, dynamic>> _classGroupOptions = []; 
  bool _isLoadingMaster = true;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchMasterData();
  }

  Future<void> _fetchMasterData() async {
    try {
      final firestore = FirebaseFirestore.instance;

      final coursesSnap = await firestore.collection('courses').get();
      for (var doc in coursesSnap.docs) {
        _courseNames[doc.id] = doc.data()['name'] ?? '';
      }

      final levelsSnap = await firestore.collection('levels').get();
      for (var doc in levelsSnap.docs) {
        _levelNames[doc.id] = doc.data()['name'] ?? '';
      }

      final classGroupsSnap = await firestore.collection('classGroups').get();

      final List<Map<String, dynamic>> options = [];
      final Map<String, bool> addedFlexibleLevels = {};
      
      const dayMap = {'1': '月', '2': '火', '3': '水', '4': '木', '5': '金', '6': '土', '7': '日'};

      for (var doc in classGroupsSnap.docs) {
        final data = doc.data();
        final group = ClassGroup.fromMap(data, doc.id);

        final courseName = _courseNames[group.courseId] ?? '不明';
        final levelName = _levelNames[group.levelId] ?? (group.levelId.isNotEmpty ? group.levelId : '不明');
        
        if (group.bookingType == 'flexible') {
          if (!addedFlexibleLevels.containsKey(group.levelId)) {
            final label = '【予約制】 $courseName / $levelName (曜日自由)';
            options.add({'id': group.id, 'label': label});
            addedFlexibleLevels[group.levelId] = true;
          }
        } else {
          String dayStr = group.dayOfWeek.toString();
          if (dayMap.containsKey(dayStr)) dayStr = dayMap[dayStr]!;
          final label = '$courseName / $levelName / $dayStr ${group.startTime} (${group.teacherName})';
          options.add({'id': group.id, 'label': label});
        }
      }

      if (mounted) {
        setState(() {
          _classGroupOptions = options;
          _isLoadingMaster = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching master data: $e');
      if (mounted) setState(() => _isLoadingMaster = false);
    }
  }

  void _executeSearch(String query) {
    setState(() {
      _searchQuery = query.trim().toLowerCase();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('生徒一覧・編集'), backgroundColor: Colors.orange),
      body: _isLoadingMaster
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: '生徒名で検索',
                      hintText: '漢字 または ローマ字',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: () => _executeSearch(_searchController.text),
                      ),
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: _executeSearch,
                  ),
                ),
                
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('students').orderBy('lastNameRomaji').snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) return Center(child: Text('エラー: ${snapshot.error}'));
                      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

                      final allDocs = snapshot.data!.docs;
                      
                      final filteredDocs = allDocs.where((doc) {
                        if (_searchQuery.isEmpty) return true; 

                        final data = doc.data() as Map<String, dynamic>;
                        final student = Student.fromMap(data, doc.id);
                        
                        final fullName = student.fullName.toLowerCase();
                        final fullNameRomaji = student.fullNameRomaji.toLowerCase();
                        
                        return fullName.contains(_searchQuery) || fullNameRomaji.contains(_searchQuery);
                      }).toList();

                      if (filteredDocs.isEmpty) return const Center(child: Text('条件に一致する生徒がいません'));

                      return ListView.separated(
                        itemCount: filteredDocs.length,
                        separatorBuilder: (ctx, i) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final doc = filteredDocs[index];
                          final data = doc.data() as Map<String, dynamic>;
                          final student = Student.fromMap(data, doc.id);
                          
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.orange.shade100,
                              child: Text(student.firstName.isNotEmpty ? student.firstName[0] : '?'),
                            ),
                            title: Text('${student.lastName} ${student.firstName}'),
                            subtitle: Text('${student.lastNameRomaji} ${student.firstNameRomaji}\n所持チケット: ${student.ticketBalance}枚'),
                            isThreeLine: true,
                            trailing: IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () => _showEditDialog(context, student),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  void _showEditDialog(BuildContext context, Student student) {
    final formKey = GlobalKey<FormState>();
    String lastName = student.lastName;
    String firstName = student.firstName;
    String lastNameRomaji = student.lastNameRomaji;
    String firstNameRomaji = student.firstNameRomaji;
    int ticketBalance = student.ticketBalance;
    
    // ★追加: 年会費編集用
    String annualFeeMonth = student.annualFeeMonth;
    final List<String> annualFeeOptions = [
      '年会費なし', 
      '1月', '2月', '3月', '4月', '5月', '6月', 
      '7月', '8月', '9月', '10月', '11月', '12月'
    ];
    
    List<Enrollment> tempEnrollments = List.from(student.enrollments);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('生徒情報の編集'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('基本情報', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                        Row(children: [
                          Expanded(child: TextFormField(initialValue: lastName, decoration: const InputDecoration(labelText: '姓'), onChanged: (v)=>lastName=v)),
                          const SizedBox(width: 10),
                          Expanded(child: TextFormField(initialValue: firstName, decoration: const InputDecoration(labelText: '名'), onChanged: (v)=>firstName=v)),
                        ]),
                        Row(children: [
                          Expanded(child: TextFormField(initialValue: lastNameRomaji, decoration: const InputDecoration(labelText: 'Surname'), onChanged: (v)=>lastNameRomaji=v)),
                          const SizedBox(width: 10),
                          Expanded(child: TextFormField(initialValue: firstNameRomaji, decoration: const InputDecoration(labelText: 'First Name'), onChanged: (v)=>firstNameRomaji=v)),
                        ]),
                        
                        const SizedBox(height: 10),
                        // ★追加: 年会費月
                        DropdownButtonFormField<String>(
                          value: annualFeeMonth,
                          decoration: const InputDecoration(labelText: '年会費の発生月'),
                          items: annualFeeOptions.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                          onChanged: (val) => setState(() => annualFeeMonth = val!),
                        ),

                        const SizedBox(height: 10),
                        TextFormField(
                          initialValue: ticketBalance.toString(),
                          decoration: const InputDecoration(labelText: 'チケット残高 (枚)', helperText: '手動修正用'),
                          keyboardType: TextInputType.number,
                          onChanged: (v) => ticketBalance = int.tryParse(v) ?? ticketBalance,
                        ),

                        const SizedBox(height: 20),
                        const Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('所属クラス', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                            TextButton.icon(
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('クラス追加'),
                              onPressed: () {
                                _showAddClassSubDialog(context, (newEnrollment) {
                                  setState(() {
                                    tempEnrollments.add(newEnrollment);
                                  });
                                });
                              },
                            ),
                          ],
                        ),
                        
                        if (tempEnrollments.isEmpty)
                          const Text('所属なし', style: TextStyle(color: Colors.grey)),

                        ...tempEnrollments.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final enroll = entry.value;
                          
                          final groupOpt = _classGroupOptions.firstWhere(
                            (g) => g['id'] == enroll.groupId,
                            orElse: () => {'label': '不明または削除されたクラス (ID: ${enroll.groupId})'},
                          );

                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                              title: Text(groupOpt['label'], style: const TextStyle(fontSize: 13)),
                              subtitle: Text('開始: ${DateFormat('yyyy/MM/dd').format(enroll.startDate)}'),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () {
                                  setState(() {
                                    tempEnrollments.removeAt(idx);
                                  });
                                },
                              ),
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
                ElevatedButton(
                  onPressed: () async {
                    try {
                      await FirebaseFirestore.instance.collection('students').doc(student.id).update({
                        'firstName': firstName,
                        'lastName': lastName,
                        'firstNameRomaji': firstNameRomaji,
                        'lastNameRomaji': lastNameRomaji,
                        'ticketBalance': ticketBalance,
                        'annualFeeMonth': annualFeeMonth, // ★追加: 更新
                        'enrollments': tempEnrollments.map((e) => e.toMap()).toList(),
                        'enrolledGroupIds': tempEnrollments.map((e) => e.groupId).toList(),
                      });
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('更新しました')));
                      }
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('更新エラー: $e')));
                    }
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAddClassSubDialog(BuildContext context, Function(Enrollment) onAdded) {
    String? selectedGroupId;
    DateTime startDate = DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('クラスを選択'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_classGroupOptions.isEmpty)
                  const Text('選択可能なクラスがありません', style: TextStyle(color: Colors.red)),
                  
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'クラス'),
                  items: _classGroupOptions.map((g) {
                    return DropdownMenuItem(
                      value: g['id'] as String,
                      child: Text(g['label'] as String, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => selectedGroupId = val),
                ),
                const SizedBox(height: 20),
                InkWell(
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context, 
                      initialDate: startDate, 
                      firstDate: DateTime(2020), 
                      lastDate: DateTime(2030),
                      locale: const Locale('ja'),
                    );
                    if (d != null) setState(() => startDate = d);
                  },
                  child: Row(
                    children: [
                      const Text('開始日: '),
                      Text(DateFormat('yyyy/MM/dd').format(startDate), style: const TextStyle(fontWeight: FontWeight.bold)),
                      const Icon(Icons.calendar_today),
                    ],
                  ),
                )
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
              ElevatedButton(
                onPressed: () {
                  if (selectedGroupId != null) {
                    onAdded(Enrollment(groupId: selectedGroupId!, startDate: startDate));
                    Navigator.pop(context);
                  }
                },
                child: const Text('追加'),
              )
            ],
          );
        },
      ),
    );
  }
}