import '../../ca/params.dart';

class ConfigGetParams extends Params {
  const ConfigGetParams({required this.key});

  final String key;
}

class ConfigSetParams extends Params {
  const ConfigSetParams({required this.key, required this.value});

  final String key;
  final String value;
}
