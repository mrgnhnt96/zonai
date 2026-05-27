class CreateBody {
  const CreateBody({required this.table, required this.object});

  final String table;
  final Map<String, dynamic> object;

  factory CreateBody.fromJson(Map<String, dynamic> json) {
    return CreateBody(
      table: json['table'] as String,
      object: json['object'] as Map<String, dynamic>,
    );
  }

  Map<String, dynamic> toJson() {
    return {'table': table, 'object': object};
  }
}
