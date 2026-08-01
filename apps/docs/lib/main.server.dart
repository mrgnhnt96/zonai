/// The entrypoint for the **server** environment.
library;

import 'package:jaspr/server.dart';
import 'package:jaspr_content/components/callout.dart';
import 'package:jaspr_content/components/code_block.dart';
import 'package:jaspr_content/components/header.dart';
import 'package:jaspr_content/components/image.dart';
import 'package:jaspr_content/components/sidebar.dart';
import 'package:jaspr_content/components/theme_toggle.dart';
import 'package:jaspr_content/jaspr_content.dart';
import 'package:jaspr_content/theme.dart';

import 'main.server.options.dart';

void main() {
  Jaspr.initializeApp(options: defaultServerOptions);

  runApp(
    ContentApp(
      templateEngine: MustacheTemplateEngine(),
      parsers: [MarkdownParser()],
      extensions: [
        HeadingAnchorsExtension(),
        TableOfContentsExtension(),
      ],
      components: [
        Callout(),
        CodeBlock(grammars: {
          for (final lang in const [
            'sh', 'bash', 'json', 'yaml', 'sql', 'nginx', 'ini', 'html',
            'dockerfile', 'typescript', 'text', 'rust', 'ruby', 'python',
            'kotlin', 'javascript', 'java', 'go', 'css', 'toml',
          ])
            lang: '{"name":"$lang","scopeName":"source.$lang","patterns":[]}',
        }),
        Image(zoom: true),
      ],
      layouts: [
        DocsLayout(
          header: Header(
            title: 'Zonai',
            logo: '/images/logo.svg',
            items: [
              ThemeToggle(),
            ],
          ),
          sidebar: Sidebar(
            groups: [
              SidebarGroup(
                links: [
                  SidebarLink(text: 'Introduction', href: '/'),
                ],
              ),
              SidebarGroup(
                title: 'Getting Started',
                links: [
                  SidebarLink(text: 'Installation', href: '/getting-started/installation'),
                  SidebarLink(text: 'Quick Start', href: '/getting-started/quick-start'),
                  SidebarLink(text: 'Project Structure', href: '/getting-started/project-structure'),
                ],
              ),
              SidebarGroup(
                title: 'Core Concepts',
                links: [
                  SidebarLink(text: 'How a Request is Processed', href: '/core-concepts/request-pipeline'),
                  SidebarLink(text: 'Workers', href: '/core-concepts/workers'),
                  SidebarLink(text: 'Config Flavors', href: '/core-concepts/config-flavors'),
                ],
              ),
              SidebarGroup(
                title: 'Configuration',
                links: [
                  SidebarLink(text: 'zonai.yaml Reference', href: '/configuration/zonai-yaml'),
                  SidebarLink(text: 'App Config', href: '/configuration/app-config'),
                  SidebarLink(text: 'Environment Variables', href: '/configuration/environment-variables'),
                ],
              ),
              SidebarGroup(
                title: 'Schemas',
                links: [
                  SidebarLink(text: 'Defining Tables', href: '/schemas/defining-tables'),
                  SidebarLink(text: 'Auth Tables', href: '/schemas/auth-tables'),
                  SidebarLink(text: 'Photo Tables', href: '/schemas/photo-tables'),
                ],
              ),
              SidebarGroup(
                title: 'Database',
                links: [
                  SidebarLink(text: 'Migrations Overview', href: '/database/migrations-overview'),
                  SidebarLink(text: 'Generating Migrations', href: '/database/generating-migrations'),
                  SidebarLink(text: 'Applying Migrations', href: '/database/applying-migrations'),
                ],
              ),
              SidebarGroup(
                title: 'Operations',
                links: [
                  SidebarLink(text: 'Overview', href: '/operations/overview'),
                  SidebarLink(text: 'Default Operations', href: '/operations/default-operations'),
                  SidebarLink(text: 'Custom Operations', href: '/operations/custom-operations'),
                  SidebarLink(text: 'Auth Operations', href: '/operations/auth-operations'),
                ],
              ),
              SidebarGroup(
                title: 'Rules',
                links: [
                  SidebarLink(text: 'Overview', href: '/rules/overview'),
                  SidebarLink(text: 'Table Rules', href: '/rules/table-rules'),
                  SidebarLink(text: 'Row Rules', href: '/rules/row-rules'),
                  SidebarLink(text: 'Auth Rules', href: '/rules/auth-rules'),
                  SidebarLink(text: 'Photo Rules', href: '/rules/photo-rules'),
                  SidebarLink(text: 'JWT Claims', href: '/rules/jwt-claims'),
                ],
              ),
              SidebarGroup(
                title: 'Extensions',
                links: [
                  SidebarLink(text: 'Overview', href: '/extensions/overview'),
                  SidebarLink(text: 'Create Hooks', href: '/extensions/create-hooks'),
                  SidebarLink(text: 'Update Hooks', href: '/extensions/update-hooks'),
                  SidebarLink(text: 'Delete Hooks', href: '/extensions/delete-hooks'),
                  SidebarLink(text: 'Auth Hooks', href: '/extensions/auth-hooks'),
                  SidebarLink(text: 'Side Effects: get', href: '/extensions/side-effects-get'),
                  SidebarLink(text: 'Side Effects: mutate', href: '/extensions/side-effects-mutate'),
                  SidebarLink(text: 'Side Effects: email', href: '/extensions/side-effects-email'),
                ],
              ),
              SidebarGroup(
                title: 'Authentication',
                links: [
                  SidebarLink(text: 'Overview', href: '/authentication/overview'),
                  SidebarLink(text: 'Password Auth', href: '/authentication/password-auth'),
                  SidebarLink(text: 'OTP Auth', href: '/authentication/otp-auth'),
                  SidebarLink(text: 'Magic Link Auth', href: '/authentication/magic-link-auth'),
                  SidebarLink(text: 'Session Management', href: '/authentication/session-management'),
                  SidebarLink(text: 'Admin Accounts', href: '/authentication/admin-accounts'),
                ],
              ),
              SidebarGroup(
                title: 'Email',
                links: [
                  SidebarLink(text: 'SMTP Setup', href: '/email/smtp-setup'),
                  SidebarLink(text: 'Built-in Templates', href: '/email/built-in-templates'),
                  SidebarLink(text: 'Custom Templates', href: '/email/custom-templates'),
                  SidebarLink(text: 'Testing Locally', href: '/email/testing-locally'),
                ],
              ),
              SidebarGroup(
                title: 'Rate Limiting',
                links: [
                  SidebarLink(text: 'Overview', href: '/rate-limiting/overview'),
                  SidebarLink(text: 'Configuring Policies', href: '/rate-limiting/configuring-policies'),
                  SidebarLink(text: 'Auth Rate Limits', href: '/rate-limiting/auth-rate-limits'),
                  SidebarLink(text: 'Trusted Proxies', href: '/rate-limiting/trusted-proxies'),
                ],
              ),
              SidebarGroup(
                title: 'Cron Jobs',
                links: [
                  SidebarLink(text: 'Overview', href: '/cron-jobs/overview'),
                  SidebarLink(text: 'Defining a Job', href: '/cron-jobs/defining-a-job'),
                  SidebarLink(text: 'Catch-Up Logic', href: '/cron-jobs/catch-up-logic'),
                  SidebarLink(text: 'Side Effects', href: '/cron-jobs/side-effects'),
                  SidebarLink(text: 'Running Manually', href: '/cron-jobs/running-manually'),
                ],
              ),
              SidebarGroup(
                title: 'CLI Reference',
                links: [
                  SidebarLink(text: 'zonai serve', href: '/cli/serve'),
                  SidebarLink(text: 'zonai build', href: '/cli/build'),
                  SidebarLink(text: 'zonai compile', href: '/cli/compile'),
                  SidebarLink(text: 'zonai dev', href: '/cli/dev'),
                  SidebarLink(text: 'zonai db', href: '/cli/db'),
                  SidebarLink(text: 'zonai rules', href: '/cli/rules'),
                  SidebarLink(text: 'zonai ai', href: '/cli/ai'),
                  SidebarLink(text: 'zonai version', href: '/cli/version'),
                  SidebarLink(text: 'Global Flags', href: '/cli/global-flags'),
                ],
              ),
              SidebarGroup(
                title: 'Dart Client',
                links: [
                  SidebarLink(text: 'Overview', href: '/dart-client/overview'),
                  SidebarLink(text: 'Authentication', href: '/dart-client/authentication'),
                  SidebarLink(text: 'Storage', href: '/dart-client/storage'),
                  SidebarLink(text: 'Database', href: '/dart-client/database'),
                  SidebarLink(text: 'Photos', href: '/dart-client/photos'),
                  SidebarLink(text: 'Email', href: '/dart-client/email'),
                ],
              ),
              SidebarGroup(
                title: 'API',
                links: [
                  SidebarLink(text: 'OpenAPI Specification', href: '/api/openapi-spec'),
                ],
              ),
              SidebarGroup(
                title: 'Deployment',
                links: [
                  SidebarLink(text: 'Building for Production', href: '/deployment/building-for-production'),
                  SidebarLink(text: 'Running the Server', href: '/deployment/running-the-server'),
                  SidebarLink(text: 'Server Binding', href: '/deployment/server-binding'),
                  SidebarLink(text: 'Cross-Compilation', href: '/deployment/cross-compilation'),
                  SidebarLink(text: 'Environment & Secrets', href: '/deployment/environment-and-secrets'),
                ],
              ),
            ],
          ),
        ),
      ],
      theme: ContentTheme(
        primary: ThemeColor(ThemeColors.blue.$500, dark: ThemeColors.blue.$300),
        background: ThemeColor(ThemeColors.slate.$50, dark: ThemeColors.zinc.$950),
      ),
    ),
  );
}
