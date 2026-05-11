import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/handlers/rules/rule_request.dart';
import 'package:zonai_schema/src/schemas/auth_collection.dart';

sealed class RuleResponse extends Response {
  const RuleResponse({
    required super.path,
    required super.id,
    required super.payload,
  });

  factory RuleResponse.fromJson(Map<String, dynamic> json) {
    final path = json['path'];
    if (path == null) {
      throw ArgumentError('Invalid rule response path: ${json['path']}');
    }

    final id = json['id'];
    if (id == null) {
      throw ArgumentError('Invalid rule response id: ${json['id']}');
    }

    return switch (path) {
      CanAccessResponse._path => CanAccessResponse.fromJson(json),
      RecordFilterResponse._path => RecordFilterResponse.fromJson(json),
      CanAuthenticateResponse._path => CanAuthenticateResponse.fromJson(json),
      _ => throw ArgumentError('Invalid rule response path: $path'),
    };
  }
}

final class CanAuthenticateResponse extends RuleResponse {
  CanAuthenticateResponse({
    required super.id,
    required this.collection,
    required this.canAuthenticate,
    required this.authType,
  }) : super(
         path: _path,
         payload: {
           'collection': collection,
           'canAuthenticate': canAuthenticate,
           'authType': authType.name,
         },
       );

  factory CanAuthenticateResponse.fromJson(Map<String, dynamic> json) {
    return CanAuthenticateResponse(
      id: json['id'],
      collection: json['collection'],
      canAuthenticate: json['canAuthenticate'],
      authType: AuthType.values.byName(json['authType']),
    );
  }

  static const _path = 'can_authenticate';

  final String collection;
  final bool canAuthenticate;
  final AuthType authType;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'collection': collection,
      'canAuthenticate': canAuthenticate,
      'authType': authType.name,
    };
  }

  @override
  String toString() {
    return 'CanAuthenticateResponse(collection: $collection, canAuthenticate: $canAuthenticate, authType: $authType)';
  }
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

  @override
  String toString() {
    return 'CanAccessResponse(collection: $collection, operation: $operation, canAccess: $canAccess)';
  }
}

final class RecordFilterResponse extends RuleResponse {
  RecordFilterResponse({
    required super.id,
    required this.collection,
    required this.operation,
    required this.canPerform,
  }) : super(
         path: _path,
         payload: {
           'collection': collection,
           'operation': operation.name,
           'canPerform': canPerform,
         },
       );

  factory RecordFilterResponse.fromJson(Map<String, dynamic> json) {
    return RecordFilterResponse(
      id: json['id'] as String,
      collection: json['collection'] as String,
      operation: RecordOperation.fromString(json['operation'])!,
      canPerform: json['canPerform'] as bool,
    );
  }

  static const _path = 'record_filter';

  final String collection;
  final RecordOperation operation;
  final bool canPerform;

  @override
  Map<String, dynamic> toJson() {
    return {
      'collection': collection,
      'operation': operation.name,
      'canPerform': canPerform,
      ...super.toJson(),
    };
  }

  @override
  String toString() {
    return 'RecordFilterResponse(collection: $collection, operation: $operation, canPerform: $canPerform)';
  }
}
