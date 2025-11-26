import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import 'package:atoz_school_app/models/lesson_model.dart';
import 'package:atoz_school_app/models/student_model.dart';
import 'package:atoz_school_app/models/ticket_model.dart';
import 'reservation_confirm_screen.dart';

class TransferLessonSelectorScreen extends StatefulWidget {
  final Student student;
  final LessonInstance currentLesson; // 振替元のレッスン（またはチケット用のダミー）
  final String? currentReservationId; // 予約の場合はID
  final String targetLevelId;       
  final Ticket? useTicket;          // 使用するチケット（内部管理用）

  const TransferLessonSelectorScreen({
    super.key,
    required this.student,
    required this.currentLesson,
    this.currentReservationId,
    required this.targetLevelId,
    this.useTicket, 
  });

  @override
  State<TransferLessonSelectorScreen> createState() => _TransferLessonSelectorScreenState();
}

class _TransferLessonSelectorScreenState extends State<TransferLessonSelectorScreen> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  
  Map<String, List<LessonInstance>> _availableLessons = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _fetchAvailableLessons();
  }

  // 曜日数値を文字列に変換するヘルパー
  String _getDayOfWeekString(int weekday) {
    const days = ['', '月曜', '火曜', '水曜', '木曜', '金曜', '土曜', '日曜'];
    if (weekday >= 1 && weekday <= 7) return days[weekday];
    return '';
  }

  Future<void> _fetchAvailableLessons() async {
    final now = DateTime.now();
    
    // 1. 基準日の決定
    DateTime originDate = widget.useTicket?.originDate ?? widget.useTicket?.issueDate ?? widget.currentLesson.startTime;
    
    // 2. 検索範囲 (前後2ヶ月)
    DateTime minDate = originDate.subtract(const Duration(days: 60));
    if (minDate.isBefore(now)) minDate = now;
    DateTime maxDate = originDate.add(const Duration(days: 60));

    try {
      // ==============================================
      // Step A: 生徒のスケジュール情報を取得
      // ==============================================
      
      // A-1. 既存の予約 (重複NG)
      final reservationSnap = await FirebaseFirestore.instance
          .collection('reservations')
          .where('studentId', isEqualTo: widget.student.id)
          .where('status', whereIn: ['approved', 'pending'])
          .where('lessonDate', isGreaterThan: minDate)
          .get();

      final Set<String> bookedTimeSlots = {};
      for (var doc in reservationSnap.docs) {
        final date = (doc.data()['lessonDate'] as Timestamp).toDate();
        bookedTimeSlots.add(DateFormat('yyyy-MM-dd HH:mm').format(date));
      }

      // A-2. 所属している定期クラス枠 (重複NG)
      // ★修正: チケット利用時でも必ずチェックする
      final Set<String> myRegularSlots = {}; // "月曜 16:25" 形式
      if (widget.student.enrolledGroupIds.isNotEmpty) {
        // Firestoreの 'in' クエリ上限対策 (30件まで)
        final groupsSnap = await FirebaseFirestore.instance
            .collection('groups')
            .where(FieldPath.documentId, whereIn: widget.student.enrolledGroupIds.take(30).toList())
            .get();
        
        for (var doc in groupsSnap.docs) {
          final data = doc.data();
          final day = data['dayOfWeek'] as String;
          final time = data['startTime'] as String; // "16:25"
          myRegularSlots.add('$day $time');
        }
      }

      // ==============================================
      // Step B: 振替先レッスンの検索
      // ==============================================
      
      final snapshot = await FirebaseFirestore.instance
          .collection('lessonInstances')
          .where('levelId', isEqualTo: widget.targetLevelId)
          .where('startTime', isGreaterThan: minDate)
          .orderBy('startTime')
          .limit(500) 
          .get();

      final Map<String, List<LessonInstance>> newItems = {};
      final dayFormatter = DateFormat('yyyy-MM-dd');
      final dateTimeFormatter = DateFormat('yyyy-MM-dd HH:mm');
      final timeFormatter = DateFormat('HH:mm');

      for (var doc in snapshot.docs) {
        final lesson = LessonInstance.fromMap(doc.data(), doc.id);
        
        // 範囲外除外
        if (lesson.startTime.isAfter(maxDate)) continue;

        // 自分自身（振替元）は除外
        if (lesson.id == widget.currentLesson.id) continue;
        
        // チケットの元になったレッスンIDがあればそれも除外
        if (widget.useTicket?.sourceLessonId == lesson.id) continue;

        final lessonDateTimeKey = dateTimeFormatter.format(lesson.startTime);

        // B-1. 既存の予約と被るなら除外
        if (bookedTimeSlots.contains(lessonDateTimeKey)) continue;

        // B-2. 定期クラスと被るかチェック
        // lesson.dayOfWeek がモデルにないため、startTimeから生成してチェック
        final lessonDayStr = _getDayOfWeekString(lesson.startTime.weekday);
        final lessonTimeStr = timeFormatter.format(lesson.startTime);
        final regularKey = '$lessonDayStr $lessonTimeStr'; // 例: "月曜 16:25"

        // ★修正: 定期クラスの時間帯なら、例外なく除外する
        if (myRegularSlots.contains(regularKey)) {
          continue; 
        }

        // B-3. 定員チェック
        if (lesson.currentBookings < lesson.capacity) {
          final dateString = dayFormatter.format(lesson.startTime);
          if (newItems[dateString] == null) newItems[dateString] = [];
          newItems[dateString]!.add(lesson);
        }
      }

      if (mounted) {
        setState(() {
          _availableLessons = newItems;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Search Error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<LessonInstance> _getEventsForDay(DateTime day) {
    final String dateString = DateFormat('yyyy-MM-dd').format(day);
    return _availableLessons[dateString] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    final events = _getEventsForDay(_selectedDay ?? _focusedDay);
    
    final now = DateTime.now();
    // 基準日
    DateTime originDate = widget.useTicket?.originDate ?? widget.useTicket?.issueDate ?? widget.currentLesson.startTime;
    
    final firstDay = originDate.subtract(const Duration(days: 60)).isBefore(now) ? now : originDate.subtract(const Duration(days: 60));
    final lastDay = originDate.add(const Duration(days: 60));

    String guideMessage = '元の予定: ${DateFormat('M/d HH:mm').format(widget.currentLesson.startTime)} を欠席して...\n↓\n新しい振替先を選んでください';
    if (widget.useTicket != null) {
      guideMessage = 'チケットを使って予約します。\nご希望の日時を選んでください。';
    }
    if (widget.currentReservationId != null) {
       guideMessage = '現在の予約をキャンセルして...\n↓\n新しい日程を選んでください';
    }
    guideMessage += '\n(前後2ヶ月以内の空きクラスを表示)';

    return Scaffold(
      appBar: AppBar(
        title: const Text('振替先の選択'),
        backgroundColor: Colors.green.shade700,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.grey.shade200,
            width: double.infinity,
            child: Text(
              guideMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14),
            ),
          ),
          TableCalendar(
            firstDay: firstDay, 
            lastDay: lastDay,   
            focusedDay: _focusedDay.isBefore(firstDay) ? firstDay : _focusedDay,
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
            onPageChanged: (focusedDay) => _focusedDay = focusedDay,
            calendarStyle: const CalendarStyle(
              todayDecoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle),
              selectedDecoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle),
              markerDecoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle),
            ),
            headerStyle: const HeaderStyle(
              formatButtonVisible: true, 
              titleCentered: true,
              formatButtonShowsNext: false, 
            ),
            availableCalendarFormats: const {
              CalendarFormat.month: '月表示',
              CalendarFormat.twoWeeks: '2週間',
              CalendarFormat.week: '週表示',
            },
            onFormatChanged: (format) {
               setState(() {
                 _calendarFormat = format;
               });
            },
          ),
          const Divider(),
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : events.isEmpty 
                ? const Center(child: Text('選択した日に予約可能なレッスンはありません'))
                : ListView.builder(
                    itemCount: events.length,
                    itemBuilder: (context, index) {
                      final lesson = events[index];
                      final isSpotLeft = (lesson.capacity - lesson.currentBookings) < 3; 

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: ListTile(
                          leading: const Icon(Icons.check_circle_outline, color: Colors.green),
                          title: Text(
                            '${DateFormat('HH:mm').format(lesson.startTime)}~ ${lesson.teacherName}先生',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text('空き: ${lesson.capacity - lesson.currentBookings}名'),
                          trailing: isSpotLeft 
                              ? const Chip(label: Text('残りわずか', style: TextStyle(color: Colors.white, fontSize: 10)), backgroundColor: Colors.orange)
                              : const Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: () {
                            // 予約確認画面へ
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ReservationConfirmScreen(
                                  lesson: lesson,
                                  studentId: widget.student.id,
                                  // チケット利用かどうかにかかわらず、元のレッスンIDを渡す
                                  originalLessonId: widget.useTicket != null 
                                      ? widget.useTicket!.sourceLessonId // 保留からの場合はチケット内の元ID
                                      : widget.currentLesson.id,         // 直接振替の場合は今のレッスンID
                                  originalReservationId: widget.currentReservationId,
                                  ticketToUse: widget.useTicket,
                                  originDateForDirectTransfer: widget.currentLesson.startTime, 
                                  sourceLesson: widget.currentLesson,
                                ),
                              ),
                            );
                          },
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