import '../../ca/params.dart';
import '../entities/device.entity.dart';
import '../entities/launch_entry.entity.dart';

class RunParams extends Params {
  const RunParams({required this.entry, required this.device});

  final LaunchEntryEntity entry;
  final DeviceEntity device;
}
