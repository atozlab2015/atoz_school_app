import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../models/student_model.dart';
import '../../models/class_model.dart';
import '../../models/lesson_model.dart';
import '../../models/ticket_stock_model.dart';
import '../../models/reservation_model.dart';
import '../../models/lesson_transaction_model.dart'; // ★追加

class GuardianBookingScreen extends StatefulWidget {
  final Student student;
  final ClassGroup enrolledClass; 

  const GuardianBookingScreen({
    Key? key,
    required this.student,
    required this.enrolledClass,
  }) : super(key: key);

  @override
  _GuardianBookingScreenState createState() => _GuardianBookingScreenState();
}

class _GuardianBookingScreenState extends State<GuardianBookingScreen> {
  bool _isLoading = true;
  int _totalTickets = 0; 
  List<LessonInstance> _availableLessons = [];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      // 1. チケット在庫の確認
      final stockSnapshot = await FirebaseFirestore.instance
          .collection('ticket_stocks')
          .where('studentId', isEqualTo: widget.student.id)
          .where('status', isEqualTo: 'active')
          .get();

      int count = 0;
      final now = DateTime.now();
      
      // 今開いている画面の対象レベル
      final targetLevelId = widget.enrolledClass.levelId;

      for (var doc in stockSnapshot.docs) {
        final stock = TicketStock.fromMap(doc.data(), doc.id);
        
        // ★修正: 期限チェック ＆ レベルIDチェック
        // (validLevelIdがnullの場合は、昔のチケットかもしれないので一旦許可するか、厳密に弾くか。今回は厳密に弾きます)
        bool isLevelMatch = stock.validLevelId == targetLevelId;
        
        if (stock.expiryDate.isAfter(now) && stock.remainingAmount > 0 && isLevelMatch) {
          count += stock.remainingAmount;
        }
      }

      // 予約済みのレッスンIDを取得（除外用）
      final myReservationsSnap = await FirebaseFirestore.instance
          .collection('reservations')
          .where('studentId', isEqualTo: widget.student.id)
          .where('status', isEqualTo: 'approved')
          .get();
      
      final bookedLessonIds = myReservationsSnap.docs
          .map((doc) => doc['lessonInstanceId'] as String)
          .toSet();

      // 2. 予約可能なレッスンの取得
      final lessonSnapshot = await FirebaseFirestore.instance
          .collection('lessonInstances')
          .where('levelId', isEqualTo: widget.enrolledClass.levelId)
          .where('startTime', isGreaterThan: Timestamp.fromDate(now))
          .orderBy('startTime')
          .limit(50)
          .get();

      // クラス情報の取得
      final Set<String> groupIds = lessonSnapshot.docs
          .map((doc) => doc['classGroupId'] as String)
          .toSet();

      Map<String, ClassGroup> groupMap = {};
      
      if (groupIds.isNotEmpty) {
        final classGroupsSnap = await FirebaseFirestore.instance.collection('classGroups').get();
        for (var doc in classGroupsSnap.docs) {
          if (groupIds.contains(doc.id)) {
            groupMap[doc.id] = ClassGroup.fromMap(doc.data(), doc.id);
          }
        }
        final groupsSnap = await FirebaseFirestore.instance.collection('groups').get();
        for (var doc in groupsSnap.docs) {
          if (groupIds.contains(doc.id) && !groupMap.containsKey(doc.id)) {
            groupMap[doc.id] = ClassGroup.fromMap(doc.data(), doc.id);
          }
        }
      }

      final List<LessonInstance> filteredLessons = [];
      for (var doc in lessonSnapshot.docs) {
        final lesson = LessonInstance.fromMap(doc.data(), doc.id);
        
        if (bookedLessonIds.contains(lesson.id)) continue;

        final group = groupMap[lesson.classGroupId];
        if (group != null && group.bookingType == 'flexible') {
          filteredLessons.add(lesson);
        }
      }

      setState(() {
        _totalTickets = count;
        _availableLessons = filteredLessons;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error: $e');
      setState(() => _isLoading = false);
    }
  }

  // 予約処理 (Transaction)
  Future<void> _processBooking(LessonInstance lesson) async {
    if (_totalTickets <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('チケットがありません')));
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('予約確認'),
        content: Text(
          '${DateFormat('M/d HH:mm').format(lesson.startTime)}〜\n'
          'チケットを1枚消費して予約しますか？\n'
          '(残りチケット: $_totalTickets枚)'
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('予約する')),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        // 1. レッスン確認
        final lessonRef = FirebaseFirestore.instance.collection('lessonInstances').doc(lesson.id);
        final lessonSnap = await transaction.get(lessonRef);
        if (!lessonSnap.exists) throw Exception("レッスンが見つかりません");
        
        final currentBookings = lessonSnap.data()!['currentBookings'] as int? ?? 0;
        final capacity = lessonSnap.data()!['capacity'] as int? ?? 0;
        
        if (currentBookings >= capacity) throw Exception("満席のため予約できません");

        // 2. 在庫取得
        final stockSnapshot = await FirebaseFirestore.instance
            .collection('ticket_stocks')
            .where('studentId', isEqualTo: widget.student.id)
            .where('status', isEqualTo: 'active')
            .get(); 

        final now = DateTime.now();
        final targetLevelId = widget.enrolledClass.levelId; // ★ターゲットレベル

        final validStocks = stockSnapshot.docs
            .map((doc) => TicketStock.fromMap(doc.data(), doc.id))
            .where((s) {
              // ★修正: 期限内 かつ 残数あり かつ レベル一致
              return s.remainingAmount > 0 && 
                     s.expiryDate.isAfter(now) && 
                     s.validLevelId == targetLevelId;
            })
            .toList();

        if (validStocks.isEmpty) throw Exception("このクラスで利用可能なチケットがありません");

        validStocks.sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
        
        final targetStockId = validStocks.first.id;
        final targetStockRef = FirebaseFirestore.instance.collection('ticket_stocks').doc(targetStockId);
        
        // 再読み込みとロック
        final freshStockSnap = await transaction.get(targetStockRef);
        if (!freshStockSnap.exists) throw Exception("在庫データエラー");
        
        final currentRemaining = freshStockSnap.data()!['remainingAmount'] as int? ?? 0;
        if (currentRemaining <= 0) throw Exception("チケット消費エラー");

        // 3. 生徒データのチケット合計残高を更新 (表示用キャッシュ)
        final studentRef = FirebaseFirestore.instance.collection('students').doc(widget.student.id);
        final studentSnap = await transaction.get(studentRef);
        final currentTotal = studentSnap.data()?['ticketBalance'] as int? ?? 0;

        // 4. 書き込み実行
        // A. 在庫消費
        transaction.update(targetStockRef, {
          'remainingAmount': currentRemaining - 1,
          'status': (currentRemaining - 1) == 0 ? 'completed' : 'active',
        });

        // B. 予約作成
        final reservationRef = FirebaseFirestore.instance.collection('reservations').doc();
        final reservation = Reservation(
          id: reservationRef.id,
          lessonInstanceId: lesson.id,
          studentId: widget.student.id,
          requestType: 'booking',
          status: 'approved',
          requestedAt: Timestamp.now(),
        );
        transaction.set(reservationRef, reservation.toMap());
        
        // C. レッスン人数更新
        transaction.update(lessonRef, {
          'currentBookings': currentBookings + 1,
        });

        // D. 生徒合計残高更新
        transaction.update(studentRef, {
          'ticketBalance': currentTotal > 0 ? currentTotal - 1 : 0,
        });

        // ★追加: E. 履歴(ログ)作成
        final historyRef = FirebaseFirestore.instance.collection('lessonTransactions').doc();
        final history = LessonTransaction(
          id: historyRef.id,
          studentId: widget.student.id,
          amount: -1, // 消費
          type: 'use',
          createdAt: DateTime.now(),
          adminId: null, // 本人操作
          note: '予約: ${lesson.teacherName}先生 ${DateFormat('MM/dd HH:mm').format(lesson.startTime)}',
        );
        transaction.set(historyRef, history.toMap());
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('予約が完了しました！')));
      Navigator.pop(context);

    } catch (e) {
      debugPrint('Booking Error: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('エラー: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('レッスンの予約')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: Colors.orange[50],
                  child: Column(
                    children: [
                      const Text('所持チケット (有効期限内)', style: TextStyle(color: Colors.grey)),
                      Text(
                        '$_totalTickets 枚',
                        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.orange),
                      ),
                      if (_totalTickets == 0)
                        const Text('※チケットがないため予約できません', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _availableLessons.isEmpty
                      ? const Center(child: Text('予約可能なレッスンが見つかりません\n(予約制クラスの日程を確認してください)'))
                      : ListView.builder(
                          itemCount: _availableLessons.length,
                          itemBuilder: (context, index) {
                            final lesson = _availableLessons[index];
                            final dateFormat = DateFormat('MM/dd(E) HH:mm', 'ja');
                            final isFull = lesson.currentBookings >= lesson.capacity;

                            return Card(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: ListTile(
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isFull ? Colors.grey[300] : Colors.blue[50],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    dateFormat.format(lesson.startTime),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: isFull ? Colors.grey : Colors.blue[800],
                                    ),
                                  ),
                                ),
                                title: Text(lesson.teacherName + '先生'),
                                subtitle: Text('予約: ${lesson.currentBookings} / ${lesson.capacity} 名'),
                                trailing: ElevatedButton(
                                  onPressed: (_totalTickets > 0 && !isFull) 
                                      ? () => _processBooking(lesson) 
                                      : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isFull ? Colors.grey : Colors.indigo,
                                    foregroundColor: Colors.white,
                                  ),
                                  child: Text(isFull ? '満席' : '予約'),
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