import 'package:zonai_schema/src/handlers/messages/message_handler.dart';

sealed class CronRequest extends Request {
  const CronRequest({required super.path, required super.id});

  static const prefix = '${Request.prefix}.cron';

  factory CronRequest.fromJson(Map<String, dynamic> json) {
    return switch (json['path']) {
      StartCronsRequest._path => StartCronsRequest.fromJson(json),
      StopCronsRequest._path => StopCronsRequest.fromJson(json),
      LastJobRunRequest._path => LastJobRunRequest.fromJson(json),
      _ => throw ArgumentError('Invalid cron request path: ${json['path']}'),
    };
  }

  factory CronRequest.fromRequest(UnknownRequest request) {
    return switch (request.path) {
      StartCronsRequest._path => StartCronsRequest.fromRequest(request),
      StopCronsRequest._path => StopCronsRequest.fromRequest(request),
      LastJobRunRequest._path => LastJobRunRequest.fromRequest(request),
      _ => throw ArgumentError('Invalid cron request path: ${request.path}'),
    };
  }
}

final class StartCronsRequest extends CronRequest {
  StartCronsRequest() : super(path: _path, id: Request.generateId());
  StartCronsRequest._({required super.id}) : super(path: _path);

  factory StartCronsRequest.fromJson(Map<String, dynamic> json) {
    return StartCronsRequest._(id: json['id']);
  }

  factory StartCronsRequest.fromRequest(UnknownRequest request) {
    return StartCronsRequest._(id: request.id);
  }

  static const _path = '${CronRequest.prefix}.start';
}

final class StopCronsRequest extends CronRequest {
  StopCronsRequest() : super(path: _path, id: Request.generateId());
  StopCronsRequest._({required super.id}) : super(path: _path);

  factory StopCronsRequest.fromJson(Map<String, dynamic> json) {
    return StopCronsRequest._(id: json['id']);
  }

  factory StopCronsRequest.fromRequest(UnknownRequest request) {
    return StopCronsRequest._(id: request.id);
  }

  static const _path = '${CronRequest.prefix}.stop';
}

final class LastJobRunRequest extends CronRequest {
  LastJobRunRequest({required this.name})
    : super(path: _path, id: Request.generateId());
  LastJobRunRequest._({required super.id, required this.name})
    : super(path: _path);

  factory LastJobRunRequest.fromJson(Map<String, dynamic> json) {
    return LastJobRunRequest._(id: json['id'], name: json['name'] as String);
  }

  factory LastJobRunRequest.fromRequest(UnknownRequest request) {
    return LastJobRunRequest._(
      id: request.id,
      name: request.payload['name'] as String,
    );
  }

  static const _path = '${CronRequest.prefix}.last_job_run';

  final String name;
}
