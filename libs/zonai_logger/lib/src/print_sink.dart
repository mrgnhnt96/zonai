import 'package:zonai_logger/src/callback_sink.dart';

class PrintSink extends CallbackSink {
  const PrintSink() : super(callback: print);
}
