import '../../ca/params.dart';
import '../entities/emulator.entity.dart';

class EmulatorLaunchParams extends Params {
  const EmulatorLaunchParams({required this.emulator, this.coldBoot = false});

  final EmulatorEntity emulator;
  final bool coldBoot;
}
