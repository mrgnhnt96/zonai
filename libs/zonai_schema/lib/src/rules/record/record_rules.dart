part of rules;

class RecordRules<T extends Collection<T>> extends BaseRecordRules<T>
    implements Rules<T> {
  const RecordRules(super.schema);
}
