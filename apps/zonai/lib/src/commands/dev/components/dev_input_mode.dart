enum DevInputMode {
  none,
  migrateGenerate,
  migrateApply,
  adminEmail,
  adminPassword,
  emailTest,
  emailPreview,
  emailTemplate,
  cronRun,
  clearDatabase,
  createPart,
  createSchema,
  rulesJwt,
}

typedef DevHint = (String key, String action);

const _menuHints = <DevHint>[
  ('↑↓', 'navigate'),
  ('enter/space', 'run'),
  ('s', 'server'),
  ('ctrl+l', 'clear'),
  ('q', 'quit'),
];

List<DevHint> devHintsFor(DevInputMode mode, {String? menuKey}) {
  if (mode == DevInputMode.none && menuKey == 'l') {
    return [('esc', 'back'), ..._menuHints];
  }

  return switch (mode) {
    DevInputMode.none || DevInputMode.migrateApply => _menuHints,
    DevInputMode.migrateGenerate => [('esc', 'cancel'), ('enter', 'generate')],
    DevInputMode.emailTemplate => [('esc', 'cancel'), ('enter', 'create')],
    DevInputMode.clearDatabase => [
      ('tab', 'toggle'),
      ('enter', 'submit'),
      ('esc', 'cancel'),
    ],
    DevInputMode.adminEmail || DevInputMode.adminPassword => [
      ('tab', 'next'),
      ('shift+tab', 'back'),
      ('esc', 'cancel'),
      ('enter', 'submit'),
    ],
    DevInputMode.emailTest => [
      ('↑↓', 'template'),
      ('tab', 'next'),
      ('esc', 'cancel'),
      ('enter', 'send'),
    ],
    DevInputMode.emailPreview => [
      ('↑↓', 'template'),
      ('tab', 'next'),
      ('esc', 'cancel'),
      ('ctrl+enter', 'preview'),
    ],
    DevInputMode.cronRun => [
      ('↑↓', 'select'),
      ('esc', 'cancel'),
      ('enter', 'run'),
    ],
    DevInputMode.createPart => [
      ('↑↓', 'select'),
      ('tab', 'next'),
      ('esc', 'cancel'),
      ('enter', 'create'),
    ],
    DevInputMode.createSchema => [
      ('tab', 'next'),
      ('space', 'toggle'),
      ('←→', 'chips'),
      ('esc', 'cancel'),
      ('enter', 'create'),
    ],
    DevInputMode.rulesJwt => [('esc', 'cancel'), ('enter', 'list')],
  };
}
