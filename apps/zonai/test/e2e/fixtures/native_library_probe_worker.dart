// Fixture worker for native_library_request_e2e_test.dart.
//
// Exercises the real ask-your-spawner native library protocol end to end:
// on any request, it asks whatever spawned this process (via the real
// `nativeLibraryHost`/`NativeLibraryRequest` plumbing wired into
// `MessageHandler.listen`, see zonai_schema's message_handler.dart) to
// resolve the named native library, then reports the result back.
//
// Deliberately has *no* self-extraction fallback of its own (unlike the
// real resqlite_native.dart/argon2_native.dart) -- a successful reply here
// can only mean the ask actually reached the spawner and got a real
// answer, which is exactly the behavior under test.
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';

void main() async {
  await MessageHandler<UnknownRequest>(
    fromUnknownRequest: (request) => request,
    onMessage: (request) async {
      final library = NativeLibraryKind.values.byName(
        request.path.split('/').last,
      );

      final path = await nativeLibraryHost.request(library);
      if (path == null) {
        return MessageErrorResponse(
          id: request.id,
          message: 'Spawner did not answer the native library request',
        );
      }

      return NativeLibraryResponse(id: request.id, libraryPath: path);
    },
  ).listen();
}
