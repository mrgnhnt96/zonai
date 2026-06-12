/// Generated HTTP client for the Zonai Revali server.
///
/// Import this library to access [ZonaiClient], [ZonaiStorage], and all
/// request/response body types re-exported from `zonai_schema`.
library;

export 'package:zonai_schema/zonai_schema.dart'
    show
        AdminSendMagicLinkAuthBody,
        AdminSendOtpAuthBody,
        AdminSignInAuthBody,
        AdminVerifyMagicLinkAuthBody,
        AdminVerifyOtpAuthBody,
        AuthBody,
        CountBody,
        CreateBody,
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
export 'src/utils/zonai_storage.dart';
