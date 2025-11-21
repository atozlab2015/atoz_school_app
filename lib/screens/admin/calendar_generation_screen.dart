import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart'; 

class CalendarGenerationScreen extends StatefulWidget {
  const CalendarGenerationScreen({super.key});

  @override
  State<CalendarGenerationScreen> createState() => _CalendarGenerationScreenState();
}

class _CalendarGenerationScreenState extends State<CalendarGenerationScreen> {
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 365));
  String _statusMessage = 'カレンダーの生成準備完了';
  bool _isGenerating = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('年間カレンダー生成'),
        backgroundColor: Colors.pink,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '⚠️ 注意: この操作は既存のレッスンインスタンス（lessonInstancesコレクション）を全て削除し、新たに1年分のデータを生成します。',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            
            // 開始日設定
            ListTile(
              title: const Text('開始日'),
              subtitle: Text(DateFormat('yyyy年M月d日').format(_startDate)),
              trailing: const Icon(Icons.edit_calendar),
              onTap: () => _selectDate(context, true),
            ),
            
            // 終了日設定
            ListTile(
              title: const Text('終了日'),
              subtitle: Text(DateFormat('yyyy年M月d日').format(_endDate)),
              trailing: const Icon(Icons.edit_calendar),
              onTap: () => _selectDate(context, false),
            ),
            
            const SizedBox(height: 30),
            
            // 実行ボタン
            Center(
              child: ElevatedButton.icon(
                icon: _isGenerating
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.auto_stories),
                label: const Text('年間カレンダー生成開始', style: TextStyle(fontSize: 18)),
                onPressed: _isGenerating ? null : _confirmGeneration,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.pink,
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // ステータスメッセージ
            Text('ステータス: $_statusMessage', style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Future<void> _selectDate(BuildContext context, bool isStart) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }
  
  void _confirmGeneration() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('最終確認'),
          content: const Text('既存の全レッスンデータを削除し、新しいカレンダーを生成します。よろしいですか？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _generateCalendar();
              },
              child: const Text('実行する'),
            ),
          ],
        );
      },
    );
  }

  // ▼▼▼ 修正点: 「月曜」「月」どちらにも対応 ▼▼▼
  int _dayOfWeekToInt(String day) {
    if (day.startsWith('月')) return DateTime.monday;
    if (day.startsWith('火')) return DateTime.tuesday;
    if (day.startsWith('水')) return DateTime.wednesday;
    if (day.startsWith('木')) return DateTime.thursday;
    if (day.startsWith('金')) return DateTime.friday;
    if (day.startsWith('土')) return DateTime.saturday;
    if (day.startsWith('日')) return DateTime.sunday;
    return 0;
  }

  Future<void> _generateCalendar() async {
    if (_isGenerating) return;

    setState(() {
      _isGenerating = true;
      _statusMessage = '生成を開始しています... 既存データを削除中...';
    });

    try {
      final firestore = FirebaseFirestore.instance;
      final DateFormat dateOnlyFormat = DateFormat('yyyy-MM-dd');
      
      // A. 既存データの完全削除
      final oldInstances = await firestore.collection('lessonInstances').get();
      for (var doc in oldInstances.docs) {
        await doc.reference.delete();
      }
      
      // B. 全体休日マスタの取得
      // (holidaysコレクションがない場合のエラー回避のため try-catch 内で処理)
      final Set<String> commonHolidayDates = {};
      try {
        final commonHolidaysSnapshot = await firestore.collection('holidays').get();
        for (var doc in commonHolidaysSnapshot.docs) {
          final timestamp = doc.data()['date'] as Timestamp;
          commonHolidayDates.add(dateOnlyFormat.format(timestamp.toDate()));
        }
      } catch (_) {
        // holidaysコレクションがなくても続行
      }
      
      // C. クラス枠の取得
      final groupsSnapshot = await firestore.collection('groups').get();
      WriteBatch newBatch = firestore.batch(); 
      int instanceCount = 0;

      if (groupsSnapshot.docs.isEmpty) {
        _statusMessage = 'エラー: クラス枠が一つも登録されていません。マスタ設定を確認してください。';
        return;
      }
      
      // D. レベル別例外のキャッシュ
      Map<String, Set<String>> levelExceptionsCache = {};

      for (var groupDoc in groupsSnapshot.docs) {
        final groupData = groupDoc.data();
        final classGroupId = groupDoc.id;
        final levelId = groupData['levelId'] as String;
        
        // 例外取得
        if (!levelExceptionsCache.containsKey(levelId)) {
          // classExceptionsコレクションがない場合も想定して try-catch
          try {
            final exceptionsSnapshot = await firestore
                .collection('classExceptions') 
                .where('levelId', isEqualTo: levelId)
                .get();
                
            final Set<String> exceptionDates = {};
            for (var doc in exceptionsSnapshot.docs) {
              final timestamp = doc.data()['date'] as Timestamp;
              exceptionDates.add(dateOnlyFormat.format(timestamp.toDate()));
            }
            levelExceptionsCache[levelId] = exceptionDates;
          } catch (_) {
            levelExceptionsCache[levelId] = {};
          }
        }
        
        final Set<String> classExceptionDates = levelExceptionsCache[levelId]!;

        final dayOfWeekName = groupData['dayOfWeek'] as String;
        final targetWeekday = _dayOfWeekToInt(dayOfWeekName);

        if (targetWeekday == 0) continue; // 曜日不明ならスキップ

        DateTime currentDate = _startDate;
        while (currentDate.isBefore(_endDate.add(const Duration(days: 1)))) {
          final dateString = dateOnlyFormat.format(currentDate);

          if (currentDate.weekday == targetWeekday) {
            // 休日チェック
            if (commonHolidayDates.contains(dateString)) {
                currentDate = currentDate.add(const Duration(days: 1));
                continue; 
            }
            if (classExceptionDates.contains(dateString)) {
                currentDate = currentDate.add(const Duration(days: 1));
                continue; 
            }
            
            // ▼▼▼ 修正点: 時間を文字列 "18:00" からパースして計算 ▼▼▼
            final startTimeStr = groupData['startTime'] as String; // "18:00"
            final parts = startTimeStr.split(':');
            final hour = int.parse(parts[0]);
            final minute = int.parse(parts[1]);

            final lessonStartTime = DateTime(
              currentDate.year, currentDate.month, currentDate.day, hour, minute,
            );
            
            final duration = groupData['durationMinutes'] as int;
            final lessonEndTime = lessonStartTime.add(Duration(minutes: duration)); 
            
            final lessonInstance = {
              'classGroupId': classGroupId,
              'levelId': levelId,
              'teacherName': groupData['teacherName'],
              'dayOfWeek': dayOfWeekName, 
              'startTime': lessonStartTime,
              'endTime': lessonEndTime,
              'capacity': groupData['capacity'],
              'currentBookings': 0, 
              'isCancelled': false,
            };

            final newInstanceRef = firestore.collection('lessonInstances').doc();
            newBatch.set(newInstanceRef, lessonInstance);
            instanceCount++;
          }
          
          currentDate = currentDate.add(const Duration(days: 1));
        }
      }

      // バッチ実行
      await newBatch.commit();
      
      setState(() {
        _statusMessage = '✅ 成功！$instanceCount 件のレッスンインスタンスを生成しました。';
      });

    } catch (e) {
      setState(() {
        _statusMessage = '🚨 エラーが発生しました: $e';
      });
      print('Calendar Generation Error: $e');
    } finally {
      setState(() {
        _isGenerating = false;
      });
    }
  }
}