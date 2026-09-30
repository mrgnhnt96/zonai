import 'package:test/test.dart';
import 'package:zonai/deps.dart';

import '../routes/components/exception_catcher.dart';

/// An update refused on its `expect` answers 412 with the structured envelope
/// `zonai_client`'s `PreconditionFailedException.tryFrom` reads.
///
/// Pinned key-for-key for the reason `password_reset_required_envelope_test`
/// gives: a client branches on `error.code` and reads `error.details.current`,
/// so renaming either is a silent break no route-drift check would report.
/// This pins the mapping, not the wiring -- the e2e test
/// `apps/zonai/test/e2e/update_precondition_e2e_test.dart` covers the engine.
void main() {
  const catcher = Exceptions();

  test('a failed precondition renders 412 with the current rows', () {
    final handled = catcher
        .onCrudException(
          const PreconditionFailedException(
            table: 'notes',
            current: [
              {'id': 'n1', 'rev': 4},
            ],
          ),
        )
        .asHandled;

    expect(handled.statusCode, 412);
    expect(handled.body, {
      'error': {
        'code': 'precondition_failed',
        'message': 'The update was refused: a target row does not meet expect',
        'details': {
          'current': [
            {'id': 'n1', 'rev': 4},
          ],
        },
      },
    });
  });

  test('control: a missing row is still a 404, not a 412', () {
    final handled = catcher
        .onCrudException(const RecordNotFoundException(table: 'notes'))
        .asHandled;

    expect(handled.statusCode, 404);
  });
}
