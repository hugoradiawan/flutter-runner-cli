/// Barrel for the data layer.
///
/// Sorting rule: `datasources/` hold process/protocol clients (daemon,
/// analysis server, VM service, CLI runners) and repository backings;
/// `services/` hold in-process helpers; `repositories/` implement the
/// domain interfaces. Only `presentation/di/dependencies.dart` and the
/// composition root may import this.
library;

export 'datasources/analysis_server.dart';
export 'datasources/app_session.dart';
export 'datasources/config_datasource.dart';
export 'datasources/config_store.dart';
export 'datasources/dart_analyze_runner.dart';
export 'datasources/device_manager.dart';
export 'datasources/diagnostics_store.dart';
export 'datasources/emulator_manager.dart';
export 'datasources/flutter_daemon.dart';
export 'datasources/inspector_bridge.dart';
export 'datasources/isolate_manager.dart';
export 'datasources/self_vm_inspector.dart';
export 'models/daemon_messages.dart';
export 'models/device.dart';
export 'models/diagnostic.dart';
export 'models/emulator.dart';
export 'models/frun_config.dart';
export 'models/launch_config.dart';
export 'repositories/config_repository_impl.dart';
export 'repositories/device_repository_impl.dart';
export 'repositories/diagnostics_repository_impl.dart';
export 'repositories/emulator_repository_impl.dart';
export 'repositories/launch_repository_impl.dart';
export 'repositories/session_repository_impl.dart';
export 'services/dart_file_watcher.dart';
export 'services/dart_source_walker.dart';
export 'services/desktop_notifier.dart';
export 'services/ide_launcher.dart';
export 'services/live_diagnostics.dart';
export 'services/main_scanner.dart';
export 'services/package_config_uri_resolver.dart';
export 'services/package_locator.dart';
export 'services/project_detector.dart';
export 'services/session_event_mapper.dart';
export 'services/todo_diagnostics.dart';
export 'services/working_set.dart';
