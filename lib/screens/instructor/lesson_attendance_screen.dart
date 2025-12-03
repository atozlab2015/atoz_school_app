import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// モデルのインポート (パスはプロジェクトに合わせて調整してください)
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
  int _currentCount = 0;

  @override
  void initState() {
    super.initState();
    _fetchAttendanceData();
  }

  /// データの取得と出席簿の構築
  Future<void> _fetchAttendanceData() async {
    try {
      final lessonId = widget.lesson.id;
      final classGroupId = widget.lesson.classGroupId;

      // 1. レギュラー生の取得 (このクラスグループに所属している生徒)
      // Studentモデルに 'enrolledGroupIds' がある前提
      final studentSnapshot = await FirebaseFirestore.instance
          .collection('students')
          .where('enrolledGroupIds', arrayContains: classGroupId)
          .get();

      final regularStudents = studentSnapshot.docs
          .map((doc) => Student.fromMap(doc.data(), doc.id))
          .toList();

      // 2. このレッスンから「抜ける」チケットの取得 (欠席・振替元としてのチケット)
      // sourceLessonId がこのレッスンIDであるチケットを探す
      final ticketSnapshot = await FirebaseFirestore.instance
          .collection('tickets')
          .where('sourceLessonId', isEqualTo: lessonId)
          .get();

      final tickets = ticketSnapshot.docs
          .map((doc) => Ticket.fromMap(doc.data(), doc.id))
          .toList();

      // 3. このレッスンに「入る」予約の取得 (他日からの振替参加)
      final reservationSnapshot = await FirebaseFirestore.instance
          .collection('reservations')
          .where('lessonInstanceId', isEqualTo: lessonId)
          .where('status', isNotEqualTo: 'cancelled') // キャンセル以外
          .get();

      // Reservationモデルに fromMap が未実装の場合は手動パース、ある場合は fromMap を使用
      final reservations = reservationSnapshot.docs.map((doc) {
        final data = doc.data();
        return Reservation(
          id: doc.id,
          lessonInstanceId: data['lessonInstanceId'] ?? '',
          studentId: data['studentId'] ?? '',
          requestType: data['requestType'] ?? 'transfer',
          status: data['status'] ?? 'approved',
          requestedAt: data['requestedAt'] as Timestamp,
          originalLessonId: data['originalLessonId'],
        );
      }).toList();

      // 振替生の生徒情報を取得するためのIDリスト
      final transferStudentIds = reservations.map((r) => r.studentId).toList();
      List<Student> transferStudents = [];

      if (transferStudentIds.isNotEmpty) {
        // FirestoreのwhereInは最大10件制限があるため、件数が多い場合は分割が必要ですが、
        // ここでは簡易的に10件以下または全取得フィルタリングを想定、もしくはループ取得
        // 今回はシンプルに `whereIn` を使います
        // (注: 実際の運用で1クラスに振替が10人以上来る場合はチャンク処理が必要です)
        if (transferStudentIds.length <= 10) {
            final transferSnapshot = await FirebaseFirestore.instance
                .collection('students')
                .where(FieldPath.documentId, whereIn: transferStudentIds)
                .get();
            transferStudents = transferSnapshot.docs
                .map((doc) => Student.fromMap(doc.data(), doc.id))
                .toList();
        } else {
            // 10件超え対策（簡易版: 全件ループで取得）
            for (var sId in transferStudentIds) {
                final sDoc = await FirebaseFirestore.instance.collection('students').doc(sId).get();
                if(sDoc.exists) {
                    transferStudents.add(Student.fromMap(sDoc.data()!, sDoc.id));
                }
            }
        }
      }

      // 4. データの統合処理
      List<AttendanceItem> tempList = [];
      int count = 0;

      // --- A. レギュラー生の処理 ---
      for (var student in regularStudents) {
        // 所属期間チェック (念のため)
        final enrollment = student.enrollments.firstWhere(
          (e) => e.groupId == classGroupId,
          orElse: () => Enrollment(groupId: '', startDate: DateTime.now()), // ダミー
        );
        // レッスン日が所属期間内かチェック (簡易実装: 開始日以降ならOKとする)
        if (widget.lesson.startTime.isBefore(enrollment.startDate)) {
          continue; // まだ入会前
        }
        if (enrollment.endDate != null && widget.lesson.startTime.isAfter(enrollment.endDate!)) {
          continue; // 退会済み
        }

        // チケットによるステータス判定
        // この生徒がこのレッスンを休むチケットを発行しているか？
        final myTicket = tickets.where((t) => t.studentId == student.id).firstOrNull;

        String status = '出席予定';
        AttendanceType type = AttendanceType.regular;
        bool isPresent = true;

        if (myTicket != null) {
          isPresent = false; // チケットがある時点でこの枠にはいない
          if (myTicket.validLevelId == 'forfeited') {
            status = '欠席 (振替なし)';
            type = AttendanceType.absentNoTransfer;
          } else if (myTicket.isUsed) {
            status = '振替済 (他日へ)';
            type = AttendanceType.transferredOut;
          } else {
            status = '欠席連絡済 (振替未定)';
            type = AttendanceType.absentPending;
          }
        }

        if (isPresent) count++;

        tempList.add(AttendanceItem(
          student: student,
          statusText: status,
          type: type,
        ));
      }

      // --- B. 振替生の処理 ---
      for (var res in reservations) {
        final student = transferStudents.where((s) => s.id == res.studentId).firstOrNull;
        if (student != null) {
          tempList.add(AttendanceItem(
            student: student,
            statusText: '振替受講',
            type: AttendanceType.transferIn,
          ));
          count++;
        }
      }

      // 名前順などでソート (振替生を目立たせたい場合はソート順を調整)
      tempList.sort((a, b) {
        // 例: 振替生を先頭に、そのあとは名前順
        if (a.type == AttendanceType.transferIn && b.type != AttendanceType.transferIn) return -1;
        if (a.type != AttendanceType.transferIn && b.type == AttendanceType.transferIn) return 1;
        return a.student.firstNameRomaji.compareTo(b.student.firstNameRomaji);
      });

      setState(() {
        _attendanceList = tempList;
        _currentCount = count;
        _isLoading = false;
      });

    } catch (e) {
      debugPrint('Error fetching attendance: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy/MM/dd (E) HH:mm', 'ja_JP');

    return Scaffold(
      appBar: AppBar(
        title: const Text('出席簿'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ヘッダー情報
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
                          Text('定員: ${widget.lesson.capacity}名'),
                          const SizedBox(width: 20),
                          Text(
                            '予約: $_currentCount名',
                            style: TextStyle(
                              color: _currentCount > widget.lesson.capacity 
                                  ? Colors.red 
                                  : Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // 生徒リスト
                Expanded(
                  child: ListView.separated(
                    itemCount: _attendanceList.length,
                    separatorBuilder: (ctx, i) => const Divider(height: 1),
                    itemBuilder: (ctx, index) {
                      final item = _attendanceList[index];
                      return _buildStudentTile(item);
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildStudentTile(AttendanceItem item) {
    Color? bgColor;
    Color textColor = Colors.black;
    IconData icon = Icons.check_circle_outline;
    Color iconColor = Colors.grey;

    // ステータスに応じた装飾
    switch (item.type) {
      case AttendanceType.regular:
        // 通常出席
        icon = Icons.person;
        iconColor = Colors.blue;
        break;
      case AttendanceType.transferIn:
        // 振替受講 (目立つように)
        bgColor = Colors.green[50];
        icon = Icons.input;
        iconColor = Colors.green;
        break;
      case AttendanceType.transferredOut:
      case AttendanceType.absentPending:
      case AttendanceType.absentNoTransfer:
        // 欠席系
        bgColor = Colors.grey[200];
        textColor = Colors.grey;
        icon = Icons.cancel_outlined;
        iconColor = Colors.grey;
        break;
    }

    return Container(
      color: bgColor,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: iconColor.withOpacity(0.1),
          child: Icon(icon, color: iconColor),
        ),
        title: Text(
          item.student.fullName,
          style: TextStyle(
            color: textColor,
            fontWeight: item.type == AttendanceType.transferIn ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: Text(
          item.statusText,
          style: TextStyle(color: textColor.withOpacity(0.7)),
        ),
        trailing: item.type == AttendanceType.regular || item.type == AttendanceType.transferIn
            ? IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: () {
                  // TODO: ここで詳細情報の表示や、手動でのステータス変更アクションなどを実装
                },
              )
            : null,
      ),
    );
  }
}

// --- 内部利用のヘルパークラス ---

enum AttendanceType {
  regular,           // 所属生 (出席)
  transferIn,        // 振替生 (出席)
  transferredOut,    // 所属生 (振替済で欠席)
  absentPending,     // 所属生 (振替未定で欠席)
  absentNoTransfer,  // 所属生 (欠席のみ)
}

class AttendanceItem {
  final Student student;
  final String statusText;
  final AttendanceType type;

  AttendanceItem({
    required this.student,
    required this.statusText,
    required this.type,
  });
}

// Dart 2.12以前やcollectionパッケージがない場合の簡易拡張
extension IterableExtensions<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}