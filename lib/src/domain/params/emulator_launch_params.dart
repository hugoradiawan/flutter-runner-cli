import '../../core/base/params.dart';
import '../entities/emulator.dart';

class EmulatorLaunchParams extends Params {
  const EmulatorLaunchParams({required this.emulator, this.coldBoot = false});

  final EmulatorEntity emulator;
  final bool coldBoot;
}
