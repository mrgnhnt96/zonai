part of payloads;

class JwtPayload extends Payload {
  const JwtPayload({required this.jwt});

  final String? jwt;
}

class FullJwtPayload extends Payload {
  const FullJwtPayload({required this.userJwt});

  final Jwt? userJwt;
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
    required this.table,
    required this.id,
    this.column = 'id',
    super.jwt,
  }) : limit = 1;

  final String table;
  final String id;
  final String column;
  final int limit;

  @override
  Where get where => Eq(column, id);
}

class ListPayload extends JwtPayload {
  ListPayload({
    required this.where,
    this.expand = const [],
    int? limit = maxLimit,
    super.jwt,
    this.offset,
    this.orderBy,
    this.groupBy,
  }) : limit = limit?.clamp(1, maxLimit) ?? maxLimit;

  static const maxLimit = 500;

  final Where? where;
  final int limit;
  final int? offset;
  final List<String> expand;
  final List<OrderByTerm>? orderBy;
  final String? groupBy;
}

class ListWithJwtPayload extends ListPayload implements FullJwtPayload {
  ListWithJwtPayload({
    required this.userJwt,
    super.expand,
    super.where,
    super.limit,
    super.offset,
    super.orderBy,
    super.groupBy,
  });

  final Jwt? userJwt;
  @override
  String? get jwt =>
      throw Exception('$ListWithJwtPayload does not support jwt');
}

class ViewPayload extends JwtPayload {
  const ViewPayload({required this.where, this.expand = const [], super.jwt});

  final Where where;
  final List<String> expand;
}

class CountPayload extends JwtPayload {
  const CountPayload({this.where, super.jwt});

  final Where? where;
}
