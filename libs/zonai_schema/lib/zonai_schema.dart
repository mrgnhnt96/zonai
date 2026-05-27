/// Shared table definitions and database types for Zonai.
library;

export 'package:raindrop/raindrop.dart'
    show
        SchemaBuilder,
        ColumnType,
        uniqueIndex,
        index,
        IndexBuilderOn,
        ReferencesColumn,
        RowReader;
export 'package:raindrop_sqlite/raindrop_sqlite.dart'
    show
        BooleanColumnDefinition,
        BooleanColumn,
        BigIntColumn,
        BigIntColumnDefinition,
        IntColumn,
        IntColumnDefinition,
        TextColumn,
        TextColumnDefinition,
        DateTimeColumn,
        DateTimeColumnDefinition,
        RealColumn,
        RealColumnDefinition,
        BlobColumn,
        BlobColumnDefinition;

export 'src/internal/collections.dart' hide setupInternalCollections;
export 'src/internal/photos_collection.dart';

export 'src/config/app_config.dart';
export 'src/config/email_config.dart';
export 'src/types/built_in_emails.dart';
export 'src/types/email_address.dart';
export 'src/types/email.dart';
export 'src/column_types/email_column.dart';
export 'src/column_types/is_verified_column.dart';
export 'src/column_types/enum_column.dart';
export 'src/column_types/password_column.dart';
export 'src/column_types/create_primary_key.dart';
export 'src/column_types/created_at_column.dart';
export 'src/column_types/id_column.dart';
export 'src/column_types/list_column.dart';
export 'src/column_types/map_column.dart';
export 'src/column_types/updated_at_column.dart';
export 'src/extension.dart';
export 'src/handlers/messages/message_handler.dart' hide Request;
export 'src/rate_limit/rate_limit_policy.dart';
export 'src/types/rate_limit_operation.dart';
export 'src/rate_limits/collection/rate_limits.dart'
    show AuthCollectionRateLimits, CollectionRateLimits, RateLimits;
export 'src/operations/collection_operations.dart';
export 'src/raw_sql_filter.dart';
export 'src/rules/rules.dart'
    hide
        BaseCollectionRules,
        BaseRecordRules,
        InternalCollectionRules,
        InternalRecordRules;
export 'src/schemas/auth_collection.dart' hide Auth;
export 'src/schemas/collection.dart';
export 'src/tables/auth_collection.dart';
export 'src/tables/collection.dart';
export 'src/types/id.dart';
export 'src/types/supported_auths.dart';
export 'src/types/where.dart';
export 'src/types/order_by.dart';
export 'src/types/paginated.dart';
export 'src/update/update.dart';
export 'src/types/jwt.dart';
export 'src/types/jwt_id.dart';

export 'payloads.dart';
