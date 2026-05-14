part of payloads;

class JwtPayload extends Payload {
  const JwtPayload({required this.jwt});

  final String? jwt;
}

class CreatePayload extends JwtPayload {
  const CreatePayload({required this.object, super.jwt});

  final Map<String, dynamic> object;
}

class UpdatePayload extends JwtPayload {
  const UpdatePayload({
    required this.where,
    required this.updates,
    this.limit,
    super.jwt,
  });

  final Where where;
  final int? limit;
  final List<Update> updates;
}

class DeletePayload extends JwtPayload {
  const DeletePayload({required this.where, this.limit, super.jwt});

  final Where where;
  final int? limit;
}

class DeleteOnePayload extends JwtPayload implements DeletePayload {
  const DeleteOnePayload({
    required this.collection,
    required this.id,
    this.column = 'id',
    super.jwt,
  }) : limit = 1;

  final String collection;
  final String id;
  final String column;
  final int limit;

  @override
  Where get where => Eq(column, id);
}

class ListPayload extends JwtPayload {
  const ListPayload({this.where, this.limit, this.offset, super.jwt});

  final Where? where;
  final int? limit;
  final int? offset;
}

class ViewPayload extends JwtPayload {
  const ViewPayload({required this.where, super.jwt});

  final Where where;
}
