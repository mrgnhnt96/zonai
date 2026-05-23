import 'package:zonai_schema/zonai_schema.dart';

class RateLimitEntry {
  RateLimitEntry({
    required this.clientIp,
    required this.operation,
    required this.collection,
    required this.windowStart,
  }) : id = RateLimitId.generate(),
       count = 1;

  RateLimitEntry._({
    required this.id,
    required this.clientIp,
    required this.operation,
    required this.collection,
    required this.count,
    required this.windowStart,
  });

  final RateLimitId id;
  final String clientIp;
  final String collection;
  final RateLimitOperation operation;
  final int count;
  final DateTime windowStart;
}

class RateLimitId implements Id {
  RateLimitId(this.value);
  static RateLimitId generate() => RateLimitId(Id.generate('rl'));

  @override
  final String value;
}

class RateLimitCollection extends Collection<RateLimitEntry> {
  RateLimitCollection(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: RateLimitId.new,
        generate: RateLimitId.generate,
      ),
      clientIp = $.text('client_ip', (s) => s.clientIp),
      operation = $.enumerator(
        'operation',
        RateLimitOperation.values,
        (s) => s.operation,
      ),
      collection = $.text('collection', (s) => s.collection),
      count = $.integer('count', (s) => s.count),
      windowStart = $.dateTime('window_start', (s) => s.windowStart);

  @override
  RateLimitEntry fromRow(RowReader read) {
    return RateLimitEntry._(
      id: read(id),
      clientIp: read(clientIp),
      operation: read(operation),
      collection: read(collection),
      count: read(count),
      windowStart: read(windowStart),
    );
  }

  final IdColumn<RateLimitId> id;
  final TextColumn clientIp;
  final EnumColumn<RateLimitOperation> operation;
  final TextColumn collection;
  final IntColumn count;
  final DateTimeColumn windowStart;
}

final rateLimits = collection('_rate_limit', RateLimitCollection.new, (table) {
  uniqueIndex(
    'rate_limit_bucket_unique',
  ).on(table.clientIp, table.collection, table.operation);
});
