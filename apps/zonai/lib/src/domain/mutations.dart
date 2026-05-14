import 'package:zonai_schema/zonai_schema.dart' hide logger;

class Mutations {
  Mutations({this.track = true}) : _mutations = [], _missed = [];

  final bool track;
  final List<MutationRequest> _mutations;
  final List<MutationRequest> _missed;

  List<MutationRequest> get extract {
    final muts = _mutations.toList();
    _mutations.clear();
    return muts;
  }

  bool addAll(List<MutationRequest> mutations) {
    if (!track) {
      _missed.addAll(mutations);
      return false;
    }
    _mutations.addAll(mutations);

    return true;
  }

  int get count => _mutations.length;
  List<MutationRequest> get missed => List.unmodifiable(_missed);
}
