import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:atoz_school_app/models/class_model.dart';

// 予約タイプの選択肢
const List<String> bookingTypes = ['fixed', 'spot'];
// 曜日選択肢
const List<String> daysOfWeek = ['月曜', '火曜', '水曜', '木曜', '金曜', '土曜', '日曜'];

class ClassGroupFormScreen extends StatefulWidget {
  // ▼ 階層の全IDを受け取る
  final String subjectId; 
  final String courseId; 
  final String levelId;
  final String levelName;

  const ClassGroupFormScreen({
    super.key,
    required this.subjectId, 
    required this.courseId, 
    required this.levelId,
    required this.levelName,
  });

  @override
  State<ClassGroupFormScreen> createState() => _ClassGroupFormScreenState();
}

class _ClassGroupFormScreenState extends State<ClassGroupFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>(); 
  
  // フォームの状態を保存する変数
  String _teacherName = '';
  String _dayOfWeek = daysOfWeek.first; 
  String _startTime = '10:00'; 
  int _duration = 50; 
  int _capacity = 8;
  String _bookingType = bookingTypes.first; 
  int? _monthlyLimit; // 月の回数制限

  // ■ データ保存処理
  Future<void> _saveGroup() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    form.save();

    // 最終モデルへのデータ渡す (全IDとフォーム入力を結合)
    final newGroup = ClassGroup(
      id: FirebaseFirestore.instance.collection('groups').doc().id,
      // ▼▼▼ ここで全階層IDを保存 ▼▼▼
      subjectId: widget.subjectId, 
      courseId: widget.courseId, 
      levelId: widget.levelId,
      // ▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲
      teacherName: _teacherName,
      dayOfWeek: _dayOfWeek,
      startTime: _startTime,
      durationMinutes: _duration,
      capacity: _capacity,
      bookingType: _bookingType,
      spotLimitType: _bookingType == 'spot' && _monthlyLimit != null ? 'monthly_count' : 'unlimited',
      monthlyLimitCount: _monthlyLimit ?? 0,
    );

    try {
      // ClassGroupモデルをMapに変換してFirestoreに保存
      await FirebaseFirestore.instance.collection('groups').add(newGroup.toMap());
      
      if (mounted) {
        Navigator.pop(context); // 前の画面に戻る
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('クラス枠が正常に登録されました。')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('登録中にエラーが発生しました: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.levelName}：枠の新規登録'),
        backgroundColor: Colors.brown.shade400,
        actions: [
          IconButton(onPressed: _saveGroup, icon: const Icon(Icons.save, color: Colors.white)),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // フォームタイトル
              Text('対象: ${widget.levelName}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Divider(),
              
              // 1. 講師名
              TextFormField(
                decoration: const InputDecoration(labelText: '担当講師名'),
                onSaved: (value) => _teacherName = value ?? '',
                validator: (value) => (value == null || value.isEmpty) ? '講師名は必須です' : null,
              ),
              // 2. 曜日選択
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: '曜日'),
                value: _dayOfWeek,
                items: daysOfWeek.map((String day) {
                  return DropdownMenuItem(value: day, child: Text(day));
                }).toList(),
                onChanged: (newValue) => setState(() => _dayOfWeek = newValue!),
                onSaved: (value) => _dayOfWeek = value!,
              ),
              // 3. 時間とレッスン時間
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      decoration: const InputDecoration(labelText: '開始時間 (HH:MM)'),
                      initialValue: _startTime,
                      onSaved: (value) => _startTime = value ?? '',
                      validator: (value) => value!.isEmpty ? '時間を入力' : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      decoration: const InputDecoration(labelText: 'レッスン時間 (分)'),
                      initialValue: _duration.toString(),
                      keyboardType: TextInputType.number,
                      onSaved: (value) => _duration = int.tryParse(value ?? '0') ?? 50,
                      validator: (value) => value!.isEmpty ? '時間を入力' : null,
                    ),
                  ),
                ],
              ),
              // 4. 定員設定
              TextFormField(
                decoration: const InputDecoration(labelText: '定員数（振替含む）'),
                initialValue: _capacity.toString(),
                keyboardType: TextInputType.number,
                onSaved: (value) => _capacity = int.tryParse(value ?? '0') ?? 8,
                validator: (value) => (value == null || int.tryParse(value) == 0) ? '定員は必須です' : null,
              ),
              const Divider(height: 30),
              // 5. 予約タイプ（固定制 or 都度予約）
              const Text('予約タイプ:', style: TextStyle(fontWeight: FontWeight.bold)),
              DropdownButton<String>(
                value: _bookingType,
                items: bookingTypes.map((type) => DropdownMenuItem(value: type, child: Text(type == 'fixed' ? '固定制' : '都度予約'))).toList(),
                onChanged: (newValue) => setState(() => _bookingType = newValue!),
              ),
              
              // 6. 回数制限 (都度予約の場合のみ表示)
              if (_bookingType == 'spot') ...[
                const SizedBox(height: 10),
                TextFormField(
                  decoration: const InputDecoration(labelText: '月間予約回数制限 (例: 4)'),
                  keyboardType: TextInputType.number,
                  initialValue: _monthlyLimit?.toString(),
                  onSaved: (value) => _monthlyLimit = int.tryParse(value ?? ''),
                  validator: (value) => value!.isNotEmpty && int.tryParse(value) == null ? '数値を入力してください' : null,
                ),
              ],
              const SizedBox(height: 40),
              Center(
                child: ElevatedButton(
                  onPressed: _saveGroup,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.brown),
                  child: const Text('クラス枠を登録', style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}