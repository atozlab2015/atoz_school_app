class AppUser {
  final String id; // FirebaseのUID
  final String email;
  final String name; // 表示名（管理者名、講師名、保護者名）
  final String role; // 'admin'(管理者), 'teacher'(講師), 'parent'(保護者)
  
  // 保護者専用の項目
  final String? fcmToken;
  final String? joinedAt; // 入会年月 (保護者の場合のみ)

  AppUser({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    this.fcmToken,
    this.joinedAt,
  });

  // Firebaseからデータを取り込む時の変換処理
  // DocumentSnapshotからMapを取り出す際に使う
  factory AppUser.fromMap(Map<String, dynamic> data, String uid) {
    return AppUser(
      id: uid,
      email: data['email'] ?? '',
      name: data['name'] ?? '',
      // Firestoreにroleフィールドがない場合、デフォルトで 'parent' と見なす
      role: data['role'] ?? 'parent', 
      fcmToken: data['fcmToken'],
      joinedAt: data['joinedAt'],
    );
  }

  // Firebaseに保存する時の変換処理
  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'name': name,
      'role': role,
      'fcmToken': fcmToken,
      'joinedAt': joinedAt,
    };
  }
}