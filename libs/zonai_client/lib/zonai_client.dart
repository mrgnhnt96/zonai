/// Generated HTTP client for the Zonai Revali server.
///
/// Import this library to access [ZonaiClient] and all request/response body
/// types re-exported from `zonai_schema`.
///
/// For file-backed [Storage] on VM targets, import `package:zonai_client/storage.dart`
/// or pass `storage: ZonaiFileStorage(directory: '...')` to [ZonaiClient].
library;

export 'src/admin_auth.dart' show AdminAuth;
export 'src/auth.dart' show Auth;
export 'src/db.dart' show Db;
export 'src/db_listen.dart' show DbListen;
export 'src/emails.dart' show Emails;
// The one typed failure zonai's own error envelope produces. A consumer that
// cannot NAME it cannot catch it, and the whole point of the 403 is that it is
// recoverable rather than fatal.
export 'src/password_reset_required_exception.dart'
    show PasswordResetRequiredException;
export 'src/photos.dart' show Photos;
// The `Where` / `Update` / `OrderByTerm` vocabulary below is the query surface a
// generated typed client returns and consumes, so a consumer must be able to
// name it. Two members of it are deliberately absent: `Null` and `NotNull`
// (`src/types/where.dart`) would shadow `dart:core`'s `Null` in every library
// that imports this barrel. Build those clauses with `Where.isNull` /
// `Where.isNotNull`, which redirect to them -- see those factories' docs for
// the compiled evidence.
export 'package:zonai_schema/payloads.dart'
    show
        Add,
        AddAll,
        AdminSendMagicLinkAuthBody,
        AdminSendOtpAuthBody,
        AdminSignInAuthBody,
        AdminVerifyMagicLinkAuthBody,
        AdminVerifyOtpAuthBody,
        And,
        AuthBody,
        AuthSession,
        ColumnUpdate,
        Contains,
        CountBody,
        CreateBody,
        CreateManyBody,
        Decrement,
        DeleteBody,
        DeleteOneBody,
        Email,
        EndsWith,
        Eq,
        GetBody,
        Gt,
        Gte,
        In,
        Increment,
        ListBody,
        Literal,
        Lt,
        Lte,
        NotContains,
        NotIn,
        OAuthProviderKind,
        OAuthProviderPublic,
        ObjectUpdate,
        Or,
        OrderByTerm,
        PhotoCreateMeta,
        Remove,
        RemoveAll,
        ResetPasswordAuthBody,
        SendMagicLinkAuthBody,
        SendMagicLinkEmail,
        SendOtpAuthBody,
        SendOtpEmail,
        SendResetPasswordEmail,
        SendVerifyEmailEmail,
        SignInAuthBody,
        SignUpAuthBody,
        SortDirection,
        StartsWith,
        StreamBody,
        StreamCountBody,
        StreamListBody,
        Update,
        UpdateBody,
        UpdateOneBody,
        UpdateValue,
        VerifyAuthBody,
        Where;

export 'package:zonai_schema/src/types/paginated.dart' show Paginated;

export 'src/utils/zonai_storage_memory.dart'
    show ZonaiMemoryStorage, ZonaiNoStorage, ZonaiStorage;
export 'src/zonai_client.dart';
