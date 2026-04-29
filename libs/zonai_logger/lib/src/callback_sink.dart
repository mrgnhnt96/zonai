import 'dart:convert';
import 'dart:io' as io;

class CallbackSink implements io.IOSink {
  const CallbackSink({required this.callback}) : encoding = utf8;

  final void Function(Object?) callback;

  @override
  final Encoding encoding;
  set encoding(Encoding value) {
    throw UnimplementedError();
  }

  @override
  void add(List<int> data) {
    write(encoding.decode(data));
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    write(error.toString());
    if (stackTrace != null) {
      write(stackTrace.toString());
    }
  }

  @override
  Future<dynamic> addStream(Stream<List<int>> stream) {
    throw UnimplementedError();
  }

  @override
  Future<dynamic> close() async {}

  @override
  Future<dynamic> get done => Future.value();

  @override
  Future<dynamic> flush() async {}

  @override
  void write(Object? object) {
    callback(object);
  }

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = ""]) {
    write(objects.join(separator));
  }

  @override
  void writeCharCode(int charCode) {
    write(String.fromCharCode(charCode));
  }

  @override
  void writeln([Object? object = ""]) {
    write(object);
    write('\n');
  }
}
