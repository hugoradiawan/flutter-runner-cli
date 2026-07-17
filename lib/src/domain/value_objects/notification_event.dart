/// Desktop-notification events emitted at interesting app-lifecycle moments.
enum FrunNotifEvent {
  appLaunching,
  appStarted,
  hotReloading,
  hotReloaded,
  restarting,
  restarted,
  openingDevTools,
  devToolsReady,
  enteringInspect,
  inspectReady,
  launchingEmulator,
  emulatorReady,
  melosRunning,
  melosDone,
  melosFailed;

  String get defaultBody {
    switch (this) {
      case appLaunching:
        return 'Launching app…';
      case appStarted:
        return 'App started';
      case hotReloading:
        return 'Hot reloading…';
      case hotReloaded:
        return 'Hot reload complete';
      case restarting:
        return 'Restarting…';
      case restarted:
        return 'Restart complete';
      case openingDevTools:
        return 'Opening DevTools…';
      case devToolsReady:
        return 'DevTools ready';
      case enteringInspect:
        return 'Inspector ON — tap widgets to jump to source';
      case inspectReady:
        return 'Inspector ready';
      case launchingEmulator:
        return 'Launching emulator…';
      case emulatorReady:
        return 'Emulator ready';
      case melosRunning:
        return 'Running melos…';
      case melosDone:
        return 'melos command finished';
      case melosFailed:
        return 'melos command failed';
    }
  }
}
