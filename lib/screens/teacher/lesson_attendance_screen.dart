import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// モデルのインポート
import '../../models/lesson_model.dart';
import '../../models/student_model.dart';
import '../../models/ticket_model.dart';
import '../../models/reservation_model.dart';

class LessonAttendanceScreen extends StatefulWidget {
  final LessonInstance lesson;

  const LessonAttendanceScreen({Key? key, required this.lesson}) : super(key: key);

  @override
  _LessonAttendanceScreenState createState() => _LessonAttendanceScreenState();
}

class _LessonAttendanceScreenState extends State<LessonAttendanceScreen> {
  bool _isLoading = true;
  List<AttendanceItem> _attendanceList = [];
  
  // 画面上の集計用
  int _totalCapacity = 0;
  int _presentCount = 0;

  @override
  void initState() {
    super.initState();
    _totalCapacity = widget.lesson.capacity;
    _fetchAttendanceData();
  }

  /// データの取得と出席簿の構築
  Future<void> _fetchAttendanceData() async {
    try {
      final lessonId = widget.lesson.id;
      final classGroupId = widget.lesson.classGroupId;

      // 1. レギュラー生の取得
      final studentSnapshot = await FirebaseFirestore.instance
          .collection('students')
          .where('enrolledGroupIds', arrayContains: classGroupId)
          .get();
      final regularStudents = studentSnapshot.docs
          .map((doc) => Student.fromMap(doc.data(), doc.id))
          .toList();

      // 2. チケット（欠席・振替元）の取得
      // 本番用コード: 該当するレッスンのチケットだけを取得（高速・低コスト）
      final ticketSnapshot = await FirebaseFirestore.instance
          .collection('tickets')
          .where('sourceLessonId', isEqualTo: lessonId)
          .get();

      final tickets = ticketSnapshot.docs
          .map((doc) => Ticket.fromMap(doc.data(), doc.id))
          .toList();

      // 3. 予約（振替参加）の取得
      final reservationSnapshot = await FirebaseFirestore.instance
          .collection('reservations')
          .where('lessonInstanceId', isEqualTo: lessonId)
          .where('status', isNotEqualTo: 'cancelled')
          .get();

      final reservations = reservationSnapshot.docs.map((doc) {
        return Reservation.fromMap(doc.data(), doc.id);
      }).toList();

      // 振替生の情報を取得
      final transferStudentIds = reservations.map((r) => r.studentId).toList();
      List<Student> transferStudents = [];
      if (transferStudentIds.isNotEmpty) {
        if (transferStudentIds.length <= 10) {
           final transferSnapshot = await FirebaseFirestore.instance
              .collection('students')
              .where(FieldPath.documentId, whereIn: transferStudentIds)
              .get();
           transferStudents = transferSnapshot.docs
              .map((doc) => Student.fromMap(doc.data(), doc.id))
              .toList();
        } else {
           for (var sId in transferStudentIds) {
             final sDoc = await FirebaseFirestore.instance.collection('students').doc(sId).get();
             if(sDoc.exists) transferStudents.add(Student.fromMap(sDoc.data()!, sDoc.id));
           }
        }
      }

      // 4. 統合と初期ステータス設定
      List<AttendanceItem> tempList = [];

      // --- A. レギュラー生 ---
      for (var student in regularStudents) {
        // 所属期間チェック
        final enrollment = student.enrollments.firstWhere(
          (e) => e.groupId == classGroupId,
          orElse: () => Enrollment(groupId: '', startDate: DateTime.now()),
        );
        if (widget.lesson.startTime.isBefore(enrollment.startDate)) continue;
        if (enrollment.endDate != null && widget.lesson.startTime.isAfter(enrollment.endDate!)) continue;

        // すでにチケットがあるか確認
        final myTicket = tickets.where((t) => t.studentId == student.id).firstOrNull;

        AttendanceType type = AttendanceType.regular;
        String statusText = '出席予定';
        bool initialIsPresent = true;
        bool isAlreadyAbsent = false; // すでに処理済みの欠席か

        if (myTicket != null) {
          initialIsPresent = false;
          isAlreadyAbsent = true; // DBに記録済みの欠席

          if (myTicket.validLevelId == 'forfeited') {
            type = AttendanceType.absentNoTransfer;
            statusText = '欠席 (振替なし)';
          } else if (myTicket.validLevelId == 'no_contact') { 
            // ★追加: 以前「連絡なし」として保存されたもの
            type = AttendanceType.absentNoContact;
            statusText = '欠席 (連絡なし)';
          } else if (myTicket.isUsed) {
            type = AttendanceType.transferredOut;
            statusText = '振替済 (他日へ)';
          } else {
            type = AttendanceType.absentPending;
            statusText = '欠席連絡済';
          }
        }

        tempList.add(AttendanceItem(
          student: student,
          statusText: statusText,
          type: type,
          isPresent: initialIsPresent,
          isLocked: isAlreadyAbsent, // すでに欠席処理済みならロック
        ));
      }

      // --- B. 振替生 ---
      for (var res in reservations) {
        final student = transferStudents.where((s) => s.id == res.studentId).firstOrNull;
        if (student != null) {
          tempList.add(AttendanceItem(
            student: student,
            statusText: '振替受講',
            type: AttendanceType.transferIn,
            isPresent: true,
            isLocked: false, // 振替生も来た/来てないの変更は可能にするならfalse
          ));
        }
      }

      // ソート: 振替生(赤)を目立たせるため先頭へ、その後は名前順
      tempList.sort((a, b) {
        if (a.type == AttendanceType.transferIn && b.type != AttendanceType.transferIn) return -1;
        if (a.type != AttendanceType.transferIn && b.type == AttendanceType.transferIn) return 1;
        return a.student.firstNameRomaji.compareTo(b.student.firstNameRomaji);
      });

      setState(() {
        _attendanceList = tempList;
        _recalcCounts();
        _isLoading = false;
      });

    } catch (e) {
      debugPrint('Error: $e');
      setState(() => _isLoading = false);
    }
  }

  void _recalcCounts() {
    int p = 0;
    for (var item in _attendanceList) {
      if (item.isPresent) p++;
    }
    setState(() {
      _presentCount = p;
    });
  }

  /// 保存処理
  /// スイッチがOFFになっている生徒に対して、「欠席（連絡なし）」チケットを発行する
  Future<void> _saveAttendance() async {
    final batch = FirebaseFirestore.instance.batch();
    int newAbsentCount = 0;

    for (var item in _attendanceList) {
      // 「レギュラー生」かつ「スイッチがOFF(欠席)」かつ「まだDBに保存されていない(ロックされていない)」場合
      if (item.type == AttendanceType.regular && !item.isPresent && !item.isLocked) {
        
        final docRef = FirebaseFirestore.instance.collection('tickets').doc();
        
        // 新しいチケットデータを作成
        final newTicket = Ticket(
          id: docRef.id,
          studentId: item.student.id,
          validLevelId: 'no_contact', // ★連絡なしを表すID
          validLevelName: '欠席(連絡なし)',
          issueDate: DateTime.now(),
          // 有効期限は一旦3ヶ月後などに設定（仕様に合わせて変更してください）
          expiryDate: DateTime.now().add(const Duration(days: 90)),
          originDate: widget.lesson.startTime,
          // 時間範囲はフォーマットに合わせて整形
          originTimeRange: '${DateFormat('HH:mm').format(widget.lesson.startTime)}〜${DateFormat('HH:mm').format(widget.lesson.endTime)}',
          isUsed: false,
          sourceLessonId: widget.lesson.id, // ★このレッスンを休んだことを記録
        );

        batch.set(docRef, newTicket.toMap());
        newAbsentCount++;
      }
    }

    if (newAbsentCount > 0) {
      try {
        await batch.commit();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$newAbsentCount名の欠席(連絡なし)を保存しました')),
        );
        // 画面を再読み込みして、表示を「グレー（ロック状態）」に更新
        _fetchAttendanceData();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存エラー: $e')),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('変更はありません')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy/MM/dd (E) HH:mm', 'ja_JP');

    return Scaffold(
      appBar: AppBar(title: const Text('出席簿')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ヘッダー
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.grey[100],
                  child: Column(
                    children: [
                      Text(
                        dateFormat.format(widget.lesson.startTime),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('定員: $_totalCapacity名'),
                          const SizedBox(width: 20),
                          Text(
                            '出席: $_presentCount名', 
                            style: TextStyle(
                              color: _presentCount > _totalCapacity ? Colors.red : Colors.green[800],
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // リスト
                Expanded(
                  child: ListView.separated(
                    itemCount: _attendanceList.length,
                    separatorBuilder: (ctx, i) => const Divider(height: 1),
                    itemBuilder: (ctx, index) {
                      return _buildStudentTile(_attendanceList[index]);
                    },
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saveAttendance,
        label: const Text('保存する'),
        icon: const Icon(Icons.save),
        backgroundColor: Colors.indigo,
      ),
    );
  }

  Widget _buildStudentTile(AttendanceItem item) {
    // --- 色とスタイルの決定 ---
    Color? tileColor;
    Color iconColor = Colors.grey;
    IconData icon = Icons.check_circle_outline;
    Color nameColor = Colors.black;

    // A. ロックされている（すでに欠席確定）の場合 → グレー
    if (item.isLocked) {
      tileColor = Colors.grey[200];
      iconColor = Colors.grey;
      nameColor = Colors.grey;
      icon = Icons.block;
    } 
    // B. 振替生の場合 → 赤 (★ご要望対応)
    else if (item.type == AttendanceType.transferIn) {
      tileColor = Colors.red[50]; // 薄い赤背景
      iconColor = Colors.red;
      nameColor = Colors.red[900]!;
      icon = Icons.input;
    }
    // C. 通常のレギュラー生
    else {
      // スイッチON(出席)なら白/青、OFF(欠席予定)なら少し暗くする
      tileColor = item.isPresent ? Colors.white : Colors.grey[50];
      iconColor = item.isPresent ? Colors.blue : Colors.grey;
      icon = Icons.person;
    }

    // 表示用ステータステキストの調整
    String subTitle = item.statusText;
    if (!item.isLocked && !item.isPresent && item.type == AttendanceType.regular) {
      // まだ保存していないが、スイッチをOFFにした状態
      subTitle = '欠席 (連絡なし) - 保存で確定';
    }

    return Container(
      color: tileColor,
      child: SwitchListTile(
        secondary: CircleAvatar(
          backgroundColor: iconColor.withOpacity(0.1),
          child: Icon(icon, color: iconColor),
        ),
        title: Text(
          item.student.fullName,
          style: TextStyle(
            fontWeight: item.type == AttendanceType.transferIn ? FontWeight.bold : FontWeight.normal,
            color: nameColor,
          ),
        ),
        subtitle: Text(
          subTitle,
          style: TextStyle(
            color: item.isLocked ? Colors.grey : Colors.grey[700], 
            fontSize: 12,
            fontWeight: subTitle.contains('保存で確定') ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        // ロックされている生徒はスイッチ操作不可
        value: item.isPresent,
        onChanged: item.isLocked ? null : (bool val) {
          setState(() {
            item.isPresent = val;
            _recalcCounts();
          });
        },
        activeColor: item.type == AttendanceType.transferIn ? Colors.red : Colors.blue,
      ),
    );
  }
}

// --- EnumとHelper ---
enum AttendanceType {
  regular,           // 所属生
  transferIn,        // 振替生
  transferredOut,    // 振替済 (欠席)
  absentPending,     // 連絡済 (欠席)
  absentNoTransfer,  // 振替なし (欠席)
  absentNoContact,   // 連絡なし (欠席) ★追加
}

class AttendanceItem {
  final Student student;
  final String statusText;
  final AttendanceType type;
  bool isPresent; // スイッチの状態
  final bool isLocked; // 操作不可かどうか

  AttendanceItem({
    required this.student,
    required this.statusText,
    required this.type,
    required this.isPresent,
    required this.isLocked,
  });
}

extension IterableExtensions<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}