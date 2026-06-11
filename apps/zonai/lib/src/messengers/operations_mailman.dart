import 'package:zonai/src/db_mutator/mailman.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai/src/exceptions/exception_mapper.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/handlers/operations/operation_request.dart';
import 'package:zonai_schema/src/handlers/operations/operation_response.dart';

class OperationsMailman extends Mailman<OperationRequest, OperationResponse> {
  OperationsMailman()
    : super(
        debugName: debug,
        executablePath: settings.compiledOperationsPath,
        fromJson: OperationResponse.fromJson,
      );

  static const debug = 'OPERATIONS';

  @override
  Future<T> send<T extends OperationResponse?>(OperationRequest request) async {
    try {
      return await super.send<T>(request);
    } on MessageHandlerFailedException catch (error, stack) {
      Error.throwWithStackTrace(
        mapWorkerError(error, table: operationRequestTable(request)),
        stack,
      );
    }
  }
}
