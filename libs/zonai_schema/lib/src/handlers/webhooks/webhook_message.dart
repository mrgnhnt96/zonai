import 'dart:typed_data';

import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/types/cron_jwt.dart';

/// Host → webhooks worker: run the webhook called [name] on one delivery.
///
/// Carries [CronJwt], the worker sentinel the host already treats as the
/// server, so the handler's `mutate` passes admin-only rules the same way a
/// cron job's does.
final class HandleWebhookRequest extends Request {
  HandleWebhookRequest({
    required this.name,
    required this.body,
    required this.headers,
    required this.ip,
  }) : super(path: _path, id: Request.generateId(), jwt: CronJwt());

  HandleWebhookRequest._({
    required super.id,
    required this.name,
    required this.body,
    required this.headers,
    required this.ip,
  }) : super(path: _path, jwt: CronJwt());

  factory HandleWebhookRequest.fromRequest(UnknownRequest request) {
    if (request.path != _path) {
      throw ArgumentError('Invalid webhook request path: ${request.path}');
    }
    final payload = request.payload;
    return HandleWebhookRequest._(
      id: request.id,
      name: payload['name'] as String,
      body: _bytes(payload['body']),
      headers: {
        for (final MapEntry(:key, :value)
            in (payload['headers'] as Map).entries)
          key.toString(): value.toString(),
      },
      ip: payload['ip'] as String,
    );
  }

  static const prefix = '${Request.prefix}.webhook';
  static const _path = '$prefix.handle';

  final String name;
  final Uint8List body;
  final Map<String, String> headers;
  final String ip;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'name': name,
      'body': body,
      'headers': headers,
      'ip': ip,
    };
  }
}

/// Webhooks worker → host: how to answer the delivery.
///
/// [found] is false when no webhook is called [HandleWebhookRequest.name];
/// the host answers 404 without looking at [status].
final class HandleWebhookResponse extends Response {
  const HandleWebhookResponse({
    required super.id,
    required this.found,
    required this.status,
    this.body,
  }) : super(path: _path, payload: const {});

  factory HandleWebhookResponse.fromJson(Map<String, dynamic> json) {
    final path = json['path'];
    if (path != _path) {
      throw ArgumentError('Invalid webhook response path: $path');
    }
    return HandleWebhookResponse(
      id: json['id'],
      found: json['found'] as bool,
      status: json['status'] as int,
      body: json['body'] as String?,
    );
  }

  static const _path = '${Response.prefix}.webhook.handle';

  final bool found;
  final int status;
  final String? body;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'found': found,
      'status': status,
      if (body != null) 'body': body,
    };
  }
}

/// msgpack hands binary back as [Uint8List]; an isolate or a JSON hop may
/// hand back a plain int list.
Uint8List _bytes(Object? value) => switch (value) {
  final Uint8List bytes => bytes,
  final List<Object?> list => Uint8List.fromList(list.cast<int>()),
  _ => throw ArgumentError('Invalid webhook body: ${value.runtimeType}'),
};
