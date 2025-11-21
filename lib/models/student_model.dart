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
  
  // ★追加: 検索用のクラスIDリスト (Firestoreの array-contains クエリ用)
  final List<String> enrolledGroupIds; 

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
    required this.enrolledGroupIds, // ★追加
  });

  factory Student.fromMap(Map<String, dynamic> data, String id) {
    var list = data['enrollments'] as List<dynamic>? ?? [];
    List<Enrollment> enrollmentsList = list.map((i) => Enrollment.fromMap(i)).toList();
    
    // ★追加: 検索用IDリストの読み込み（なければenrollmentsから生成）
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
      enrolledGroupIds: groupIds, // ★追加
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
      // ★追加: 検索用IDリストを保存
      'enrolledGroupIds': enrollments.map((e) => e.groupId).toList(),
    };
  }
  
  String get fullName => '$lastName $firstName';
  String get fullNameRomaji => '$firstNameRomaji $lastNameRomaji';
}