import 'package:zonai_schema/zonai_schema.dart';

sealed class ConfigResponse extends Response {
  const ConfigResponse({
    required super.path,
    required super.id,
    required super.payload,
  });

  factory ConfigResponse.fromJson(Map<String, dynamic> json) {
    final path = json['path'];
    if (path == null) {
      throw ArgumentError('Invalid config response path: ${json['path']}');
    }

    final id = json['id'];
    if (id == null) {
      throw ArgumentError('Invalid config response id: ${json['id']}');
    }

    return switch (path) {
      GetAppConfigResponse._path => GetAppConfigResponse.fromJson(json),
      _ => throw ArgumentError('Invalid config response path: $path'),
    };
  }
}

final class GetAppConfigResponse extends ConfigResponse {
  GetAppConfigResponse({required super.id, required this.data})
    : super(path: _path, payload: {'data': data});

  factory GetAppConfigResponse.fromJson(Map<String, dynamic> json) {
    return GetAppConfigResponse(
      id: json['id'] as String,
      data: AppConfig.fromJson(json['data'] as Map<String, dynamic>),
    );
  }

  static const _path = '${Response.prefix}.config.get';

  final AppConfig data;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'data': data.toJson()};
  }
}
