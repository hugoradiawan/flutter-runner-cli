/// Barrel for the domain layer: entities, value objects, params, failures,
/// ports, repository interfaces, and use cases.
///
/// Layer rules: domain depends only on core; data and presentation may
/// depend on domain; presentation touches concrete data types only in
/// `presentation/di/dependencies.dart` and the composition root.
library;

export 'entities/app_config.dart';
export 'entities/device.dart';
export 'entities/diagnostic.dart';
export 'entities/emulator.dart';
export 'entities/flutter_project.dart';
export 'entities/isolate_info.dart';
export 'entities/launch_entry.dart';
export 'entities/run_session.dart';
export 'entities/session_event.dart';
export 'failures/analysis_failure.dart';
export 'failures/config_failure.dart';
export 'failures/daemon_failure.dart';
export 'failures/device_failure.dart';
export 'failures/ide_failure.dart';
export 'failures/launch_failure.dart';
export 'failures/session_failure.dart';
export 'params/config_params.dart';
export 'params/diagnostics_filter_params.dart';
export 'params/emulator_create_params.dart';
export 'params/emulator_launch_params.dart';
export 'params/reload_params.dart';
export 'params/session_params.dart';
export 'ports/ide_launcher.dart';
export 'ports/isolate_control.dart';
export 'ports/notifier.dart';
export 'ports/source_change_watcher.dart';
export 'ports/vm_uri_resolver.dart';
export 'repositories/config_repository.dart';
export 'repositories/device_repository.dart';
export 'repositories/diagnostics_repository.dart';
export 'repositories/emulator_repository.dart';
export 'repositories/launch_repository.dart';
export 'repositories/session_repository.dart';
export 'usecases/analyze_project.dart';
export 'usecases/create_emulator.dart';
export 'usecases/detach_session.dart';
export 'usecases/discover_launch_entries.dart';
export 'usecases/get_config.dart';
export 'usecases/get_diagnostics.dart';
export 'usecases/hot_reload.dart';
export 'usecases/hot_restart.dart';
export 'usecases/launch_emulator.dart';
export 'usecases/list_devices.dart';
export 'usecases/list_emulators.dart';
export 'usecases/save_config.dart';
export 'usecases/set_config.dart';
export 'usecases/start_session.dart';
export 'usecases/stop_session.dart';
export 'usecases/watch_diagnostics.dart';
export 'value_objects/config_values.dart';
export 'value_objects/notification_event.dart';
export 'value_objects/source_location.dart';
