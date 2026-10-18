import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:revali_router/revali_router.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai_schema/src/handlers/webhooks/webhook_message.dart';
import 'package:zonai_server/src/handlers/webhook_handler.dart';

import '../routes/components/webhook_rate_limit.dart';
import '../routes/controllers/hook_controller.dart';

/// `POST /hooks/:name` hands the app's webhook the delivery as it was sent
/// -- a signature is over the exact bytes -- and answers with what the
/// webhook picked.
///
/// Driven through [HookController] with a stub [ZonaiDb] standing in for the
/// webhooks worker, which is covered next to it in zonai_schema.
void main() {
  late _StubZonaiDb db;

  setUp(() => db = _StubZonaiDb());

  Future<({ResponseImpl response, String body})> post({
    String name = 'resend',
    List<int> body = const [],
    Map<String, Iterable<String>> headers = const {},
  }) {
    return runScoped(
      () async {
        final response = ResponseImpl(requestHeaders: HeadersImpl());
        await HookController(webhookHandler: const WebhookHandler()).handle(
          name: name,
          ipAddress: '203.0.113.9',
          // Split, as a socket would deliver it.
          body: Stream.fromIterable([
            body.take(3).toList(),
            body.skip(3).toList(),
          ]),
          headers: RequestHeadersImpl(headers),
          response: response,
        );
        final bytes = [
          for (final chunk
              in await (response.body.read() ?? const Stream<List<int>>.empty())
                  .toList())
            ...chunk,
        ];
        return (response: response, body: utf8.decode(bytes));
      },
      values: {
        zonaiDbProvider.overrideWith(
          () =>
              () => db,
        ),
      },
    );
  }

  test('hands the webhook the body bytes, headers and ip as sent', () async {
    final body = utf8.encode('{"type": "email.received"} ');

    await post(
      body: body,
      headers: {
        'Svix-Signature': ['v1,abc'],
        'X-Forwarded-For': ['10.0.0.1', '10.0.0.2'],
      },
    );

    expect(db.name, 'resend');
    expect(db.body, body, reason: 'not re-encoded: the signature is over it');
    expect(db.headers?['svix-signature'], 'v1,abc');
    expect(db.headers?['x-forwarded-for'], '10.0.0.1, 10.0.0.2');
    expect(db.ip, '203.0.113.9');
  });

  test("answers with the webhook's status and body", () async {
    db.answer = const HandleWebhookResponse(
      id: 'id',
      found: true,
      status: HttpStatus.unauthorized,
      body: 'bad signature',
    );

    final (:response, :body) = await post();

    expect(response.statusCode, HttpStatus.unauthorized);
    expect(body, 'bad signature');
  });

  test('a name with no webhook is a 404', () async {
    db.answer = const HandleWebhookResponse(
      id: 'id',
      found: false,
      status: HttpStatus.ok,
    );

    final (:response, :body) = await post(name: 'stripe');

    expect(response.statusCode, HttpStatus.notFound);
    expect(body, isEmpty);
  });

  group(WebhookRateLimit, () {
    test('is a LifecycleComponent, so revali generates it as a guard', () {
      expect(
        const WebhookRateLimit(),
        isA<LifecycleComponent>(),
        reason:
            'without this the annotation is inert and /hooks is unlimited '
            '-- see fix 111b8dfd',
      );
    });

    test('buckets on a reserved constant, not the caller-picked name', () {
      expect(WebhookRateLimit.kWebhookBucket, startsWith('__'));
    });
  });
}

/// A [ZonaiDb] that records the one delivery it is handed.
class _StubZonaiDb implements ZonaiDb {
  HandleWebhookResponse answer = const HandleWebhookResponse(
    id: 'id',
    found: true,
    status: HttpStatus.ok,
  );

  String? name;
  Uint8List? body;
  Map<String, String>? headers;
  String? ip;

  @override
  Future<HandleWebhookResponse> runWebhook({
    required String name,
    required Uint8List body,
    required Map<String, String> headers,
    required String ip,
  }) async {
    this.name = name;
    this.body = body;
    this.headers = headers;
    this.ip = ip;
    return answer;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
