import 'package:zonai/src/db_mutator/mailman.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai_schema/src/handlers/rules/rule_request.dart';
import 'package:zonai_schema/src/handlers/rules/rule_response.dart';

class RulesMailman extends Mailman<RuleRequest, RuleResponse> {
  RulesMailman()
    : super(
        debugName: debug,
        executablePath: settings.compiledRulesPath,
        snapshotPath: settings.compiledRulesSnapshotPath,
        sourceEntryPath: settings.generatedRulesEntryPath,
        fromJson: RuleResponse.fromJson,
      );

  static const debug = 'RULES';
}
