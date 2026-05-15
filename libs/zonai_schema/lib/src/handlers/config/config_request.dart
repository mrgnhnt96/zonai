import '../messages/message_handler.dart';

sealed class ConfigRequest extends Request {
  const ConfigRequest({required super.path, required super.id});

  factory ConfigRequest.fromRequest(UnknownRequest request) {
    switch (request.path) {
      case GetAppConfigRequest._path:
        return GetAppConfigRequest.fromRequest(request);
      default:
        throw ArgumentError('Invalid config request path: ${request.path}');
    }
  }
}

final class GetAppConfigRequest extends ConfigRequest {
  GetAppConfigRequest() : super(path: _path, id: Request.generateId());

  GetAppConfigRequest._({required super.id}) : super(path: _path);

  factory GetAppConfigRequest.fromRequest(UnknownRequest request) {
    return GetAppConfigRequest._(id: request.id);
  }

  static const _path = '${Request.prefix}.config.get';

  @override
  Map<String, dynamic> toJson() => {...super.toJson()};
}
