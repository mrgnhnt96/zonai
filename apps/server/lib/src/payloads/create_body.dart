class CreateBody {
  const CreateBody({required this.collection, required this.object});

  final String collection;
  final Map<String, dynamic> object;

  factory CreateBody.fromJson(Map<String, dynamic> json) {
    return CreateBody(
      collection: json['collection'] as String,
      object: json['object'] as Map<String, dynamic>,
    );
  }

  Map<String, dynamic> toJson() {
    return {'collection': collection, 'object': object};
  }
}
