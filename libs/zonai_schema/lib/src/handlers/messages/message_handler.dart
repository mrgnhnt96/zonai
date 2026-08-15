// dart format width=100
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai_schema/src/handlers/cron/cron_request.dart';
import 'package:zonai_schema/src/handlers/cron/cron_response.dart';
import 'package:zonai_schema/src/handlers/messages/message_io.dart';
import 'package:zonai_schema/zonai_schema.dart';

part 'deps/__email.dart';
part 'deps/__get.dart';
part 'deps/__log.dart';
part 'deps/__mutate.dart';
part 'deps/__native_library.dart';
part 'deps/__notify.dart';
part 'deps/__push.dart';
part 'deps/__cron.dart';
part 'request.dart';
part 'response.dart';

class MessageHandler<R extends Request> {
  MessageHandler({required this.onMessage, required this.fromUnknownRequest, MessageIo? io})
    : io = io ?? StdioMessageIo();

  final Future<Response?> Function(R) onMessage;
  final MessageIo io;
  final R Function(UnknownRequest) fromUnknownRequest;

  final Map<String, Completer<Response>> _pendingHostReplies = {};

  bool _listening = false;
  Future<void> listen() async {
    Future<void> _listen() async {
      if (_listening) return;
      _listening = true;

      queue:
      await for (final raw in io.incoming) {
        final map = coerceStringKeyedMap(raw);

        final pathRaw = map['path'];

        if (pathRaw is String && pathRaw.startsWith(Response.prefix)) {
          Response? response;
          try {
            response = Response.fromJson(map);
          } catch (e, stack) {
            logger.error('Invalid response payload', error: '$e', stackTrace: '$stack');
            continue;
          }
          if (_pendingHostReplies.containsKey(response.id)) {
            _deliverHostReply(response);
            continue;
          }
          logger.warn(
            'Ignoring response with no pending id',
            properties: switch (response) {
              MessageErrorResponse(:final message, :final error) => {
                'path': pathRaw,
                'id': response.id,
                'error_message': message,
                'cause': error ?? '(null)',
              },
              _ => {'path': pathRaw, 'id': response.id},
            },
          );
          continue;
        }

        if (pathRaw is! String || !pathRaw.startsWith(Request.prefix)) {
          logger.error(
            'Invalid message path (expected ${Request.prefix})',
            properties: {'path': pathRaw},
          );
          continue;
        }

        Request request;
        try {
          request = Request.fromJson(map);
        } catch (e, stack) {
          logger.error(
            'Invalid request payload for path "$pathRaw"',
            error: '$e',
            stackTrace: '$stack',
          );
          continue;
        }

        switch (request) {
          case RequestPing():
            reply(PongResponse(id: request.id));
            continue;
          case RequestKill():
            break queue;

          case final R request:
            _handleResponse(request);

          case final UnknownRequest request:
            R typed;
            try {
              typed = fromUnknownRequest(request);
            } catch (e, stack) {
              // An uncaught throw here would escape the switch and the
              // `await for` above, killing this worker's whole listen loop
              // over one bad request instead of just failing that request.
              reply(
                MessageErrorResponse(
                  id: request.id,
                  message: 'Invalid request payload',
                  error: e.toString(),
                  stackTrace: stack.toString(),
                ),
              );
              continue;
            }
            _handleResponse(typed);

          case _:
            reply(
              MessageErrorResponse(
                id: request.id,
                message: 'Unhandled request',
                error: 'Unhandled request ${request.runtimeType}(${request.path})',
              ),
            );
        }
      }

      for (final completer in _pendingHostReplies.values) {
        completer.completeError(StateError('MessageHandler stopped before the host replied'));
      }
      _pendingHostReplies.clear();
      _listening = false;
    }

    await runZoned(
      () async {
        await runScoped(
          _listen,
          values: {
            _getRecordRequestProvider.overrideWith(
              () => _Get(({required tableName, required where, limit, offset, jwt}) async {
                final result = await sendRequest(
                  GetRecordRequest(
                    table: tableName,
                    where: where,
                    limit: limit,
                    offset: offset,
                    // Falls back to the ambient request's identity so `get`
                    // defaults the way `mutate` and `email` do.
                    //
                    // `orElse` is a guard, and named as one rather than dressed
                    // up: every `get` reachable today runs inside a
                    // `runWithParent`, so the ref is bound and the fallback is
                    // dead. But this closure is *built* here, in the listen
                    // scope, where it is not — and a bare `read` on an unbound
                    // ref throws. Without the `orElse` a future caller in that
                    // scope would take down the whole listen loop, which is a
                    // steep price for a default.
                    jwt: jwt ?? read(_ambientJwtProvider, orElse: () => null),
                  ),
                );

                if (result case GetRecordResponse(:final records)) {
                  return records;
                } else {
                  logger.error(
                    'Received unexpected response for get record request ${result?.path}',
                  );
                  logger.debug('Unexpected Response: ${result?.toJson()}');
                }

                return null;
              }),
            ),
            _nativeLibraryRequestProvider.overrideWith(
              () => _NativeLibrary((library) async {
                final result = await sendRequest(NativeLibraryRequest(library: library));

                if (result case NativeLibraryResponse(:final libraryPath)) {
                  return libraryPath;
                } else {
                  logger.error(
                    'Received unexpected response for native library request '
                    '${result?.path}',
                  );
                }

                return null;
              }),
            ),
            _loggerProvider.overrideWith(
              () => _Logger((message, {required level, properties, stackTrace, error}) {
                reply(
                  DebugResponse(
                    message: message,
                    level: level,
                    properties: properties,
                    stackTrace: stackTrace,
                    error: error,
                  ),
                );
              }),
            ),
          },
        );
      },
      zoneSpecification: .new(
        print: (_, _, _, message) {
          reply(DebugResponse(message: message, level: .info));
        },
      ),
    );
  }

  void _handleResponse(R request) {
    runWithParent(request, () async {
      onMessage(request).then(
        reply,
        onError: (Object error, StackTrace stackTrace) {
          logger.debug(
            'Error handling request',
            properties: {'request': request.toJson(), 'error': error.toString()},
          );
          reply(
            MessageErrorResponse(
              id: request.id,
              message: 'Error handling request',
              error: error.toString(),
              stackTrace: stackTrace.toString(),
            ),
          );
        },
      );
    });
  }

  /// Runs [body] with worker [get], [mutate], and [email] scoped to [parent].
  ///
  /// Side-effect [MutationRequest]s emitted during [body] use [parent.id] as
  /// their parent id so the host can commit them when the matching notification
  /// response arrives.
  ///
  /// The request-scoped bindings below are `override`, not `includeIfAbsent`,
  /// and the difference is load-bearing. `includeIfAbsent` skips a ref the
  /// zone chain already defines, so a *nested* `runWithParent` silently kept
  /// the outer request's bindings — and a scheduled cron nests: `_startCrons`
  /// runs inside `runWithParent(StartCronsRequest)`, `cron.schedule` registers
  /// its timers there, and a Dart timer fires in the zone that created it. So
  /// every firing, hours later, tagged its mutations with the startup
  /// request's id. The host keys `_pendingMutations` by that id and flushes it
  /// when the matching response arrives — which for `CronsStarted` had already
  /// happened, once, at boot. The mutations were parked forever, at any row
  /// count, without an error. Found via a production deployment whose
  /// retention crons had run 1,269 times and deleted nothing
  /// (see `test/src/handlers/cron/scheduled_cron_mutations_test.dart`).
  ///
  /// `_msg` and `_cron` stay in `includeIfAbsent`: they close over [reply] and
  /// [sendRequest], not over [request], so rebinding them would be a no-op.
  Future<void> runWithParent(covariant Request request, Future<void> Function() body) {
    final pendingSideEffects = <Future<void>>[];

    void queueSideEffect(Future<void>? sideEffect) {
      if (sideEffect != null) {
        pendingSideEffects.add(sideEffect);
      }
    }

    return runMergedScoped(
      () async {
        await body();
        if (pendingSideEffects.isNotEmpty) {
          await Future.wait(pendingSideEffects);
        }
      },
      includeIfAbsent: {
        _msgProvider.overrideWith(() => _Msg(reply, sendRequest)),
        _cronProvider.overrideWith(
          () => _Cron((name) {
            sendRequest(RunCronJobRequest(name: name));
          }),
        ),
      },
      override: {
        _ambientJwtProvider.overrideWith(() => request.jwt),
        _emailProvider.overrideWith(
          () => _Email(
            (email) {
              sendRequest(SendEmailRequest(email, jwt: request.jwt));
            },
            (builtIn, to, tableName, variables) {
              sendRequest(
                SendBuiltInEmailRequest(
                  builtIn,
                  to: to,
                  variables: variables,
                  table: tableName,
                  jwt: request.jwt,
                ),
              );
            },
          ),
        ),
        // Awaited by its caller rather than queued as a side effect: `push`
        // hands back the id of the job row the host just committed, and a
        // queued mutation cannot report anything. The wait is for the *write*,
        // not the fan-out -- see [EnqueuePushRequest].
        _pushProvider.overrideWith(
          () => _Push((message, {required table, required column, where}) async {
            final result = await sendRequest(
              EnqueuePushRequest(
                message: message,
                table: table,
                column: column,
                where: where,
                jwt: request.jwt,
              ),
            );

            if (result case EnqueuePushResponse(:final jobId)) {
              if (jobId == null) {
                throw StateError(
                  'Cannot send a push notification: AppConfig.push is not '
                  'configured for this flavor',
                );
              }
              return PushJobId(jobId);
            }

            throw StateError(
              'Unexpected response to push enqueue: ${result?.path}',
            );
          }),
        ),
        _mutateProvider.overrideWith(
          () => _Mutate(
            update: ({required tableName, required updates, required where, limit}) {
              queueSideEffect(
                sendRequest(
                  UpdateRecordRequest(
                    table: tableName,
                    updates: updates,
                    where: where,
                    jwt: request.jwt,
                    parent: request,
                  ),
                  expectResponse: false,
                ),
              );
            },
            delete: ({required tableName, required where, limit}) {
              queueSideEffect(
                sendRequest(
                  DeleteRecordRequest(
                    table: tableName,
                    where: where,
                    limit: limit,
                    parent: request,
                    jwt: request.jwt,
                  ),
                  expectResponse: false,
                ),
              );
            },
            create: ({required tableName, required objects}) {
              queueSideEffect(
                sendRequest(
                  CreateRecordRequest(
                    table: tableName,
                    objects: objects,
                    parent: request,
                    jwt: request.jwt,
                  ),
                  expectResponse: false,
                ),
              );
            },
            // Awaited, not queued as a side effect: a purge is answered
            // directly by the host rather than parked against `request`'s id
            // and replayed when its response arrives. That difference is the
            // point -- see [PurgeRecordsRequest].
            purge: ({required tableName, required where}) async {
              final result = await sendRequest(
                PurgeRecordsRequest(table: tableName, where: where, jwt: request.jwt),
              );

              if (result case PurgeRecordsResponse(:final rowsAffected)) {
                return rowsAffected;
              }

              logger.error('Unexpected response to purge of "$tableName": ${result?.path}');
              return 0;
            },
          ),
        ),
      },
    );
  }

  /// Asks the host process for data by writing a framed [request] to stdout
  /// and waiting for a matching [Response] on stdin (same [id]).
  ///
  /// A host [MessageErrorResponse] is turned into [MessageHandlerFailedException].
  Future<Response?> sendRequest(Request request, {bool expectResponse = true}) async {
    if (!_listening) {
      assert(false, 'Cannot send a request while not listening');
      return null;
    }
    Completer<Response>? completer;
    if (expectResponse) {
      completer = Completer<Response>();
      _pendingHostReplies[request.id] = completer;
    }

    try {
      io.send(request.toJson());
    } catch (e) {
      _pendingHostReplies.remove(request.id);
      assert(false, 'Failed to encode request: $e');
      return null;
    }

    return await completer?.future;
  }

  void reply(Response? message) {
    if (message == null) return;
    assert(_listening, 'Cannot send a message while not listening');

    try {
      io.send(message.toJson());
    } catch (e) {
      assert(false, 'Failed to encode message: $e');
      print('Failed to encode message: $e');
      return;
    }
  }

  void _deliverHostReply(Response response) {
    final completer = _pendingHostReplies.remove(response.id);
    if (completer == null) {
      logger.error('Received response for unknown request: ${response.id}');
      return;
    }
    try {
      if (response is MessageErrorResponse) {
        completer.completeError(
          MessageHandlerFailedException(
            response.message,
            cause: response.error,
            causeStackTrace: response.stackTrace,
          ),
        );
      } else {
        completer.complete(response);
      }
    } on Object catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    }
  }

  void dispose() {
    io.dispose();
  }
}
