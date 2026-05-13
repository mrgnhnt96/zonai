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
      CollectionRulesResponse._path => CollectionRulesResponse.fromJson(json),
      RecordRulesResponse._path => RecordRulesResponse.fromJson(json),
      AuthCollectionRulesResponse._path => AuthCollectionRulesResponse.fromJson(
        json,
      ),
      AuthRecordRulesResponse._path => AuthRecordRulesResponse.fromJson(json),
      _ => throw ArgumentError('Invalid rule response path: $path'),
    };
  }
}

final class AuthCollectionRulesResponse extends RuleResponse {
  AuthCollectionRulesResponse({
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

  factory AuthCollectionRulesResponse.fromJson(Map<String, dynamic> json) {
    return AuthCollectionRulesResponse(
      id: json['id'],
      collection: json['collection'],
      canAuthenticate: json['canAuthenticate'],
      authType: AuthType.values.byName(json['authType']),
    );
  }

  static const _path = '${Response.prefix}.collection.auth.can_authenticate';

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
    return 'AuthCollectionRulesResponse(collection: $collection, canAuthenticate: $canAuthenticate, authType: $authType)';
  }
}

final class AuthRecordRulesResponse extends RuleResponse {
  AuthRecordRulesResponse({
    required super.id,
    required this.collection,
    required this.canAccess,
    required this.authType,
    required this.operation,
  }) : super(
         path: _path,
         payload: {
           'collection': collection,
           'canAuthenticate': canAccess,
           'authType': authType.name,
           'operation': operation.name,
         },
       );

  factory AuthRecordRulesResponse.fromJson(Map<String, dynamic> json) {
    return AuthRecordRulesResponse(
      id: json['id'],
      collection: json['collection'],
      canAccess: json['canAuthenticate'],
      authType: AuthType.values.byName(json['authType']),
      operation: AuthOperation.values.byName(json['operation']),
    );
  }

  static const _path = '${Response.prefix}.record.auth.can_access';

  final String collection;
  final bool canAccess;
  final AuthType authType;
  final AuthOperation operation;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'collection': collection,
      'canAuthenticate': canAccess,
      'authType': authType.name,
      'operation': operation.name,
    };
  }

  @override
  String toString() {
    return 'AuthRecordRulesResponse(collection: $collection, canAccess: $canAccess, authType: $authType, operation: $operation)';
  }
}

final class CollectionRulesResponse extends RuleResponse {
  CollectionRulesResponse({
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

  factory CollectionRulesResponse.fromJson(Map<String, dynamic> json) {
    return CollectionRulesResponse(
      id: json['id'],
      collection: json['collection'],
      operation: json['operation'],
      canAccess: json['canAccess'],
    );
  }

  static const _path = '${Response.prefix}.collection.can_access';

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
    return 'CollectionRulesResponse(collection: $collection, operation: $operation, canAccess: $canAccess)';
  }
}

final class RecordRulesResponse extends RuleResponse {
  RecordRulesResponse({
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

  factory RecordRulesResponse.fromJson(Map<String, dynamic> json) {
    return RecordRulesResponse(
      id: json['id'] as String,
      collection: json['collection'] as String,
      operation: RecordOperation.fromString(json['operation'])!,
      canPerform: json['canPerform'] as bool,
    );
  }

  static const _path = '${Response.prefix}.record.can_access';

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
    return 'RecordRulesResponse(collection: $collection, operation: $operation, canPerform: $canPerform)';
  }
}
