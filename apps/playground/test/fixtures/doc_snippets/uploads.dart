// Stand-in for the `uploads` table the docs invent for the keyed rate-limit
// counter example. See tasks.dart for why these fixtures exist and when to
// extend them.
import 'package:zonai_schema/zonai_schema.dart';

import 'ids.dart';

final class Upload {
  const Upload({
    required this.id,
    required this.apiKey,
    required this.installId,
  });

  final UploadsId id;
  final String apiKey;
  final String? installId;
}

final class UploadTable extends Table<Upload> {
  UploadTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: UploadsId.new,
        generate: UploadsId.generate,
      ),
      apiKey = $.text('api_key', (s) => s.apiKey),
      installId = $.text('install_id', (s) => s.installId);

  @override
  Upload fromRow(RowReader read) =>
      Upload(id: read(id), apiKey: read(apiKey), installId: read(installId));

  final IdColumn<UploadsId> id;
  final TextColumn apiKey;
  final ColumnType<String?> installId;
}

final uploads = table('uploads', UploadTable.new);
