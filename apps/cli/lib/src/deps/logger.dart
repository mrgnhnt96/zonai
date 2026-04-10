import 'package:zonai_logger/zonai_logger.dart';
import 'package:scoped_deps/scoped_deps.dart';

final loggerProvider = create<Logger>(Logger.new);

Logger get logger => read(loggerProvider);
