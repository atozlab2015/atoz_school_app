import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../models/class_model.dart'; // モデルのパスが合っているか確認してください

class ClassGroupFormScreen extends StatefulWidget {
  final ClassGroup? classGroup; // 編集時はこれが入る
  
  // ★新規作成用に親IDを受け取れるように追加
  final String? subjectId;
  final String? courseId;
  final String? levelId;

  const ClassGroupFormScreen({
    Key? key, 
    this.classGroup,
    this.subjectId,
    this.courseId,
    this.levelId,
  }) : super(key: key);

  @override
  _ClassGroupFormScreenState createState() => _ClassGroupFormScreenState();
}

class _ClassGroupFormScreenState extends State<ClassGroupFormScreen> {
  final _formKey = GlobalKey<FormState>();

  // 入力用変数
  String _teacherName = '';
  int _dayOfWeek = 1; // 1=月曜日
  TimeOfDay _startTime = const TimeOfDay(hour: 10, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 10, minute: 50);
  int _capacity = 4;
  
  // ★重要: 予約タイプ (fixed=固定制, flexible=予約制)
  String _bookingType = 'fixed'; 

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.classGroup != null) {
      // 編集モード: 既存データから読み込み
      final c = widget.classGroup!;
      _teacherName = c.teacherName;
      
      // dayOfWeekがStringで保存されているかintかによる変換（モデルに合わせて調整）
      // ここでは汎用的に int.tryParse で対応
      _dayOfWeek = int.tryParse(c.dayOfWeek) ?? 1; 
      
      _capacity = c.capacity;
      _bookingType = c.bookingType; // ★読み込み

      // 時間のパース (HH:mm -> TimeOfDay)
      final startParts = c.startTime.split(':');
      if (startParts.length == 2) {
        _startTime = TimeOfDay(hour: int.parse(startParts[0]), minute: int.parse(startParts[1]));
        
        // 終了時間は durationMinutes から計算する
        final startDt = DateTime(2020, 1, 1, _startTime.hour, _startTime.minute);
        final endDt = startDt.add(Duration(minutes: c.durationMinutes));
        _endTime = TimeOfDay(hour: endDt.hour, minute: endDt.minute);
      }
    }
  }

  Future<void> _saveClassGroup() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final docRef = widget.classGroup == null
          ? FirebaseFirestore.instance.collection('classGroups').doc()
          : FirebaseFirestore.instance.collection('classGroups').doc(widget.classGroup!.id);

      final startTimeStr = '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}';
      
      // 終了時間を計算してDuration(分数)を出す
      final startDt = DateTime(2020, 1, 1, _startTime.hour, _startTime.minute);
      final endDt = DateTime(2020, 1, 1, _endTime.hour, _endTime.minute);
      // 日またぎの計算（終了が開始より前なら翌日扱い）
      DateTime adjustedEndDt = endDt;
      if (endDt.isBefore(startDt)) {
        adjustedEndDt = endDt.add(const Duration(days: 1));
      }
      final duration = adjustedEndDt.difference(startDt).inMinutes;

      final newGroup = ClassGroup(
        id: docRef.id,
        // ★修正: 編集時は既存ID、新規時は渡されたIDを使う（nullチェック付き）
        subjectId: widget.classGroup?.subjectId ?? widget.subjectId ?? '',
        courseId: widget.classGroup?.courseId ?? widget.courseId ?? '',
        levelId: widget.classGroup?.levelId ?? widget.levelId ?? '',
        
        teacherName: _teacherName,
        dayOfWeek: _dayOfWeek.toString(), // モデルに合わせてString変換
        startTime: startTimeStr,
        durationMinutes: duration,
        capacity: _capacity,
        
        // ★重要: ここでタイプを保存
        bookingType: _bookingType, 
        
        // その他デフォルト値（フォームにない項目）
        spotLimitType: widget.classGroup?.spotLimitType ?? 'unlimited',
        monthlyLimitCount: widget.classGroup?.monthlyLimitCount ?? 0,
        validFrom: widget.classGroup?.validFrom,
        validTo: widget.classGroup?.validTo,
      );

      await docRef.set(newGroup.toMap());

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('クラス枠を保存しました')));
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('エラー: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 時間選択ピッカー
  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
          // 開始時間が変わったら、終了時間を自動で50分後にする（便利機能）
          final startDt = DateTime(2020, 1, 1, _startTime.hour, _startTime.minute);
          final endDt = startDt.add(const Duration(minutes: 50));
          _endTime = TimeOfDay(hour: endDt.hour, minute: endDt.minute);
        } else {
          _endTime = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.classGroup == null ? 'クラス枠の新規作成' : 'クラス枠の編集')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 講師名
              TextFormField(
                initialValue: _teacherName,
                decoration: const InputDecoration(labelText: '担当講師名'),
                onChanged: (val) => _teacherName = val,
                validator: (val) => val == null || val.isEmpty ? '講師名は必須です' : null,
              ),
              const SizedBox(height: 16),
              
              // 曜日選択
              DropdownButtonFormField<int>(
                value: _dayOfWeek,
                decoration: const InputDecoration(labelText: '曜日'),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('月曜日')),
                  DropdownMenuItem(value: 2, child: Text('火曜日')),
                  DropdownMenuItem(value: 3, child: Text('水曜日')),
                  DropdownMenuItem(value: 4, child: Text('木曜日')),
                  DropdownMenuItem(value: 5, child: Text('金曜日')),
                  DropdownMenuItem(value: 6, child: Text('土曜日')),
                  DropdownMenuItem(value: 7, child: Text('日曜日')),
                ],
                onChanged: (val) => setState(() => _dayOfWeek = val!),
              ),
              const SizedBox(height: 16),

              // 時間選択
              Row(
                children: [
                  Expanded(
                    child: ListTile(
                      title: const Text('開始'),
                      subtitle: Text(_startTime.format(context), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      onTap: () => _pickTime(true),
                    ),
                  ),
                  const Icon(Icons.arrow_forward),
                  Expanded(
                    child: ListTile(
                      title: const Text('終了'),
                      subtitle: Text(_endTime.format(context), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      onTap: () => _pickTime(false),
                    ),
                  ),
                ],
              ),
              
              const Divider(),
              // ★追加: 予約タイプの選択
              const Text('クラスタイプ (重要)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              RadioListTile<String>(
                title: const Text('固定制 (Pattern A)'),
                subtitle: const Text('毎週決まった生徒が出席します。\n（例：通常の英会話クラス）'),
                value: 'fixed',
                groupValue: _bookingType,
                onChanged: (val) => setState(() => _bookingType = val!),
                activeColor: Colors.indigo,
              ),
              RadioListTile<String>(
                title: const Text('予約・チケット制 (Pattern B)'),
                subtitle: const Text('所属生徒が都度予約して出席します。チケットを消費します。\n（例：回数制ヨガ、振替自由クラス）'),
                value: 'flexible',
                groupValue: _bookingType,
                onChanged: (val) => setState(() => _bookingType = val!),
                activeColor: Colors.orange,
              ),
              const Divider(),

              // 定員
              TextFormField(
                initialValue: _capacity.toString(),
                decoration: const InputDecoration(labelText: '定員 (名)'),
                keyboardType: TextInputType.number,
                onChanged: (val) => _capacity = int.tryParse(val) ?? 4,
              ),
              const SizedBox(height: 30),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.save),
                  label: _isLoading 
                    ? const CircularProgressIndicator(color: Colors.white) 
                    : const Text('保存する', style: TextStyle(fontSize: 18)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _isLoading ? null : _saveClassGroup, 
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}