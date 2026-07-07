import '../../core/base/params.dart';

class ConfigSetParams extends Params {
  const ConfigSetParams({required this.key, required this.value});

  final String key;
  final String value;
}
