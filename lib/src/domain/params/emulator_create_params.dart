import '../../core/base/params.dart';

class EmulatorCreateParams extends Params {
  const EmulatorCreateParams({this.name});

  /// Optional AVD name; the tooling picks one when null.
  final String? name;
}
