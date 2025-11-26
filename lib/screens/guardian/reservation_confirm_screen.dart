import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:atoz_school_app/models/lesson_model.dart';
import 'package:atoz_school_app/models/ticket_model.dart';

class ReservationConfirmScreen extends StatefulWidget {
  final LessonInstance lesson; 
  final String studentId;
  
  final String? originalLessonId;       
  final String? originalReservationId;  
  final Ticket? ticketToUse; 
  final DateTime? originDateForDirectTransfer; 
  final LessonInstance? sourceLesson;

  const ReservationConfirmScreen({
    super.key,
    required this.lesson,
    required this.studentId,
    this.originalLessonId,
    this.originalReservationId,
    this.ticketToUse, 
    this.originDateForDirectTransfer,
    this.sourceLesson,
  });

  @override
  State<ReservationConfirmScreen> createState() => _ReservationConfirmScreenState();
}

class _ReservationConfirmScreenState extends State<ReservationConfirmScreen> {
  bool _isSubmitting = false;

  Future<void> _submitRequest() async {
    setState(() => _isSubmitting = true);

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final newLessonRef = FirebaseFirestore.instance.collection('lessonInstances').doc(widget.lesson.id);
        final newReservationRef = FirebaseFirestore.instance.collection('reservations').doc();
        
        final newLessonSnap = await transaction.get(newLessonRef);
        if (!newLessonSnap.exists) throw Exception("対象レッスンが見つかりません");
        
        final currentBookings = newLessonSnap.data()!['currentBookings'] as int? ?? 0;
        final capacity = newLessonSnap.data()!['capacity'] as int? ?? 0;
        if (currentBookings >= capacity) throw Exception("満席のため予約できません");

        if (widget.originalReservationId != null) {
          final oldResRef = FirebaseFirestore.instance.collection('reservations').doc(widget.originalReservationId);
          final oldResSnap = await transaction.get(oldResRef);
          
          if (oldResSnap.exists && oldResSnap.data()!['status'] == 'approved') {
             transaction.update(oldResRef, {'status': 'cancelled'});
             
             final oldLessonId = oldResSnap.data()!['lessonInstanceId'] as String;
             final oldLessonRef = FirebaseFirestore.instance.collection('lessonInstances').doc(oldLessonId);
             transaction.update(oldLessonRef, {'currentBookings': FieldValue.increment(-1)});
          }
        } 
        else if (widget.sourceLesson != null) {
           final srcRef = FirebaseFirestore.instance.collection('lessonInstances').doc(widget.sourceLesson!.id);
           final srcSnap = await transaction.get(srcRef);
           if (srcSnap.exists) {
             final cur = srcSnap.data()!['currentBookings'] as int? ?? 1;
             transaction.update(srcRef, {'currentBookings': cur > 0 ? cur - 1 : 0});
           }
        }

        // ★重要: チケット管理 (新規作成 or 更新)
        DocumentReference ticketRef;
        
        if (widget.ticketToUse != null) {
          ticketRef = FirebaseFirestore.instance.collection('tickets').doc(widget.ticketToUse!.id);
        } else {
          // 直接振替でも必ずチケットを作る
          ticketRef = FirebaseFirestore.instance.collection('tickets').doc();
          final originDate = widget.originDateForDirectTransfer ?? DateTime.now();
          final expiryDate = DateTime(originDate.year, originDate.month + 2, originDate.day);
          final timeStr = widget.sourceLesson != null 
              ? '${DateFormat('HH:mm').format(widget.sourceLesson!.startTime)}～${DateFormat('HH:mm').format(widget.sourceLesson!.endTime)}'
              : '';
          
          transaction.set(ticketRef, {
            'studentId': widget.studentId,
            'validLevelId': widget.lesson.levelId,
            'validLevelName': '振替済み', 
            'issueDate': FieldValue.serverTimestamp(),
            'originDate': originDate,
            'expiryDate': expiryDate,
            'originTimeRange': timeStr,
            'sourceLessonId': widget.originalLessonId, // ここが振替元との紐づけになる
          });
        }

        final timeRange = '${DateFormat('HH:mm').format(widget.lesson.startTime)}～${DateFormat('HH:mm').format(widget.lesson.endTime)}';
        transaction.update(ticketRef, {
          'isUsed': true, 
          'usedForReservationId': newReservationRef.id, 
          'usedForDate': widget.lesson.startTime,
          'usedForTimeRange': timeRange,
        });

        transaction.set(newReservationRef, {
          'lessonInstanceId': widget.lesson.id,
          'studentId': widget.studentId,
          'requestType': 'transfer_simple',
          'status': 'approved',
          'requestedAt': FieldValue.serverTimestamp(),
          'teacherName': widget.lesson.teacherName,
          'lessonDate': widget.lesson.startTime,
          'originalLessonId': widget.originalLessonId, 
          'usedTicketId': ticketRef.id, 
        });

        transaction.update(newLessonRef, {
          'currentBookings': currentBookings + 1,
        });
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('振替予約が完了しました！')));
        Navigator.of(context).pop(); 
        Navigator.of(context).pop(); 
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('エラー: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ... (前回のコードと同じUI部分) ...
    // ファイル全体を貼り付けるため省略せず記述します
    final dateStr = DateFormat('yyyy年M月d日 (E)').format(widget.lesson.startTime);
    final timeStr = '${DateFormat('HH:mm').format(widget.lesson.startTime)} - ${DateFormat('HH:mm').format(widget.lesson.endTime)}';

    return Scaffold(
      appBar: AppBar(title: const Text('振替内容の確認')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             Container(
               margin: const EdgeInsets.only(bottom: 20),
               padding: const EdgeInsets.all(12),
               decoration: BoxDecoration(color: Colors.orange.shade50, border: Border.all(color: Colors.orange)),
               child: const Row(
                 children: [
                   Icon(Icons.swap_horiz, color: Colors.orange),
                   SizedBox(width: 10),
                   Expanded(child: Text('以下の日程に振替予約を確定します。', style: TextStyle(fontWeight: FontWeight.bold))),
                 ],
               ),
             ),

            Card(
              elevation: 4,
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.calendar_today, color: Colors.blue),
                      title: Text(dateStr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.access_time, color: Colors.blue),
                      title: Text(timeStr, style: const TextStyle(fontSize: 18)),
                    ),
                    ListTile(
                      leading: const Icon(Icons.person, color: Colors.blue),
                      title: Text('${widget.lesson.teacherName} 先生', style: const TextStyle(fontSize: 18)),
                    ),
                  ],
                ),
              ),
            ),
            
            const Spacer(),
            
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitRequest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                ),
                child: _isSubmitting 
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('振替予約を確定する', style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}