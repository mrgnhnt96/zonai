class CreateManyBody {
  const CreateManyBody({required this.table, required this.objects});

  final String table;
  final List<Map<String, dynamic>> objects;

  factory CreateManyBody.fromJson(Map<String, dynamic> json) {
    return CreateManyBody(
      table: json['table'] as String,
      objects: [
        for (final object in json['objects'] as List<dynamic>)
          object as Map<String, dynamic>,
      ],
    );
  }

  Map<String, dynamic> toJson() {
    return {'table': table, 'objects': objects};
  }
}
