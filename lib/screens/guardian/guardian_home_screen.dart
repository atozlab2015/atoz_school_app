import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../models/lesson_model.dart';
import '../../models/student_model.dart';
import '../../models/ticket_model.dart';
import '../../models/class_model.dart';
import '../../models/lesson_transaction_model.dart';

import 'student_link_screen.dart';
import 'ticket_list_screen.dart';
import 'reservation_confirm_screen.dart';
import 'transfer_lesson_selector_screen.dart';
import 'transfer_history_screen.dart';
import 'guardian_booking_screen.dart';
import 'guardian_transaction_history_screen.dart'; 

class GuardianHomeScreen extends StatefulWidget {
  const GuardianHomeScreen({super.key});

  @override
  State<GuardianHomeScreen> createState() => _GuardianHomeScreenState();
}

class _GuardianHomeScreenState extends State<GuardianHomeScreen> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  
  List<Student> _myChildren = [];
  bool _isLoadingChildren = true;
  bool _isLoadingMaster = true; 

  Map<String, String> _courseNames = {}; 
  Map<String, String> _levelNames = {};  
  Map<String, String> _levelToCourse = {}; 
  Map<String, String> _groupToLevel = {}; 
  Map<String, ClassGroup> _classGroupMap = {}; 

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _fetchMasterData(); 
    _fetchMyChildren();
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
        final data = doc.data();
        _levelNames[doc.id] = data['name'] ?? '';
        _levelToCourse[doc.id] = data['courseId'] ?? '';
      }
      
      final allGroupDocs = <QueryDocumentSnapshot>[];
      final classGroupsSnap = await firestore.collection('classGroups').get();
      allGroupDocs.addAll(classGroupsSnap.docs);
      final groupsSnap = await firestore.collection('groups').get();
      allGroupDocs.addAll(groupsSnap.docs);
      
      for (var doc in allGroupDocs) {
        final data = doc.data() as Map<String, dynamic>;
        _groupToLevel[doc.id] = data['levelId'] ?? '';
        _classGroupMap[doc.id] = ClassGroup.fromMap(data, doc.id);
      }
      
      if (mounted) {
        setState(() {
          _isLoadingMaster = false;
        });
      }
    } catch (e) {
      print('Error fetching master data: $e');
      if (mounted) setState(() => _isLoadingMaster = false);
    }
  }

  String _getCourseAndLevelName(String levelId) {
    final levelName = _levelNames[levelId] ?? '';
    final courseId = _levelToCourse[levelId];
    final courseName = courseId != null ? _courseNames[courseId] ?? '' : '';
    if (courseName.isEmpty && levelName.isEmpty) return '';
    return '$courseName $levelName';
  }

  Future<void> _fetchMyChildren() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final snapshot = await FirebaseFirestore.instance
        .collection('students')
        .where('parentId', isEqualTo: uid)
        .get();
    
    if (mounted) {
      setState(() {
        _myChildren = snapshot.docs.map((doc) => Student.fromMap(doc.data() as Map<String, dynamic>, doc.id)).toList();
        _isLoadingChildren = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingChildren || _isLoadingMaster) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    
    if (_myChildren.isEmpty) return _buildNoChildrenView();

    final studentIds = _myChildren.map((s) => s.id).toList();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('lessonInstances')
          .where('isCancelled', isEqualTo: false)
          .snapshots(),
      builder: (context, lessonSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('reservations')
              .where('studentId', whereIn: studentIds)
              .where('status', whereIn: ['pending', 'approved'])
              .snapshots(),
          builder: (context, resSnap) {
            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('tickets')
                  .where('studentId', whereIn: studentIds)
                  .snapshots(),
              builder: (context, ticketSnap) {
                if (!lessonSnap.hasData || !resSnap.hasData || !ticketSnap.hasData) {
                  return const Scaffold(body: Center(child: CircularProgressIndicator()));
                }

                final calendarItems = _generateCalendarItems(
                  lessonSnap.data!.docs,
                  resSnap.data!.docs,
                  ticketSnap.data!.docs,
                );

                return _buildMainScreen(calendarItems);
              },
            );
          },
        );
      },
    );
  }

  // ★ここに追加しました
  Widget _buildNoChildrenView() {
    return Scaffold(
      appBar: AppBar(title: const Text('ホーム')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('生徒情報が登録されていません'),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const StudentLinkScreen()));
                _fetchMyChildren();
              },
              child: const Text('生徒IDを入力して紐付ける'),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, List<_CalendarItem>> _generateCalendarItems(
    List<QueryDocumentSnapshot> lessonDocs,
    List<QueryDocumentSnapshot> resDocs,
    List<QueryDocumentSnapshot> ticketDocs,
  ) {
    final Map<String, List<_CalendarItem>> itemsByDay = {};
    final DateFormat formatter = DateFormat('yyyy-MM-dd');

    final Map<String, LessonInstance> allLessonsMap = {
      for (var doc in lessonDocs) 
        doc.id: LessonInstance.fromMap(doc.data() as Map<String, dynamic>, doc.id)
    };

    final Map<String, QueryDocumentSnapshot> resMap = {};
    final Map<String, QueryDocumentSnapshot> transferSourceMap = {};
    final Map<String, Map<String, dynamic>> allResByIdMap = {
      for (var doc in resDocs)
        doc.id: doc.data() as Map<String, dynamic>
    };

    for (var doc in resDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final key = '${data['lessonInstanceId']}_${data['studentId']}';
      resMap[key] = doc;
      if (data['originalLessonId'] != null) {
        final sourceKey = '${data['originalLessonId']}_${data['studentId']}';
        transferSourceMap[sourceKey] = doc;
      }
    }

    final Map<String, QueryDocumentSnapshot> ticketMap = {};
    for (var doc in ticketDocs) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['sourceLessonId'] != null) {
        final key = '${data['sourceLessonId']}_${data['studentId']}';
        ticketMap[key] = doc;
      }
    }

    for (var doc in lessonDocs) {
      final lesson = LessonInstance.fromMap(doc.data() as Map<String, dynamic>, doc.id);
      final dateString = formatter.format(lesson.startTime);
      final classGroup = _classGroupMap[lesson.classGroupId]; 

      for (var student in _myChildren) {
        bool shouldShow = false;
        String status = 'none';
        String? reservationId;
        Ticket? internalTicket;
        LessonInstance? destinationLesson;
        LessonInstance? sourceLesson;

        final uniqueKey = '${lesson.id}_${student.id}';

        // 所属チェック
        bool isEnrolled = false;
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
            if (isAfterStart && isBeforeEnd) isEnrolled = true;
          }
        }

        if (isEnrolled) {
          if (classGroup != null && classGroup.bookingType == 'flexible') {
             shouldShow = true;
             status = 'flexible_not_booked'; 
          } else {
             shouldShow = true;
             status = 'enrolled'; 
          }

          if (transferSourceMap.containsKey(uniqueKey)) {
            status = 'ticket_used'; 
            final resDoc = transferSourceMap[uniqueKey]!;
            final resData = resDoc.data() as Map<String, dynamic>;
            final destId = resData['lessonInstanceId'];
            destinationLesson = allLessonsMap[destId];
          }
          else if (ticketMap.containsKey(uniqueKey)) {
            final tData = ticketMap[uniqueKey]!.data() as Map<String, dynamic>;
            internalTicket = Ticket.fromMap(tData, ticketMap[uniqueKey]!.id);
            final validLevelId = tData['validLevelId'];
            final isUsed = tData['isUsed'] ?? false;

            if (validLevelId == 'forfeited') {
              status = 'absent_no_transfer'; 
            } else if (isUsed) {
              status = 'ticket_used'; 
              final usedResId = tData['usedForReservationId'];
              if (usedResId != null && allResByIdMap.containsKey(usedResId)) {
                final resData = allResByIdMap[usedResId]!;
                final destId = resData['lessonInstanceId'];
                destinationLesson = allLessonsMap[destId];
              }
            } else {
              status = 'ticket_pending'; 
            }
          }
        }

        if (resMap.containsKey(uniqueKey)) {
          shouldShow = true;
          final rData = resMap[uniqueKey]!.data() as Map<String, dynamic>;
          status = rData['status'] == 'approved' ? 'booked' : 'pending';
          reservationId = resMap[uniqueKey]!.id;
          
          if (rData['originalLessonId'] != null) {
            final orgId = rData['originalLessonId'];
            sourceLesson = allLessonsMap[orgId];
          }
        }

        if (shouldShow) {
          final item = _CalendarItem(
            lesson: lesson,
            student: student,
            status: status,
            reservationId: reservationId,
            internalTicket: internalTicket,
            destinationLesson: destinationLesson,
            sourceLesson: sourceLesson,
            classGroup: classGroup,
          );
          if (itemsByDay[dateString] == null) itemsByDay[dateString] = [];
          itemsByDay[dateString]!.add(item);
        }
      }
    }
    return itemsByDay;
  }

  Widget _buildMainScreen(Map<String, List<_CalendarItem>> itemsByDay) {
    final events = itemsByDay[DateFormat('yyyy-MM-dd').format(_selectedDay ?? _focusedDay)] ?? [];
    
    List<ClassGroup> flexibleClasses = [];
    for (var child in _myChildren) {
      for (var enrollment in child.enrollments) {
        final group = _classGroupMap[enrollment.groupId];
        if (group != null && group.bookingType == 'flexible') {
          if (!flexibleClasses.any((g) => g.id == group.id)) {
            flexibleClasses.add(group);
          }
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('ホーム'),
        backgroundColor: Colors.blue.shade700,
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long),
            tooltip: 'チケット履歴',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GuardianTransactionHistoryScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: '振替履歴',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TransferHistoryScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const StudentLinkScreen()));
              _fetchMyChildren();
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          )
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            TableCalendar(
              firstDay: DateTime.utc(2024, 1, 1),
              lastDay: DateTime.utc(2030, 12, 31),
              focusedDay: _focusedDay,
              calendarFormat: _calendarFormat,
              locale: 'ja_JP',
              eventLoader: (day) {
                final allEvents = itemsByDay[DateFormat('yyyy-MM-dd').format(day)] ?? [];
                return allEvents.where((item) {
                  if (item.status == 'flexible_not_booked') return false;
                  return item.status != 'ticket_used' && item.status != 'absent_no_transfer';
                }).toList();
              },
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              onDaySelected: (selectedDay, focusedDay) {
                if (!isSameDay(_selectedDay, selectedDay)) {
                  setState(() {
                    _selectedDay = selectedDay;
                    _focusedDay = focusedDay;
                  });
                }
              },
              onPageChanged: (focusedDay) => _focusedDay = focusedDay,
              calendarStyle: CalendarStyle(
                selectedDecoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
                todayDecoration: BoxDecoration(color: Colors.blue.withOpacity(0.5), shape: BoxShape.circle),
                markerDecoration: BoxDecoration(color: Colors.red.shade600, shape: BoxShape.circle),
              ),
              headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true),
            ),
            const Divider(height: 1),
            
            if (flexibleClasses.isNotEmpty) ...[
               Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: const [
                    Icon(Icons.airplane_ticket, color: Colors.orange),
                    SizedBox(width: 8),
                    Text("チケット予約", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
              ),
              ...flexibleClasses.map((group) {
                  final student = _myChildren.firstWhere((s) => s.enrollments.any((e) => e.groupId == group.id));
                  return Card(
                    color: Colors.orange[50],
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: ListTile(
                      title: Text('${student.firstName}さん: ${_getCourseAndLevelName(group.levelId)}'),
                      subtitle: const Text('受講するには予約が必要です'),
                      trailing: ElevatedButton(
                        child: const Text('予約する'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                        onPressed: () {
                          Navigator.push(
                            context, 
                            MaterialPageRoute(builder: (_) => GuardianBookingScreen(
                              student: student, 
                              enrolledClass: group
                            ))
                          );
                        },
                      ),
                    ),
                  );
              }),
              const Divider(),
            ],

            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text("選択日の予定", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            if (events.where((e) => e.status != 'flexible_not_booked').isEmpty)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text("この日の予定はありません。", style: TextStyle(color: Colors.black54)),
              ),
            ...events.where((e) => e.status != 'flexible_not_booked').map((item) => _buildLessonTile(item)).toList(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildLessonTile(_CalendarItem item) {
    final lesson = item.lesson;
    final student = item.student;
    String statusText = '';
    Color statusColor = Colors.grey;
    Color cardColor = Colors.white;

    final courseLevelName = _getCourseAndLevelName(lesson.levelId);
    
    switch (item.status) {
      case 'enrolled':
        statusText = '受講中';
        statusColor = Colors.blueGrey;
        cardColor = Colors.blue.shade50;
        break;
      case 'booked':
        statusText = '予約済'; 
        statusColor = Colors.indigo;
        cardColor = Colors.indigo.shade50;
        if (item.sourceLesson != null) {
          statusText = '振替レッスン';
          statusColor = Colors.red;
          cardColor = Colors.red.shade50;
        }
        break;
      case 'pending':
        statusText = '申請中';
        statusColor = Colors.orange;
        break;
      case 'ticket_used':
        statusText = '欠席(振替予約済)';
        statusColor = Colors.grey;
        cardColor = Colors.grey.shade200;
        break;
      case 'ticket_pending':
        statusText = '振替検討中';
        statusColor = Colors.green;
        cardColor = Colors.green.shade50;
        break;
      case 'absent_no_transfer':
        statusText = '欠席(振替なし)';
        statusColor = Colors.grey;
        cardColor = Colors.grey.shade300;
        break;
    }

    return Card(
      color: cardColor,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: (item.status.contains('ticket') || item.status.contains('absent')) 
              ? Colors.grey.shade400 
              : (item.status == 'ticket_pending' ? Colors.green.shade100 : Colors.indigo.shade100),
          child: Text(student.firstName.isNotEmpty ? student.firstName[0] : '?', style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        title: Text('${student.firstName}さん: $courseLevelName', 
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, 
            color: (item.status.contains('ticket') || item.status.contains('absent')) ? Colors.grey.shade700 : Colors.black)),
        
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${DateFormat('M/d(E) HH:mm', 'ja').format(lesson.startTime)} - ${DateFormat('HH:mm').format(lesson.endTime)}  ${lesson.teacherName}先生',
              style: const TextStyle(fontSize: 13)
            ),
            
            if (item.status == 'ticket_used' && item.destinationLesson != null) ...[
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.arrow_forward, size: 14, color: Colors.blue),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${DateFormat('M/d(E) HH:mm', 'ja').format(item.destinationLesson!.startTime)}-${DateFormat('HH:mm').format(item.destinationLesson!.endTime)} ${item.destinationLesson!.teacherName}先生 に振替予約済み',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue),
                    ),
                  ),
                ],
              ),
            ],

            if (item.status == 'booked' && item.sourceLesson != null) ...[
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.arrow_back, size: 14, color: Colors.red),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${DateFormat('M/d(E) HH:mm', 'ja').format(item.sourceLesson!.startTime)}-${DateFormat('HH:mm').format(item.sourceLesson!.endTime)} ${item.sourceLesson!.teacherName}先生 から振替',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        
        trailing: Chip(
          label: Text(statusText, style: const TextStyle(color: Colors.white, fontSize: 11)),
          backgroundColor: statusColor,
        ),
        onTap: () {
          final bookingType = (item.classGroup?.bookingType ?? '').trim();
          bool isFlexible = bookingType == 'flexible';
          bool isBooked = item.status == 'booked';
          bool isNotTransfer = item.sourceLesson == null;

          if (isFlexible && isBooked && isNotTransfer) {
              _cancelFlexibleBooking(item.reservationId!);
          } else if (item.status == 'ticket_pending') {
             _goToTransferSelection(item);
          } else {
             _showLessonActionMenu(item);
          }
        },
      ),
    );
  }

  Future<void> _cancelFlexibleBooking(String reservationId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('予約キャンセル'),
        content: const Text('予約をキャンセルし、チケットを1枚戻しますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('いいえ')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('はい')),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
         final resRef = FirebaseFirestore.instance.collection('reservations').doc(reservationId);
         final resSnap = await transaction.get(resRef);
         if (!resSnap.exists) return;
         
         final lessonId = resSnap.data()!['lessonInstanceId'] as String;
         final studentId = resSnap.data()!['studentId'] as String;

         transaction.update(resRef, {'status': 'cancelled'});

         final lessonRef = FirebaseFirestore.instance.collection('lessonInstances').doc(lessonId);
         transaction.update(lessonRef, {'currentBookings': FieldValue.increment(-1)});

         final stockQuery = await FirebaseFirestore.instance
             .collection('ticket_stocks')
             .where('studentId', isEqualTo: studentId)
             .where('status', isEqualTo: 'active')
             .get();
         
         if (stockQuery.docs.isNotEmpty) {
           final docs = stockQuery.docs;
           docs.sort((a, b) {
             final d1 = (a['expiryDate'] as Timestamp).toDate();
             final d2 = (b['expiryDate'] as Timestamp).toDate();
             return d2.compareTo(d1); 
           });
           final targetStock = docs.first;
           transaction.update(targetStock.reference, {
             'remainingAmount': FieldValue.increment(1),
           });
         }

         final studentRef = FirebaseFirestore.instance.collection('students').doc(studentId);
         transaction.update(studentRef, {
           'ticketBalance': FieldValue.increment(1),
         });

         final historyRef = FirebaseFirestore.instance.collection('lessonTransactions').doc();
         final history = LessonTransaction(
           id: historyRef.id,
           studentId: studentId,
           amount: 1, 
           type: 'cancel_refund',
           createdAt: DateTime.now(),
           adminId: null, 
           note: '予約キャンセル返還',
         );
         transaction.set(historyRef, history.toMap());
      });
      
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('キャンセルしました')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('エラー: $e')));
    }
  }

  void _goToTransferSelection(_CalendarItem item) {
    String levelId = item.lesson.levelId; 
    if (levelId.isEmpty) {
      levelId = _groupToLevel[item.lesson.classGroupId] ?? '';
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TransferLessonSelectorScreen(
          student: item.student,
          currentLesson: item.lesson,
          targetLevelId: levelId,
          useTicket: item.internalTicket, 
        ),
      ),
    );
  }

  void _showLessonActionMenu(_CalendarItem item) {
    String levelId = item.lesson.levelId; 
    if (levelId.isEmpty) {
      levelId = _groupToLevel[item.lesson.classGroupId] ?? '';
    }

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.info),
                title: Text('${item.student.firstName}さんのレッスン'),
                subtitle: Text(DateFormat('M/d HH:mm~').format(item.lesson.startTime)),
              ),
              const Divider(),
              
              if (item.status == 'booked') ...[
                ListTile(
                  leading: const Icon(Icons.edit_calendar, color: Colors.green),
                  title: const Text('A. 日程を変更する'),
                  subtitle: const Text('現在の予約をキャンセルし、別の日に変更します'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => TransferLessonSelectorScreen(
                          student: item.student,
                          currentLesson: item.lesson, 
                          currentReservationId: item.reservationId, 
                          targetLevelId: levelId,
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.undo, color: Colors.blue),
                  title: const Text('B. 保留に戻す (予約キャンセル)'),
                  subtitle: const Text('予約をキャンセルし、緑色の状態に戻します'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _cancelReservationToPending(item.reservationId!, item.lesson.id);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.close, color: Colors.red),
                  title: const Text('C. 出席に戻す (全キャンセル)'),
                  subtitle: const Text('振替をやめて、元のレッスンに出席します'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _cancelAllAndReturn(item.reservationId!, item.lesson.id);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.block, color: Colors.grey),
                  title: const Text('D. 振替をやめる (振替なし欠席)'),
                  subtitle: const Text('予約をキャンセルし、振替の権利も放棄します'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _cancelReservationToForfeited(item.reservationId!, item.lesson.id);
                  },
                ),
              ] 
              else if (item.status == 'enrolled') ...[
                ListTile(
                  leading: const Icon(Icons.swap_horiz, color: Colors.blue),
                  title: const Text('① 別の日に振り替える'),
                  subtitle: const Text('すぐに振替先を予約します'),
                  onTap: () {
                    Navigator.pop(context); 
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => TransferLessonSelectorScreen(
                          student: item.student,
                          currentLesson: item.lesson,
                          targetLevelId: levelId,
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.pause_circle_outline, color: Colors.green),
                  title: const Text('② とりあえず欠席 (保留)'),
                  subtitle: const Text('後で振替日を決めます (緑色になります)'),
                  onTap: () async {
                    Navigator.pop(context); 
                    await _registerAbsence(item.lesson, item.student, isForfeited: false);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.block, color: Colors.grey),
                  title: const Text('③ 欠席する (振替不要)'),
                  subtitle: const Text('振替をせず欠席します'),
                  onTap: () async {
                    Navigator.pop(context); 
                    await _registerAbsence(item.lesson, item.student, isForfeited: true);
                  },
                ),
              ]
              else if (item.status == 'ticket_pending') ...[
                ListTile(
                  leading: const Icon(Icons.check_circle_outline, color: Colors.red),
                  title: const Text('A. 振替予約する'),
                  subtitle: const Text('振替先のレッスンを選択します'),
                  onTap: () {
                    Navigator.pop(context);
                    _goToTransferSelection(item);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.undo, color: Colors.blue),
                  title: const Text('C. 出席に戻す (欠席キャンセル)'),
                  subtitle: const Text('欠席を取り消し、出席に戻します'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _undoAbsence(item.lesson, item.student);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.block, color: Colors.grey),
                  title: const Text('D. 振替をやめる (欠席確定)'),
                  subtitle: const Text('振替の権利を放棄して欠席扱いにします'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _changeToForfeited(item.internalTicket!);
                  },
                ),
              ]
              else if (item.status == 'absent_no_transfer') ...[
                const ListTile(title: Text('振替なし欠席として登録されています')),
                ListTile(
                  leading: const Icon(Icons.edit_calendar, color: Colors.green),
                  title: const Text('A. 振替予約する (復活)'),
                  subtitle: const Text('振替権利を復活させて予約します'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _reviveToPending(item.internalTicket!, item.lesson);
                    _goToTransferSelection(item);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.pause_circle_outline, color: Colors.green),
                  title: const Text('B. 振替を保留にする'),
                  subtitle: const Text('緑色の「振替検討中」に戻します'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _reviveToPending(item.internalTicket!, item.lesson);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.undo, color: Colors.blue),
                  title: const Text('C. 出席に戻す (取り消し)'),
                  subtitle: const Text('欠席を取り消し、出席に戻します'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _undoAbsence(item.lesson, item.student);
                  },
                ),
              ]
              else if (item.status == 'ticket_used') ...[
                const ListTile(title: Text('欠席または振替予約済みです')),
                ListTile(
                  leading: const Icon(Icons.undo, color: Colors.blue),
                  title: const Text('C. 出席に戻す (全キャンセル)'),
                  subtitle: const Text('振替先もキャンセルし、出席に戻します'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _undoAbsence(item.lesson, item.student);
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _registerAbsence(LessonInstance lesson, Student student, {required bool isForfeited}) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isForfeited ? '欠席しますか？' : '欠席・保留'),
        content: Text(isForfeited ? '振替なしで欠席します。' : '保留状態(緑色)にします。後で予約できます。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('いいえ')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('はい')),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final lessonRef = FirebaseFirestore.instance.collection('lessonInstances').doc(lesson.id);
        final ticketRef = FirebaseFirestore.instance.collection('tickets').doc();
        
        final lessonSnap = await transaction.get(lessonRef);
        if (lessonSnap.exists) {
          final current = lessonSnap.data()!['currentBookings'] as int? ?? 1;
          transaction.update(lessonRef, {'currentBookings': current > 0 ? current - 1 : 0});
        }

        final lessonDate = lesson.startTime;
        final expiryDate = DateTime(lessonDate.year, lessonDate.month + 2, lessonDate.day); 
        final timeStr = '${DateFormat('HH:mm').format(lesson.startTime)}～${DateFormat('HH:mm').format(lesson.endTime)}';
        
        String levelId = lesson.levelId.isNotEmpty ? lesson.levelId : (_groupToLevel[lesson.classGroupId] ?? '');

        transaction.set(ticketRef, {
          'studentId': student.id,
          'validLevelId': isForfeited ? 'forfeited' : levelId,
          'validLevelName': isForfeited ? '振替なし' : _getCourseAndLevelName(levelId),
          'issueDate': FieldValue.serverTimestamp(),
          'originDate': lessonDate, 
          'originTimeRange': timeStr,
          'expiryDate': expiryDate,
          'isUsed': isForfeited ? true : false, 
          'sourceLessonId': lesson.id, 
        });
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('登録しました')));
    } catch (e) {
      print(e);
    }
  }

  Future<void> _undoAbsence(LessonInstance lesson, Student student) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('出席に戻しますか？'),
        content: const Text('欠席・振替を取り消し、元のレッスンに出席する状態に戻します。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('いいえ')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('はい')),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final ticketSnap = await FirebaseFirestore.instance
          .collection('tickets')
          .where('studentId', isEqualTo: student.id)
          .where('sourceLessonId', isEqualTo: lesson.id)
          .limit(1)
          .get();
      
      if (ticketSnap.docs.isEmpty) return;
      final ticketDoc = ticketSnap.docs.first;
      final reservationId = ticketDoc.data()['usedForReservationId'] as String?;

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final lessonRef = FirebaseFirestore.instance.collection('lessonInstances').doc(lesson.id);
        final lessonSnap = await transaction.get(lessonRef);
        
        DocumentSnapshot<Map<String, dynamic>>? resSnap;
        DocumentSnapshot<Map<String, dynamic>>? destLessonSnap;
        DocumentReference<Map<String, dynamic>>? destRef;

        if (reservationId != null) {
           final resRef = FirebaseFirestore.instance.collection('reservations').doc(reservationId);
           resSnap = await transaction.get(resRef);
           
           if (resSnap.exists && resSnap.data()!['status'] == 'approved') {
             final destId = resSnap.data()!['lessonInstanceId'] as String;
             destRef = FirebaseFirestore.instance.collection('lessonInstances').doc(destId);
             destLessonSnap = await transaction.get(destRef!);
           }
        }

        if (lessonSnap.exists) {
          final current = lessonSnap.data()!['currentBookings'] as int? ?? 0;
          transaction.update(lessonRef, {'currentBookings': current + 1});
        }

        if (resSnap != null && resSnap.exists) {
           transaction.update(resSnap.reference, {'status': 'cancelled'});
           if (destLessonSnap != null && destLessonSnap.exists && destRef != null) {
             final cur = destLessonSnap.data()!['currentBookings'] as int? ?? 1;
             transaction.update(destRef!, {'currentBookings': cur > 0 ? cur - 1 : 0});
           }
        }
        transaction.delete(ticketDoc.reference);
      });
      
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('出席に戻しました')));
    } catch (e) {
      print(e);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('エラー: $e')));
    }
  }

  Future<void> _changeToForfeited(Ticket ticket) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('振替をやめますか？'),
        content: const Text('このレッスンの振替権利を放棄し、「欠席（振替なし）」の状態にします。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('いいえ')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('はい')),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance.collection('tickets').doc(ticket.id).update({
        'validLevelId': 'forfeited',
        'validLevelName': '振替なし',
        'isUsed': true, 
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('変更しました')));
    } catch (e) {
      print(e);
    }
  }

  Future<void> _reviveToPending(Ticket ticket, LessonInstance lesson) async {
    try {
      String levelId = lesson.levelId.isNotEmpty ? lesson.levelId : (_groupToLevel[lesson.classGroupId] ?? '');
      String levelName = _getCourseAndLevelName(levelId);

      await FirebaseFirestore.instance.collection('tickets').doc(ticket.id).update({
        'validLevelId': levelId,
        'validLevelName': levelName,
        'isUsed': false,
      });
    } catch (e) {
      print(e);
    }
  }

  Future<void> _cancelReservationToPending(String reservationId, String lessonId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('予約キャンセル'),
        content: const Text('予約をキャンセルし、振替検討中(緑)に戻しますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('いいえ')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('はい')),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final resRef = FirebaseFirestore.instance.collection('reservations').doc(reservationId);
        final lessonRef = FirebaseFirestore.instance.collection('lessonInstances').doc(lessonId); 
        
        final resSnap = await transaction.get(resRef);
        if (!resSnap.exists) throw Exception("予約が見つかりません");
        final ticketId = resSnap.data()?['usedTicketId'] as String?;
        
        final lessonSnap = await transaction.get(lessonRef);

        transaction.update(resRef, {'status': 'cancelled'});
        
        if (lessonSnap.exists) {
           final current = lessonSnap.data()!['currentBookings'] as int? ?? 1;
           transaction.update(lessonRef, {'currentBookings': current > 0 ? current - 1 : 0});
        }

        if (ticketId != null) {
          final ticketRef = FirebaseFirestore.instance.collection('tickets').doc(ticketId);
          transaction.update(ticketRef, {
            'isUsed': false,
            'usedForReservationId': FieldValue.delete(),
            'usedForDate': FieldValue.delete(),
            'usedForTimeRange': FieldValue.delete(),
          });
        }
      });

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('保留に戻しました。')));
    } catch (e) {
      print(e);
    }
  }

  Future<void> _cancelReservationToForfeited(String reservationId, String lessonId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('振替をやめますか？'),
        content: const Text('予約をキャンセルし、振替の権利も放棄して欠席扱いにします。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('いいえ')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('はい')),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final resRef = FirebaseFirestore.instance.collection('reservations').doc(reservationId);
        final lessonRef = FirebaseFirestore.instance.collection('lessonInstances').doc(lessonId); 
        
        final resSnap = await transaction.get(resRef);
        if (!resSnap.exists) throw Exception("予約が見つかりません");
        final ticketId = resSnap.data()?['usedTicketId'] as String?;
        
        final lessonSnap = await transaction.get(lessonRef);

        transaction.update(resRef, {'status': 'cancelled'});
        
        if (lessonSnap.exists) {
           final current = lessonSnap.data()!['currentBookings'] as int? ?? 1;
           transaction.update(lessonRef, {'currentBookings': current > 0 ? current - 1 : 0});
        }

        if (ticketId != null) {
          final ticketRef = FirebaseFirestore.instance.collection('tickets').doc(ticketId);
          transaction.update(ticketRef, {
            'validLevelId': 'forfeited',
            'validLevelName': '振替なし',
            'isUsed': true,
            'usedForReservationId': FieldValue.delete(),
            'usedForDate': FieldValue.delete(),
            'usedForTimeRange': FieldValue.delete(),
          });
        }
      });

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('振替をキャンセルしました。')));
    } catch (e) {
      print(e);
    }
  }

  Future<void> _cancelAllAndReturn(String reservationId, String lessonId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('出席に戻しますか？'),
        content: const Text('振替予約をキャンセルし、元のレッスンに出席します。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('いいえ')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('はい')),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final resRef = FirebaseFirestore.instance.collection('reservations').doc(reservationId);
        final lessonRef = FirebaseFirestore.instance.collection('lessonInstances').doc(lessonId); 
        
        final resSnap = await transaction.get(resRef);
        final ticketId = resSnap.data()?['usedTicketId'] as String?;
        
        DocumentReference<Map<String, dynamic>>? orgLessonRef;
        DocumentReference<Map<String, dynamic>>? ticketRef;
        DocumentSnapshot<Map<String, dynamic>>? ticketSnap;
        DocumentSnapshot<Map<String, dynamic>>? orgSnap;

        if (ticketId != null) {
          ticketRef = FirebaseFirestore.instance.collection('tickets').doc(ticketId);
          ticketSnap = await transaction.get(ticketRef);
          if (ticketSnap.exists) {
            final orgId = ticketSnap.data()!['sourceLessonId'] as String?;
            if (orgId != null) {
              orgLessonRef = FirebaseFirestore.instance.collection('lessonInstances').doc(orgId);
              orgSnap = await transaction.get(orgLessonRef); 
            }
          }
        }

        final lessonSnap = await transaction.get(lessonRef);

        if (ticketRef != null && ticketSnap != null && ticketSnap.exists) {
            transaction.delete(ticketRef);
        }

        transaction.update(resRef, {'status': 'cancelled'});
        
        if (lessonSnap.exists) {
           final current = lessonSnap.data()!['currentBookings'] as int? ?? 1;
           transaction.update(lessonRef, {'currentBookings': current > 0 ? current - 1 : 0});
        }

        if (orgLessonRef != null && orgSnap != null && orgSnap.exists) {
            final current = orgSnap.data()!['currentBookings'] as int? ?? 0;
            transaction.update(orgLessonRef!, {'currentBookings': current + 1});
        }
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('出席に戻しました')));
    } catch (e) {
      print(e);
    }
  }
}

class _CalendarItem {
  final LessonInstance lesson;
  final Student student;
  final String status; 
  final String? reservationId;
  final Ticket? internalTicket;
  final LessonInstance? destinationLesson;
  final LessonInstance? sourceLesson;
  final ClassGroup? classGroup; 
  
  _CalendarItem({
    required this.lesson, 
    required this.student, 
    required this.status, 
    this.reservationId,
    this.internalTicket,
    this.destinationLesson,
    this.sourceLesson,
    this.classGroup,
  });
}