enum UserRole { patient, doctor, nurse }

class UserModel {
  const UserModel({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    this.profileImageUrl,
    this.specialization,
  });

  final String id;
  final String email;
  final String name;
  final UserRole role;
  final String? profileImageUrl;
  final String? specialization;

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      email: json['email'] as String,
      name: json['name'] as String,
      role: UserRole.values.byName(json['role'] as String),
      profileImageUrl: json['profileImageUrl'] as String?,
      specialization: json['specialization'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'name': name,
        'role': role.name,
        if (profileImageUrl != null) 'profileImageUrl': profileImageUrl,
        if (specialization != null) 'specialization': specialization,
      };

  UserModel copyWith({
    String? id,
    String? email,
    String? name,
    UserRole? role,
    String? profileImageUrl,
    String? specialization,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      role: role ?? this.role,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      specialization: specialization ?? this.specialization,
    );
  }
}
