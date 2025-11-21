import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:atoz_school_app/models/lesson_model.dart';

class ReservationConfirmScreen extends StatefulWidget {
  final LessonInstance lesson;
  final String studentId;

  const ReservationConfirmScreen({
    super.key,
    required this.lesson,
    required this.studentId,
  });

  @override
  State<ReservationConfirmScreen> createState() => _ReservationConfirmScreenState();
}

class _ReservationConfirmScreenState extends State<ReservationConfirmScreen> {
  bool _isSubmitting = false;

  // ■ 予約リクエスト送信処理
  Future<void> _submitRequest() async {
    setState(() => _isSubmitting = true);

    try {
      // reservations コレクションにリクエストを追加
      await FirebaseFirestore.instance.collection('reservations').add({
        'lessonInstanceId': widget.lesson.id,
        'studentId': widget.studentId,
        'requestType': 'transfer', // 振替
        'status': 'pending',       // 承認待ち
        'requestedAt': FieldValue.serverTimestamp(),
        // 講師や管理者が見やすいように冗長なデータも少し持たせておく
        'teacherName': widget.lesson.teacherName,
        'lessonDate': widget.lesson.startTime, 
      });
      
      // LessonInstanceの予約数を+1する（※厳密には承認後に行うべきですが、今回は簡易的にリクエスト時点で枠を確保するロジックとします）
      // 今回は「承認制」なので、予約数は増やさず、あくまでリクエストだけを送ります。
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('振替リクエストを送信しました！承認をお待ちください。')),
        );
        // ホームに戻る
        Navigator.of(context).pop(); 
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('エラー: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('yyyy年M月d日 (E)').format(widget.lesson.startTime);
    final timeStr = '${DateFormat('HH:mm').format(widget.lesson.startTime)} - ${DateFormat('HH:mm').format(widget.lesson.endTime)}';

    return Scaffold(
      appBar: AppBar(title: const Text('振替予約の確認')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('以下のレッスンに振替を申し込みますか？', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 30),
            
            // レッスン情報カード
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
            
            // 送信ボタン
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitRequest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                ),
                child: _isSubmitting 
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('この内容でリクエスト送信', style: TextStyle(fontSize: 18)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}