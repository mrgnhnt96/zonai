part of '../client.dart';

class Server {
  Server({HttpClient? client, Storage? storage, Uri? baseUrl})
    : storage = storage ?? SessionStorage() {
    final url = baseUrl?.toString() ?? "http://localhost:8080";

    this.client = RevaliClient(
      client: client ?? HttpPackageClient(),
      baseUrl: url,
      storage: this.storage,
    );

    this.storage.save('__BASE_URL__', url);
  }

  late final RevaliClient client;

  late final Storage storage;

  late final EmailDataSource email = EmailDataSourceImpl(
    client: client,
    storage: storage,
  );

  late final RootDataSource root = RootDataSourceImpl(
    client: client,
    storage: storage,
  );

  late final CronDataSource cron = CronDataSourceImpl(
    client: client,
    storage: storage,
  );

  late final PhotosDataSource photos = PhotosDataSourceImpl(
    client: client,
    storage: storage,
  );

  late final DashboardDataSource dashboard = DashboardDataSourceImpl(
    client: client,
    storage: storage,
  );

  late final DbDataSource db = DbDataSourceImpl(
    client: client,
    storage: storage,
  );

  late final AuthDataSource auth = AuthDataSourceImpl(
    client: client,
    storage: storage,
  );
}
