/// Generated HTTP client for the Zonai Revali server.
///
/// Import this library to access [ZonaiClient] and all request/response body
/// types re-exported from `zonai_schema`.
///
/// For file-backed [Storage] on VM targets, import `package:zonai_client/storage.dart`
/// or pass `storage: ZonaiFileStorage(directory: '...')` to [ZonaiClient].
library;

export 'src/auth.dart' show Auth;
export 'package:zonai_schema/payloads.dart'
    show
        AdminSendMagicLinkAuthBody,
        AdminSendOtpAuthBody,
        AdminSignInAuthBody,
        AdminVerifyMagicLinkAuthBody,
        AdminVerifyOtpAuthBody,
        AuthBody,
        CountBody,
        CreateBody,
        CreateManyBody,
        DeleteBody,
        DeleteOneBody,
        Email,
        GetBody,
        ListBody,
        PhotoCreateMeta,
        ResetPasswordAuthBody,
        SendMagicLinkAuthBody,
        SendMagicLinkEmail,
        SendOtpAuthBody,
        SendOtpEmail,
        SendResetPasswordEmail,
        SendVerifyEmailEmail,
        SignInAuthBody,
        SignUpAuthBody,
        StreamBody,
        StreamCountBody,
        StreamListBody,
        UpdateBody,
        UpdateOneBody,
        VerifyAuthBody;

export 'src/zonai_client.dart';
