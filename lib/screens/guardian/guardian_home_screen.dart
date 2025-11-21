import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:atoz_school_app/models/lesson_model.dart';
import 'package:atoz_school_app/models/student_model.dart';
import 'reservation_confirm_screen.dart';
import 'student_link_screen.dart';

class GuardianHomeScreen extends StatefulWidget {
  const GuardianHomeScreen({super.key});

  @override
  State<GuardianHomeScreen> createState() => _GuardianHomeScreenState();
}

class _GuardianHomeScreenState extends State<GuardianHomeScreen> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  
  Map<String, List<_CalendarItem>> _calendarItemsByDay = {}; 
  List<Student> _myChildren = [];
  bool _isLoading = true;

  // ★追加: マスタデータ（名前引き用）
  Map<String, String> _courseNames = {}; // courseId -> Name
  Map<String, String> _levelNames = {};  // levelId -> Name
  Map<String, String> _levelToCourse = {}; // levelId -> courseId

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _fetchMasterData(); // ★マスタデータを先に読み込む
    _fetchMyChildrenAndLessons();
  }

  // ★追加: コースとレベルの名前を取得する
  Future<void> _fetchMasterData() async {
    try {
      final firestore = FirebaseFirestore.instance;
      
      // コース名取得
      final coursesSnap = await firestore.collection('courses').get();
      for (var doc in coursesSnap.docs) {
        _courseNames[doc.id] = doc.data()['name'] ?? '';
      }

      // レベル名取得
      final levelsSnap = await firestore.collection('levels').get();
      for (var doc in levelsSnap.docs) {
        final data = doc.data();
        _levelNames[doc.id] = data['name'] ?? '';
        _levelToCourse[doc.id] = data['courseId'] ?? '';
      }
      
      // 画面更新（再描画して名前を反映）
      if (mounted) setState(() {});
      
    } catch (e) {
      print('Error fetching master data: $e');
    }
  }

  // ヘルパー関数: レベルIDからコース名・レベル名を取得
  String _getCourseAndLevelName(String levelId) {
    final levelName = _levelNames[levelId] ?? '';
    final courseId = _levelToCourse[levelId];
    final courseName = courseId != null ? _courseNames[courseId] ?? '' : '';
    
    if (courseName.isEmpty && levelName.isEmpty) return '';
    return '$courseName $levelName';
  }

  Future<void> _fetchMyChildrenAndLessons() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    
    final snapshot = await FirebaseFirestore.instance
        .collection('students')
        .where('parentId', isEqualTo: uid)
        .get();

    final children = snapshot.docs
        .map((doc) => Student.fromMap(doc.data(), doc.id))
        .toList();

    if (mounted) {
      setState(() {
        _myChildren = children;
        _isLoading = false;
      });
      if (children.isNotEmpty) {
        _startListeningToLessons();
      }
    }
  }

  void _startListeningToLessons() {
    FirebaseFirestore.instance
        .collection('lessonInstances')
        .where('isCancelled', isEqualTo: false)
        .snapshots()
        .listen((lessonSnapshot) async {
      
      final reservationSnapshot = await FirebaseFirestore.instance
          .collection('reservations')
          .where('studentId', whereIn: _myChildren.map((s) => s.id).toList())
          .where('status', whereIn: ['pending', 'approved'])
          .get();

      final Map<String, String> reservationMap = {};
      for (var doc in reservationSnapshot.docs) {
        final data = doc.data();
        final key = '${data['lessonInstanceId']}_${data['studentId']}';
        reservationMap[key] = data['status'];
      }

      final Map<String, List<_CalendarItem>> newItems = {};
      final DateFormat formatter = DateFormat('yyyy-MM-dd');

      for (var doc in lessonSnapshot.docs) {
        final lesson = LessonInstance.fromMap(doc.data(), doc.id);
        final dateString = formatter.format(lesson.startTime);

        for (var student in _myChildren) {
          bool shouldShow = false;
          String status = 'none';

          // A. 固定クラス所属チェック
          for (var enrollment in student.enrollments) {
            if (enrollment.groupId == lesson.classGroupId) {
              final lessonDate = DateTime(lesson.startTime.year, lesson.startTime.month, lesson.startTime.day);
              final startDate = DateTime(enrollment.startDate.year, enrollment.startDate.month, enrollment.startDate.day);
              
              bool isAfterStart = !lessonDate.isBefore(startDate);
              bool isBeforeEnd = true;
              if (enrollment.endDate != null) {
                final endDate = DateTime(enrollment.endDate!.year, enrollment.endDate!.month, enrollment.endDate!.day);
                if (lessonDate.isAfter(endDate)) isBeforeEnd = false;
              }

              if (isAfterStart && isBeforeEnd) {
                shouldShow = true;
                status = 'enrolled';
              }
            }
          }

          // B. 予約チェック
          final resKey = '${lesson.id}_${student.id}';
          if (reservationMap.containsKey(resKey)) {
            shouldShow = true;
            status = reservationMap[resKey] == 'approved' ? 'booked' : 'pending';
          }

          if (shouldShow) {
            final item = _CalendarItem(
              lesson: lesson,
              student: student,
              status: status,
            );
            
            if (newItems[dateString] == null) {
              newItems[dateString] = [];
            }
            newItems[dateString]!.add(item);
          }
        }
      }

      if (mounted) {
        setState(() {
          _calendarItemsByDay = newItems;
        });
      }
    });
  }

  List<_CalendarItem> _getEventsForDay(DateTime day) {
    final String dateString = DateFormat('yyyy-MM-dd').format(day);
    return _calendarItemsByDay[dateString] ?? [];
  }
  
  Future<void> _cancelReservation(String lessonId, String reservationId, String currentStatus) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('予約のキャンセル'),
        content: const Text('この予約を取り消しますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('いいえ')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('はい', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final reservationRef = FirebaseFirestore.instance.collection('reservations').doc(reservationId);
        final lessonRef = FirebaseFirestore.instance.collection('lessonInstances').doc(lessonId);

        DocumentSnapshot<Map<String, dynamic>>? lessonSnapshot;
        if (currentStatus == 'approved') {
          lessonSnapshot = await transaction.get(lessonRef);
        }

        transaction.update(reservationRef, {'status': 'cancelled'});

        if (currentStatus == 'approved' && lessonSnapshot != null && lessonSnapshot.exists) {
            final currentBookings = lessonSnapshot.data()!['currentBookings'] as int? ?? 1;
            final newCount = currentBookings > 0 ? currentBookings - 1 : 0;
            transaction.update(lessonRef, {'currentBookings': newCount});
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('予約を取り消しました。')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('エラー: $e')));
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final events = _getEventsForDay(_selectedDay ?? _focusedDay);

    return Scaffold(
      appBar: AppBar(
        title: const Text('保護者ホーム'),
        backgroundColor: Colors.blue.shade700,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            tooltip: '兄弟を追加',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StudentLinkScreen()),
              );
              _fetchMyChildrenAndLessons();
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          )
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : _myChildren.isEmpty 
          ? _buildNoChildrenView()
          : SingleChildScrollView(
              child: Column(
                children: [
                  TableCalendar(
                    firstDay: DateTime.utc(2024, 1, 1),
                    lastDay: DateTime.utc(2030, 12, 31),
                    focusedDay: _focusedDay,
                    calendarFormat: _calendarFormat,
                    locale: 'ja_JP',
                    eventLoader: _getEventsForDay,
                    selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                    onDaySelected: (selectedDay, focusedDay) {
                      if (!isSameDay(_selectedDay, selectedDay)) {
                        setState(() {
                          _selectedDay = selectedDay;
                          _focusedDay = focusedDay;
                        });
                      }
                    },
                    onPageChanged: (focusedDay) {
                      _focusedDay = focusedDay;
                    },
                    calendarStyle: CalendarStyle(
                      selectedDecoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
                      markersAlignment: Alignment.bottomRight,
                      markerDecoration: BoxDecoration(color: Colors.red.shade600, shape: BoxShape.circle),
                    ),
                    headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true),
                  ),
                  const Divider(height: 1),
                  
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text("予定リスト", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),

                  if (events.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text("この日の予定はありません。", style: TextStyle(color: Colors.black54)),
                    ),

                  ...events.map((item) => _buildLessonTile(item)).toList(),
                  
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _buildNoChildrenView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('生徒情報が登録されていません'),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StudentLinkScreen()),
              );
              _fetchMyChildrenAndLessons();
            },
            child: const Text('生徒IDを入力して紐付ける'),
          ),
        ],
      ),
    );
  }

  // ★修正: レッスンタイルの表示内容を変更
  Widget _buildLessonTile(_CalendarItem item) {
    final lesson = item.lesson;
    final student = item.student;
    
    String statusText = '';
    Color statusColor = Colors.grey;
    VoidCallback? onCancel;

    // コース名・レベル名を取得
    final courseLevelName = _getCourseAndLevelName(lesson.levelId);
    
    switch (item.status) {
      case 'enrolled':
        statusText = '所属クラス';
        statusColor = Colors.blueGrey;
        break;
      case 'booked':
        statusText = '予約済';
        statusColor = Colors.red;
        // 予約IDを取得してキャンセル処理へ
        // (簡易実装のため再検索ロジックは省略、本来はitemにreservationIdを持たせるべき)
        break;
      case 'pending':
        statusText = '申請中';
        statusColor = Colors.orange;
        break;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.indigo.shade100,
          child: Text(student.firstName.isNotEmpty ? student.firstName[0] : '?', style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        // 変更点1: 名前＋さん, 先生名ではなくコース・レベル名を表示
        title: Text('${student.firstName}さん: $courseLevelName', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        
        // 変更点2: 時間の後に先生名を表示
        subtitle: Text(
          '${DateFormat('HH:mm').format(lesson.startTime)} - ${DateFormat('HH:mm').format(lesson.endTime)}  ${lesson.teacherName}先生',
          style: const TextStyle(fontSize: 13)
        ),
        
        trailing: Chip(
          label: Text(statusText, style: const TextStyle(color: Colors.white, fontSize: 12)),
          backgroundColor: statusColor,
        ),
        // タップ時の処理（キャンセルなど）は別途実装
      ),
    );
  }
}

class _CalendarItem {
  final LessonInstance lesson;
  final Student student;
  final String status; 

  _CalendarItem({required this.lesson, required this.student, required this.status});
}