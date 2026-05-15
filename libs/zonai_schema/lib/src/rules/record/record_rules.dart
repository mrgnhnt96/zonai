part of rules;

class RecordRules<S extends Collection<R>, R> extends BaseRecordRules<S, R>
    implements Rules<S, R> {
  const RecordRules(super.schema);
}
