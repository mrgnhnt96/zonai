import 'package:zonai_schema/src/handlers/messages/message_handler.dart';

sealed class RuleResponse extends Response {
  const RuleResponse({
    required super.path,
    required super.id,
    required super.payload,
  });
}

final class CanAccessResponse extends RuleResponse {
  CanAccessResponse({
    required super.id,
    required this.collection,
    required this.operation,
    required this.canAccess,
  }) : super(
         path: _path,
         payload: {
           'collection': collection,
           'operation': operation,
           'canAccess': canAccess,
         },
       );

  factory CanAccessResponse.fromJson(Map<String, dynamic> json) {
    return CanAccessResponse(
      id: json['id'],
      collection: json['collection'],
      operation: json['operation'],
      canAccess: json['canAccess'],
    );
  }

  static const _path = 'can_access';

  final String collection;
  final String operation;
  final bool canAccess;

  @override
  Map<String, dynamic> toJson() {
    return {
      'collection': collection,
      'operation': operation,
      'canAccess': canAccess,
      ...super.toJson(),
    };
  }
}
