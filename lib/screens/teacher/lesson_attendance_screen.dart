import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:atoz_school_app/models/lesson_model.dart';
import 'package:atoz_school_app/models/student_model.dart'; 

class LessonAttendanceScreen extends StatefulWidget {
  final LessonInstance lesson;

  const LessonAttendanceScreen({super.key, required this.lesson});

  @override
  State<LessonAttendanceScreen> createState() => _LessonAttendanceScreenState();
}

class _LessonAttendanceScreenState extends State<LessonAttendanceScreen> {
  List<Student> _students = [];
  // 出欠状況を管理するマップ (Key: studentId, Value: true/false)
  Map<String, bool> _attendanceStatus = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchAttendeesAndStatus();
  }

  // ■ 生徒リストと出欠状況をまとめて取得
  Future<void> _fetchAttendeesAndStatus() async {
    final firestore = FirebaseFirestore.instance;
    final lesson = widget.lesson;

    try {
      // 1. レギュラー生徒を取得
      final regularsSnapshot = await firestore
          .collection('students')
          .where('enrolledGroupIds', arrayContains: lesson.classGroupId)
          .get();
      
      final List<Student> regulars = [];
      for (var doc in regularsSnapshot.docs) {
        final s = Student.fromMap(doc.data(), doc.id);
        // 有効期間チェック
        for (var enrollment in s.enrollments) {
          if (enrollment.groupId == lesson.classGroupId) {
             final lessonDate = DateTime(lesson.startTime.year, lesson.startTime.month, lesson.startTime.day);
             final startDate = DateTime(enrollment.startDate.year, enrollment.startDate.month, enrollment.startDate.day);
             
             bool isActive = !lessonDate.isBefore(startDate);
             if (enrollment.endDate != null) {
               final endDate = DateTime(enrollment.endDate!.year, enrollment.endDate!.month, enrollment.endDate!.day);
               if (lessonDate.isAfter(endDate)) isActive = false;
             }
             
             if (isActive) regulars.add(s);
          }
        }
      }

      // 2. 振替生徒を取得
      final reservationsSnapshot = await firestore
          .collection('reservations')
          .where('lessonInstanceId', isEqualTo: lesson.id)
          .where('status', isEqualTo: 'approved')
          .get();

      final List<String> transferStudentIds = reservationsSnapshot.docs
          .map((doc) => doc.data()['studentId'] as String)
          .toList();

      List<Student> transfers = [];
      for (var id in transferStudentIds) {
        final doc = await firestore.collection('students').doc(id).get();
        if (doc.exists) {
          transfers.add(Student.fromMap(doc.data()!, doc.id));
        }
      }

      // 3. リストを合体
      final Map<String, Student> allAttendees = {};
      for (var s in regulars) allAttendees[s.id] = s;
      for (var s in transfers) allAttendees[s.id] = s;

      // 4. 出欠データの読み込み (attendanceRecords コレクション)
      final attendanceSnapshot = await firestore
          .collection('attendanceRecords')
          .where('lessonInstanceId', isEqualTo: lesson.id)
          .get();

      final Map<String, bool> currentStatus = {};
      for (var doc in attendanceSnapshot.docs) {
        final data = doc.data();
        final studentId = data['studentId'] as String;
        final isPresent = data['isPresent'] as bool? ?? false;
        currentStatus[studentId] = isPresent;
      }

      if (mounted) {
        setState(() {
          _students = allAttendees.values.toList();
          _attendanceStatus = currentStatus;
          _isLoading = false;
        });
      }

    } catch (e) {
      print('Error fetching attendees: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ■ スイッチ切替時の保存処理
  Future<void> _toggleAttendance(String studentId, bool newValue) async {
    // UIを先に更新 (サクサク動かすため)
    setState(() {
      _attendanceStatus[studentId] = newValue;
    });

    try {
      // DBに保存 (ドキュメントIDを "レッスンID_生徒ID" にして一意にする)
      final docId = '${widget.lesson.id}_$studentId';
      
      await FirebaseFirestore.instance.collection('attendanceRecords').doc(docId).set({
        'lessonInstanceId': widget.lesson.id,
        'studentId': studentId,
        'isPresent': newValue,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)); // マージして上書き

    } catch (e) {
      // エラー時はUIを戻すなどの処理が必要だが今回は省略
      print('Error saving attendance: $e');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('保存に失敗しました')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('M/d(E) HH:mm', 'ja').format(widget.lesson.startTime);

    return Scaffold(
      appBar: AppBar(title: const Text('出欠管理'), backgroundColor: Colors.orange),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.orange.shade50,
            child: Row(
              children: [
                const Icon(Icons.class_, color: Colors.orange),
                const SizedBox(width: 10),
                Text('$dateStr のクラス', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const Divider(height: 1),
          
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : _students.isEmpty
                ? const Center(child: Text('参加予定者はいません'))
                : ListView.builder(
                    itemCount: _students.length,
                    itemBuilder: (context, index) {
                      final student = _students[index];
                      final isPresent = _attendanceStatus[student.id] ?? false;

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isPresent ? Colors.green : Colors.grey.shade300,
                            child: Icon(Icons.person, color: isPresent ? Colors.white : Colors.grey),
                          ),
                          title: Text('${student.fullName} (${student.fullNameRomaji})'),
                          subtitle: Text(isPresent ? '出席' : '未チェック'),
                          trailing: Switch(
                            value: isPresent,
                            activeColor: Colors.green,
                            onChanged: (val) => _toggleAttendance(student.id, val),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}