library payloads;

import 'package:zonai_schema/src/update/update.dart';

part 'where.dart';

class Payload {
  const Payload();
}

class CreatePayload extends Payload {
  const CreatePayload({required this.object});

  final Map<String, dynamic> object;
}

class UpdatePayload extends Payload {
  const UpdatePayload({required this.where, this.limit, required this.updates});

  final Where where;
  final int? limit;
  final List<Update> updates;
}

class DeletePayload extends Payload {
  const DeletePayload({required this.where, this.limit});

  final Where where;
  final int? limit;
}

class DeleteOnePayload implements DeletePayload {
  const DeleteOnePayload({required this.id}) : limit = 1;

  final String id;
  final int limit;
  @override
  Where get where => Where();
}

class ListPayload extends Payload {
  const ListPayload({required this.where, this.limit, this.offset});

  final Where where;
  final int? limit;
  final int? offset;
}

class ViewPayload extends Payload {
  const ViewPayload({required this.where});

  final Where where;
}
