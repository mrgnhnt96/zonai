// Statements that use a `ZonaiClient` -- the `client.db.list(...)` /
// `client.email.send(...)` calls the dart-client pages show once the page has
// already established how the client is constructed.
//
// `client` and `photoId` are getters rather than locals for the reason given
// in side-effects.dart: the fragment needs their type, not a value.
import 'dart:io';

import 'package:zonai_client/zonai_client.dart';
import 'package:zonai_schema/zonai_schema.dart'
    show EmailAddress, Eq, Update, UpdateValue;

class ClientExample {
  ZonaiClient get client => throw UnimplementedError();
  String get photoId => throw UnimplementedError();

  Future<void> run() async {
    // Referenced so the dart:io import is not flagged unused by a doc that
    // does not happen to use File.
    File('unused');

    // <<body>>
  }
}
