/// Shared table definitions and database types for Zonai.
library;

export 'package:zonai_schema/gen/raindrop/raindrop/dialect.dart'
    show SqlDialect;
// `table` is hidden: zonai_schema's own `table()` helper (see
// src/schemas/table.dart) is the developer-facing version -- the vendored
// `TableMeta`/reflection API is internal. `Logger`/`migrate` are hidden
// because they collide with `package:zonai_logger`'s `Logger` and zonai's
// own `migrate` -- callers that need raindrop's originals import the
// vendored path directly with a prefix.
export 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart'
    hide table, Logger, migrate;
// Exported from the column_types sub-barrel directly, not raindrop_sqlite.dart's
// top-level barrel: that one also unconditionally exports sqlite_delegate.dart
// (needs package:sqlite3) and sqlite_table.dart/builders/ -- a `show` clause here
// only filters which NAMES get re-exported, it doesn't stop the compiler from
// having to resolve every file in an unrestricted `export` chain. Importing this
// narrower sub-barrel means a client that only builds queries (no SQLiteDelegate,
// ever) doesn't need sqlite3 resolvable at all. See issue #24.
export 'package:zonai_schema/gen/raindrop/raindrop_sqlite/src/column_types/column_types.dart'
    show
        BooleanColumnDefinition,
        BigIntColumnDefinition,
        IntColumnDefinition,
        TextColumnDefinition,
        DateTimeColumnDefinition,
        RealColumnDefinition,
        BlobColumnDefinition;

export 'src/raindrop_query_compile.dart';
export 'src/column_types/column_type_aliases.dart';

export 'package:cron/cron.dart' show Schedule;

export 'payloads.dart';
export 'src/column_types/create_primary_key.dart';
export 'src/column_types/created_at_column.dart';
export 'src/column_types/email_column.dart';
export 'src/column_types/enum_column.dart';
export 'src/column_types/enum_list_column.dart';
export 'src/column_types/id_column.dart';
export 'src/column_types/is_verified_column.dart';
export 'src/column_types/list_column.dart';
export 'src/column_types/map_column.dart';
export 'src/column_types/password_column.dart';
export 'src/column_types/photo_column.dart';
export 'src/column_types/device_token_column.dart';
export 'src/column_types/photos_column.dart';
export 'src/column_types/secret_column.dart';
export 'src/column_types/server_generated_column.dart';
export 'src/column_types/updated_at_column.dart';
export 'src/column_types/updated_when_column.dart';
export 'src/config/app_config.dart';
export 'src/exceptions/schema_exception.dart';
export 'src/config/email_config.dart';
export 'src/config/external_idp_config.dart';
export 'src/config/photos_config.dart';
export 'src/config/apns_config.dart';
export 'src/config/push_config.dart';
export 'src/config/supabase_external_idp.dart';
export 'src/config/trusted_proxy_config.dart';
export 'src/types/cron_job.dart';
export 'src/types/supabase_claims.dart';
export 'src/extension.dart';
export 'src/handlers/messages/message_handler.dart'
    hide
        Request,
        Response,
        msg,
        nativeLibraryHost,
        NativeLibraryRequest,
        NativeLibraryResponse;
export 'src/internal/tables/abusers_table.dart';
export 'src/internal/tables/photos_table.dart';
export 'src/operations/table_operations.dart';
export 'src/rate_limit/rate_limit_policy.dart';
export 'src/rate_limits/table/rate_limits.dart'
    show AuthTableRateLimits, TableRateLimits, RateLimits;
export 'src/raw_sql_filter.dart';
export 'src/rules/rules.dart'
    hide BaseTableRules, BaseRowRules, InternalTableRules, InternalRowRules;
export 'src/schemas/auth_table.dart' hide Auth;
export 'src/schemas/table.dart';
export 'src/tables/auth_table.dart';
export 'src/tables/table.dart';
export 'src/types/api_token_id.dart';
export 'src/types/api_token_jwt.dart';
export 'src/types/api_token_scope.dart';
export 'src/types/api_token_secret.dart';
export 'src/types/auth_session.dart';
export 'src/types/built_in_emails.dart';
export 'src/types/email.dart';
export 'src/types/email_address.dart';
export 'src/types/id.dart';
export 'src/types/image_mime_type.dart';
export 'src/types/jwt.dart';
export 'src/types/cron_jwt.dart';
export 'src/types/jwt_id.dart';
export 'src/types/oauth/oauth_brand.dart';
export 'src/types/oauth/oauth_claim_map.dart';
export 'src/types/oauth/oauth_endpoints.dart';
export 'src/types/oauth/oauth_icon.dart';
export 'src/types/oauth/oauth_linking.dart';
export 'src/types/oauth/oauth_provider.dart';
export 'src/types/oauth/oauth_provider_kind.dart';
export 'src/types/oauth/oauth_provider_public.dart';
export 'src/types/provisioning_jwt.dart';
export 'src/types/order_by.dart';
export 'src/types/paginated.dart';
export 'src/types/push_message.dart';
export 'src/types/push_outcome.dart';
export 'src/types/rate_limit_operation.dart';
export 'src/types/supported_auths.dart';
export 'src/types/where.dart';
export 'src/types/column_shape_kind.dart';
export 'src/types/schema_shape.dart';
export 'src/schema_shape_from_table.dart';
export 'src/update/update.dart';
