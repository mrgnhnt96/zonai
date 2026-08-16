import 'dart:io' show Platform;

import 'package:clock/clock.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/src/utils/email_template_render.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// Thrown when a caller may not use the mail endpoint.
///
/// Carries no detail: "no token", "not an admin" and "not a permitted
/// recipient" are the same answer to anyone asking, and telling them apart
/// would confirm which addresses the server is willing to mail.
class EmailForbiddenException implements Exception {
  const EmailForbiddenException();

  @override
  String toString() => 'Email send refused';
}

/// Thrown when the mail endpoint is being called faster than it allows.
class EmailRateLimitException implements Exception {
  const EmailRateLimitException();

  @override
  String toString() => 'Too many email requests';
}

/// Sends mail on behalf of an authenticated admin.
///
/// Previously this took anything the network offered: no token, no throttle,
/// and a caller-chosen recipient, subject and template. That is an open relay
/// wearing the server's own sending domain and reputation -- a phishing page
/// can be delivered as a genuine, SPF-passing message from the product.
///
/// Three things gate it now, in order of how much they matter:
///
/// 1. **An admin token**, matching `/dashboard` and `/crons`. This is the one
///    that closes the relay.
/// 2. **A throttle**, so a leaked admin token cannot be turned into a bulk
///    sender before anyone notices.
/// 3. **An optional recipient allow-list**, for deployments that only ever
///    mail a fixed set of addresses.
class EmailHandler {
  const EmailHandler();

  /// Requests allowed per [_window], counted per client IP.
  static const _maxPerWindow = 10;
  static const _window = Duration(minutes: 1);

  /// Fixed-window counters, keyed by IP.
  ///
  /// In-process on purpose: it needs to hold under a leaked token with no
  /// schema migration and no round-trip to SQLite on a path that already
  /// talks to an SMTP server. The trade-off is that it counts per isolate, so
  /// a multi-worker deployment gets `workers x _maxPerWindow` -- still a
  /// bound, and still far below "unbounded", which is what was here before.
  static final Map<String, ({DateTime start, int count})> _counters = {};

  /// Recipients this server will mail, or empty for "any".
  ///
  /// Set `ZONAI_EMAIL_RECIPIENTS` to a comma-separated list of addresses to
  /// pin it down. Left unset the admin token is the control, which is the
  /// right default for a general-purpose endpoint.
  static Set<String> get allowedRecipients =>
      parseAllowedRecipients(Platform.environment['ZONAI_EMAIL_RECIPIENTS']);

  /// Parses a recipient allow-list. Empty means "no list configured".
  ///
  /// Split out from [allowedRecipients] because the environment cannot be set
  /// from inside a Dart test, and an allow-list that is never exercised is an
  /// allow-list nobody knows the shape of.
  static Set<String> parseAllowedRecipients(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const {};
    return {
      for (final part in raw.split(','))
        if (part.trim().isNotEmpty) part.trim().toLowerCase(),
    };
  }

  Future<void> send(
    Email email, {
    required String? authorization,
    required String ipAddress,
  }) async {
    final jwt = await zonaiDB.parseJwt(_bearerToken(authorization));
    if (jwt == null || jwt.admin.isAdmin != true) {
      throw const EmailForbiddenException();
    }

    if (!withinRateLimit(ipAddress)) {
      throw const EmailRateLimitException();
    }

    final recipients = allowedRecipients;
    if (recipients.isNotEmpty &&
        !recipients.contains(email.to.address.toLowerCase())) {
      throw const EmailForbiddenException();
    }

    // The template name is joined onto a directory and read off disk;
    // `renderEmailTemplate` rejects anything that could escape it. Checked
    // here too so a bad name is refused before an SMTP connection is opened.
    if (!isValidEmailTemplateName(email.template)) {
      throw const EmailForbiddenException();
    }

    await zonaiDB.sendEmail(email);
  }

  /// Counts this request and reports whether it is within the limit.
  static bool withinRateLimit(String ipAddress) {
    final now = clock.now();
    final existing = _counters[ipAddress];

    if (existing == null || now.difference(existing.start) >= _window) {
      _counters[ipAddress] = (start: now, count: 1);
      return true;
    }

    if (existing.count >= _maxPerWindow) {
      return false;
    }

    _counters[ipAddress] = (start: existing.start, count: existing.count + 1);
    return true;
  }

  /// Clears the throttle. For tests, which must not inherit each other's counts.
  static void resetRateLimits() => _counters.clear();

  static String? _bearerToken(String? authorization) {
    if (authorization == null) return null;

    final trimmed = authorization.trim();
    const prefix = 'Bearer ';
    if (trimmed.length >= prefix.length &&
        trimmed.toLowerCase().startsWith(prefix.toLowerCase())) {
      final token = trimmed.substring(prefix.length).trim();
      return token.isEmpty ? null : token;
    }

    return null;
  }
}
