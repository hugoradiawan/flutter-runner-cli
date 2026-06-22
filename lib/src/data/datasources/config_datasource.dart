import '../../ca/data_source.dart';
import '../../domain/failures/config_failure.dart';
import '../models/frun_config.dart';
import 'config_store.dart';

class ConfigDataSource extends LocalDataSource<ConfigFailure> {
  ConfigDataSource(this.store);

  final ConfigStore store;

  String get path => store.path;

  FrunConfig load() => store.load();

  void save(FrunConfig config) => store.save(config);
}
