import 'package:zonai_schema/src/payloads/parse_body.dart';

class CreateManyBody {
  const CreateManyBody({required this.table, required this.objects});

  final String table;
  final List<Map<String, dynamic>> objects;

  factory CreateManyBody.fromJson(Map<String, dynamic> json) =>
      parseBody('CreateManyBody', () => CreateManyBody._fromJson(json));

  factory CreateManyBody._fromJson(Map<String, dynamic> json) {
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
