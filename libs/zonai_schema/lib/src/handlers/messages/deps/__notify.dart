part of '../message_handler.dart';

typedef _RespondFn = void Function(Response response);
typedef _RequestFn = Future<Response?> Function(Request request);

final _msgProvider = create<_Msg>(_Msg._);

_Msg get msg => read(_msgProvider);

void _noop(Response response) {}
Future<Response> _noopRequest(Request request) async =>
    throw UnimplementedError();

class _Msg {
  const _Msg._() : _respond = _noop, _request = _noopRequest;

  _Msg(this._respond, this._request);

  final _RespondFn _respond;
  final _RequestFn _request;

  void notify(Response response) {
    _respond(response);
  }

  Future<T> request<T extends Response>(Request request) async {
    final response = await _request(request);

    if (response is! T) {
      throw ArgumentError(
        '$_Msg.request expected $T, got ${response.runtimeType}',
      );
    }

    return response;
  }
}
