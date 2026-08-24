/// Every name `package:zonai_client/zonai_client.dart` exports.
///
/// The generated barrel re-exports that library, so a table that mints one of
/// these names would make the barrel export it twice. That is an ambiguous
/// export and the generated client does not compile at all -- reproduced with
/// a table named `photos`, whose token holder is `Photos`.
///
/// The emitter hides exactly the overlap from the re-export rather than
/// refusing the table. Refusing was the other option and it costs too much:
/// all nine names in `TableNames.all` can collide, not only the bare base, so
/// a refusal would make 25 ordinary table names ungeneratable -- `photos`,
/// `emails`, `db`, `column` (via `ColumnUpdate`) and `object` (via
/// `ObjectUpdate`) among them. A project with a `photos` table generates
/// today; a re-export it never asked for must not take that away.
///
/// This list is hand-maintained because it has to be. `apps/zonai` depends on
/// `zonai_schema`, not on `zonai_client`: the dependency arrow points
/// generated -> `zonai_client` and never back (§7), so the CLI cannot read
/// that barrel at generation time. `client_package_exports_test.dart` derives
/// the set from the real file and fails in EITHER direction of drift, which is
/// the same defence `kClientRuntimeExports` carries and for the same reason --
/// a second hand-written copy is a new thing to forget.
///
/// What it cannot know is the `zonai_client` a *consumer* resolves. This is
/// the CLI's idea of the package, fixed when the CLI was built. A consumer on
/// a newer `zonai_client` that exports a name absent from this list gets no
/// hide clause for it and their build fails with an ambiguous export naming
/// the barrel. That is survivable -- a compile error in their project, not
/// silence -- but this is a floor, not a proof.
library;

const kZonaiClientExports = <String>[
  'Add',
  'AddAll',
  'AdminAuth',
  'AdminSendMagicLinkAuthBody',
  'AdminSendOtpAuthBody',
  'AdminSignInAuthBody',
  'AdminVerifyMagicLinkAuthBody',
  'AdminVerifyOtpAuthBody',
  'And',
  'Auth',
  'AuthBody',
  'AuthSession',
  'ColumnUpdate',
  'Contains',
  'CountBody',
  'CreateBody',
  'CreateManyBody',
  'Db',
  'DbListen',
  'Decrement',
  'DeleteBody',
  'DeleteOneBody',
  'Email',
  'Emails',
  'EndsWith',
  'Eq',
  'GetBody',
  'Gt',
  'Gte',
  'In',
  'Increment',
  'ListBody',
  'Literal',
  'Lt',
  'Lte',
  'NotContains',
  'NotIn',
  'OAuthProviderKind',
  'OAuthProviderPublic',
  'ObjectUpdate',
  'Or',
  'OrderByTerm',
  'Paginated',
  'PasswordResetRequiredException',
  'PhotoCreateMeta',
  'Photos',
  'Remove',
  'RemoveAll',
  'ResetPasswordAuthBody',
  'SendMagicLinkAuthBody',
  'SendMagicLinkEmail',
  'SendOtpAuthBody',
  'SendOtpEmail',
  'SendResetPasswordEmail',
  'SendVerifyEmailEmail',
  'SignInAuthBody',
  'SignUpAuthBody',
  'SortDirection',
  'StartsWith',
  'StreamBody',
  'StreamCountBody',
  'StreamListBody',
  'Update',
  'UpdateBody',
  'UpdateOneBody',
  'UpdateValue',
  'VerifyAuthBody',
  'Where',
  'ZonaiClient',
  'ZonaiMemoryStorage',
  'ZonaiNoStorage',
  'ZonaiStorage',
];
