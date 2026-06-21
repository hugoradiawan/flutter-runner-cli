import 'data_source.dart' show LocalDataSource, RemoteDataSource;
import 'failures/app_failure.dart' show AppFailure;

abstract class Repository<
  R extends RemoteDataSource<AppFailure>,
  L extends LocalDataSource<AppFailure>
> {
  Repository(this.remote, this.local);

  final R remote;
  final L local;
}

abstract class RemoteRepository<R extends RemoteDataSource<AppFailure>> {
  RemoteRepository(this.remote);

  final R remote;
}

abstract class LocalRepository<L extends LocalDataSource<AppFailure>> {
  LocalRepository(this.local);

  final L local;
}
