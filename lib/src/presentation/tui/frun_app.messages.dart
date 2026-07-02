part of 'frun_app.dart';

// ─── Domain messages dispatched by hit-regions and the entry layer ─────────

final class TickWakeMsg extends Msg {
  const TickWakeMsg();
}

final class SetActiveTabMsg extends Msg {
  const SetActiveTabMsg(this.index);
  final int index;
}

final class ReloadTabMsg extends Msg {
  const ReloadTabMsg(this.index);
  final int index;
}

final class RestartTabMsg extends Msg {
  const RestartTabMsg(this.index);
  final int index;
}

final class StopTabMsg extends Msg {
  const StopTabMsg(this.index);
  final int index;
}

final class RerunTabMsg extends Msg {
  const RerunTabMsg(this.index);
  final int index;
}

final class RunButtonMsg extends Msg {
  const RunButtonMsg();
}

enum IsolatePanelAction { start, refresh, pause, resume, step, kill, stack }

final class CloseIsolatesPanelMsg extends Msg {
  const CloseIsolatesPanelMsg();
}

final class SelectIsolateMsg extends Msg {
  const SelectIsolateMsg(this.index);

  final int index;
}

final class IsolateActionMsg extends Msg {
  const IsolateActionMsg(this.action, {this.id});

  final IsolatePanelAction action;
  final String? id;
}

final class TranscriptLineClickMsg extends Msg {
  TranscriptLineClickMsg(this.action);
  final void Function() action;
}

final class PickLaunchEntryMsg extends Msg {
  const PickLaunchEntryMsg(this.index);
  final int index;
}

final class CloseLaunchPickerMsg extends Msg {
  const CloseLaunchPickerMsg();
}

final class PickEmulatorMsg extends Msg {
  const PickEmulatorMsg(this.index);
  final int index;
}

final class CloseEmulatorPickerMsg extends Msg {
  const CloseEmulatorPickerMsg();
}

final class PickBootModeMsg extends Msg {
  const PickBootModeMsg(this.index);
  final int index;
}

final class CloseBootModePickerMsg extends Msg {
  const CloseBootModePickerMsg();
}

final class PickRunTargetMsg extends Msg {
  const PickRunTargetMsg(this.index);
  final int index;
}

final class CloseRunTargetPickerMsg extends Msg {
  const CloseRunTargetPickerMsg();
}

final class _CycleTabsForwardMsg extends Msg {
  const _CycleTabsForwardMsg();
}

// ─── Diagnostics overlay ───────────────────────────────────────────────────

final class ToggleDiagnosticsOverlayMsg extends Msg {
  const ToggleDiagnosticsOverlayMsg();
}

final class CloseDiagnosticsOverlayMsg extends Msg {
  const CloseDiagnosticsOverlayMsg();
}

final class SetDiagnosticsFilterMsg extends Msg {
  const SetDiagnosticsFilterMsg(this.level);

  /// Category to filter to, or null for "all".
  final DiagnosticCategory? level;
}

final class JumpToDiagnosticMsg extends Msg {
  const JumpToDiagnosticMsg(this.diagnostic);
  final DiagnosticEntity diagnostic;
}
