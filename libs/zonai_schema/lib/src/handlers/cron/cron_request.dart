import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/types/cron_jwt.dart';

sealed class CronRequest extends Request {
  CronRequest({required super.path, required super.id}) : super(jwt: CronJwt());

  static const prefix = '${Request.prefix}.cron';

  factory CronRequest.fromJson(Map<String, dynamic> json) {
    return switch (json['path']) {
      StartCronsRequest._path => StartCronsRequest.fromJson(json),
      StopCronsRequest._path => StopCronsRequest.fromJson(json),
      LastJobRunRequest._path => LastJobRunRequest.fromJson(json),
      RunCronJobRequest._path => RunCronJobRequest.fromJson(json),
      CleanupUnreferencedPhotosRequest._path =>
        CleanupUnreferencedPhotosRequest.fromJson(json),
      ReclaimLogSpaceRequest._path => ReclaimLogSpaceRequest.fromJson(json),
      DrainPushJobsRequest._path => DrainPushJobsRequest.fromJson(json),
      ListCronJobsRequest._path => ListCronJobsRequest.fromJson(json),
      _ => throw ArgumentError('Invalid cron request path: ${json['path']}'),
    };
  }

  factory CronRequest.fromRequest(UnknownRequest request) {
    return switch (request.path) {
      StartCronsRequest._path => StartCronsRequest.fromRequest(request),
      StopCronsRequest._path => StopCronsRequest.fromRequest(request),
      LastJobRunRequest._path => LastJobRunRequest.fromRequest(request),
      RunCronJobRequest._path => RunCronJobRequest.fromRequest(request),
      CleanupUnreferencedPhotosRequest._path =>
        CleanupUnreferencedPhotosRequest.fromRequest(request),
      ReclaimLogSpaceRequest._path => ReclaimLogSpaceRequest.fromRequest(
        request,
      ),
      DrainPushJobsRequest._path => DrainPushJobsRequest.fromRequest(request),
      ListCronJobsRequest._path => ListCronJobsRequest.fromRequest(request),
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

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'name': name};
  }
}

final class RunCronJobRequest extends CronRequest {
  RunCronJobRequest({required this.name})
    : super(path: _path, id: Request.generateId());
  RunCronJobRequest._({required super.id, required this.name})
    : super(path: _path);

  factory RunCronJobRequest.fromJson(Map<String, dynamic> json) {
    return RunCronJobRequest._(id: json['id'], name: json['name'] as String);
  }

  factory RunCronJobRequest.fromRequest(UnknownRequest request) {
    return RunCronJobRequest._(
      id: request.id,
      name: request.payload['name'] as String,
    );
  }

  static const _path = '${CronRequest.prefix}.run_job';

  final String name;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'name': name};
  }
}

final class CleanupUnreferencedPhotosRequest extends CronRequest {
  CleanupUnreferencedPhotosRequest()
    : super(path: _path, id: Request.generateId());
  CleanupUnreferencedPhotosRequest._({required super.id}) : super(path: _path);

  factory CleanupUnreferencedPhotosRequest.fromJson(Map<String, dynamic> json) {
    return CleanupUnreferencedPhotosRequest._(id: json['id']);
  }

  factory CleanupUnreferencedPhotosRequest.fromRequest(UnknownRequest request) {
    return CleanupUnreferencedPhotosRequest._(id: request.id);
  }

  static const _path = '${CronRequest.prefix}.cleanup_unreferenced_photos';
}

/// Asks the host to rewrite the log database when enough of it is dead space.
///
/// A host RPC rather than a `mutate.*` call because `VACUUM` is not a
/// mutation the operations layer can express, and because the decision needs
/// two things only the host has: the database's pragmas and the volume's free
/// space.
final class ReclaimLogSpaceRequest extends CronRequest {
  ReclaimLogSpaceRequest() : super(path: _path, id: Request.generateId());
  ReclaimLogSpaceRequest._({required super.id}) : super(path: _path);

  factory ReclaimLogSpaceRequest.fromJson(Map<String, dynamic> json) {
    return ReclaimLogSpaceRequest._(id: json['id']);
  }

  factory ReclaimLogSpaceRequest.fromRequest(UnknownRequest request) {
    return ReclaimLogSpaceRequest._(id: request.id);
  }

  static const _path = '${CronRequest.prefix}.reclaim_log_space';
}

/// Asks the host to advance every unfinished push fan-out.
///
/// A host RPC rather than anything the worker could do itself: the fan-out
/// reads a token column the worker has no privileged access to, talks to FCM,
/// and commits its cursor and outcomes in one transaction. All three live
/// host-side.
///
/// This is what actually drains the queue `push` writes to. Recorded as its
/// own request rather than assumed reachable — the design flagged that today's
/// cron `get` defect (`1d95261`) was exactly a side effect that existed
/// everywhere except where it was needed.
final class DrainPushJobsRequest extends CronRequest {
  DrainPushJobsRequest() : super(path: _path, id: Request.generateId());
  DrainPushJobsRequest._({required super.id}) : super(path: _path);

  factory DrainPushJobsRequest.fromJson(Map<String, dynamic> json) {
    return DrainPushJobsRequest._(id: json['id']);
  }

  factory DrainPushJobsRequest.fromRequest(UnknownRequest request) {
    return DrainPushJobsRequest._(id: request.id);
  }

  static const _path = '${CronRequest.prefix}.drain_push_jobs';
}

final class ListCronJobsRequest extends CronRequest {
  ListCronJobsRequest() : super(path: _path, id: Request.generateId());
  ListCronJobsRequest._({required super.id}) : super(path: _path);

  factory ListCronJobsRequest.fromJson(Map<String, dynamic> json) {
    return ListCronJobsRequest._(id: json['id']);
  }

  factory ListCronJobsRequest.fromRequest(UnknownRequest request) {
    return ListCronJobsRequest._(id: request.id);
  }

  static const _path = '${CronRequest.prefix}.list_jobs';
}
