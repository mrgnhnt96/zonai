import 'dart:io';

/// Whether the process is running in a known CI environment.
bool get isCiEnvironment {
  final ci = Platform.environment['CI'];
  if (ci == 'true' || ci == '1') {
    return true;
  }

  const ciVariables = [
    'GITHUB_ACTIONS',
    'GITLAB_CI',
    'BUILDKITE',
    'JENKINS_URL',
    'CIRCLECI',
    'TRAVIS',
    'TF_BUILD', // Azure Pipelines
  ];

  return ciVariables.any(Platform.environment.containsKey);
}
