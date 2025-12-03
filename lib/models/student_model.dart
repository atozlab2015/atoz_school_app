import 'package:cloud_firestore/cloud_firestore.dart';

class Enrollment {
  final String groupId;
  final DateTime startDate;
  final DateTime? endDate;

  Enrollment({
    required this.groupId,
    required this.startDate,
    this.endDate,
  });

  Map<String, dynamic> toMap() => {
    'groupId': groupId,
    'startDate': startDate,
    'endDate': endDate,
  };

  factory Enrollment.fromMap(Map<String, dynamic> data) {
    return Enrollment(
      groupId: data['groupId'] ?? '',
      startDate: (data['startDate'] as Timestamp).toDate(),
      endDate: (data['endDate'] as Timestamp?)?.toDate(),
    );
  }
}

class Student {
  final String id;
  final String parentId; 
  final String firstName;       
  final String lastName;        
  final String firstNameRomaji; 
  final String lastNameRomaji;  
  final DateTime dob;           
  final DateTime admissionDate;
  
  final List<Enrollment> enrollments; 
  final List<String> enrolledGroupIds; 
  
  final int ticketBalance; 
  
  // ★追加: 年会費の発生月 ('1月'...'12月', '年会費なし')
  final String annualFeeMonth;

  Student({
    required this.id,
    required this.parentId,
    required this.firstName,
    required this.lastName,
    required this.firstNameRomaji,
    required this.lastNameRomaji,
    required this.dob,
    required this.admissionDate,
    required this.enrollments,
    required this.enrolledGroupIds,
    this.ticketBalance = 0,
    this.annualFeeMonth = '年会費なし', // ★追加: デフォルト
  });

  factory Student.fromMap(Map<String, dynamic> data, String id) {
    var list = data['enrollments'] as List<dynamic>? ?? [];
    List<Enrollment> enrollmentsList = list.map((i) => Enrollment.fromMap(i)).toList();
    
    var groupIds = List<String>.from(data['enrolledGroupIds'] ?? []);
    if (groupIds.isEmpty && enrollmentsList.isNotEmpty) {
      groupIds = enrollmentsList.map((e) => e.groupId).toList();
    }

    return Student(
      id: id,
      parentId: data['parentId'] ?? '',
      firstName: data['firstName'] ?? '',
      lastName: data['lastName'] ?? '',
      firstNameRomaji: data['firstNameRomaji'] ?? '',
      lastNameRomaji: data['lastNameRomaji'] ?? '',
      dob: (data['dob'] as Timestamp?)?.toDate() ?? DateTime(2000, 1, 1),
      admissionDate: (data['admissionDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      enrollments: enrollmentsList,
      enrolledGroupIds: groupIds,
      ticketBalance: data['ticketBalance'] ?? 0,
      annualFeeMonth: data['annualFeeMonth'] ?? '年会費なし', // ★追加: 読み込み
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'parentId': parentId,
      'firstName': firstName,
      'lastName': lastName,
      'firstNameRomaji': firstNameRomaji,
      'lastNameRomaji': lastNameRomaji,
      'dob': dob,
      'admissionDate': admissionDate,
      'enrollments': enrollments.map((e) => e.toMap()).toList(),
      'enrolledGroupIds': enrollments.map((e) => e.groupId).toList(),
      'ticketBalance': ticketBalance,
      'annualFeeMonth': annualFeeMonth, // ★追加: 保存
    };
  }
  
  String get fullName => '$lastName $firstName';
  String get fullNameRomaji => '$firstNameRomaji $lastNameRomaji';
}