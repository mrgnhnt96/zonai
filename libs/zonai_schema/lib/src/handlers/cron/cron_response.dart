import 'package:zonai_schema/src/handlers/messages/message_handler.dart';

sealed class CronResponse extends Response {
  const CronResponse({
    required super.path,
    required super.id,
    required super.payload,
  });

  static const prefix = '${Response.prefix}.cron';

  factory CronResponse.fromJson(Map<String, dynamic> json) {
    return switch (json['path']) {
      CronsStopped._path => CronsStopped.fromJson(json),
      CronsStarted._path => CronsStarted.fromJson(json),
      JobStarted._path => JobStarted.fromJson(json),
      JobCompleted._path => JobCompleted.fromJson(json),
      JobFailed._path => JobFailed.fromJson(json),
      LastJobRunResponse._path => LastJobRunResponse.fromJson(json),
      final path => throw ArgumentError('Invalid cron response path: $path'),
    };
  }
}

final class CronsStopped extends CronResponse {
  const CronsStopped({required super.id})
    : super(path: _path, payload: const {});

  factory CronsStopped.fromJson(Map<String, dynamic> json) {
    return CronsStopped(id: json['id']);
  }

  static const _path = '${CronResponse.prefix}.stopped';
}

final class CronsStarted extends CronResponse {
  const CronsStarted({required super.id})
    : super(path: _path, payload: const {});

  factory CronsStarted.fromJson(Map<String, dynamic> json) {
    return CronsStarted(id: json['id']);
  }

  static const _path = '${CronResponse.prefix}.started';
}

final class JobStarted extends CronResponse {
  JobStarted({required super.id, required this.name})
    : super(path: _path, payload: {});

  factory JobStarted.fromJson(Map<String, dynamic> json) {
    return JobStarted(id: json['id'], name: json['name'] as String);
  }

  static const _path = '${CronResponse.prefix}.job.started';

  final String name;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'name': name};
  }
}

final class JobCompleted extends CronResponse {
  const JobCompleted({required super.id, required this.name})
    : super(path: _path, payload: const {});

  factory JobCompleted.fromJson(Map<String, dynamic> json) {
    return JobCompleted(id: json['id'], name: json['name'] as String);
  }

  static const _path = '${CronResponse.prefix}.job.completed';

  final String name;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'name': name};
  }
}

final class JobFailed extends CronResponse {
  JobFailed({
    required super.id,
    required this.name,
    required this.error,
    required this.stackTrace,
  }) : super(path: _path, payload: {});

  factory JobFailed.fromJson(Map<String, dynamic> json) {
    return JobFailed(
      id: json['id'],
      name: json['name'] as String,
      error: json['error'] as String,
      stackTrace: json['stackTrace'] as String,
    );
  }

  static const _path = '${CronResponse.prefix}.job.failed';

  final String name;
  final String error;
  final String stackTrace;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'name': name,
      'error': error,
      'stackTrace': stackTrace,
    };
  }
}

final class LastJobRunResponse extends CronResponse {
  LastJobRunResponse({
    required this.name,
    required this.time,
    required this.wasSuccessful,
    required super.id,
  }) : super(path: _path, payload: const {});

  factory LastJobRunResponse.fromJson(Map<String, dynamic> json) {
    return LastJobRunResponse(
      id: json['id'],
      name: json['name'] as String,
      time: switch (json['lastRun']) {
        final String time => DateTime.tryParse(time),
        final DateTime time => time,
        _ => null,
      },
      wasSuccessful: json['wasSuccessful'] as bool,
    );
  }

  final String name;
  final DateTime? time;
  final bool wasSuccessful;

  static const _path = '${CronResponse.prefix}.job.last_run';

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'name': name,
      'lastRun': time?.toIso8601String(),
      'wasSuccessful': wasSuccessful,
    };
  }
}
