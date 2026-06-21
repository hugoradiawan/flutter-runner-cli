import '../../ca/data_source.dart';
import '../../config/config_store.dart';
import '../../domain/failures/config_failure.dart';

class ConfigDataSource extends LocalDataSource<ConfigFailure> {
  ConfigDataSource(this.store);

  final ConfigStore store;
}
