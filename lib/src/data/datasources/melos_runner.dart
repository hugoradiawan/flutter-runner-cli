import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../domain/entities/melos_run_event.dart';

/// Spawns the `melos` executable and streams its output line-by-line.
///
/// Emits a [MelosRunLine] per stdout/stderr line and a terminal [MelosRunExit]
/// with the process exit code. `runInShell` lets the platform resolve `melos`
/// from PATH (e.g. `melos.bat` on Windows, a pub-global shim elsewhere).
class MelosRunner {
  const MelosRunner({
    Future<Process> Function(
      String executable,
      List<String> args, {
      String? workingDirectory,
      bool runInShell,
    })?
    starter,
  }) : _starter = starter ?? Process.start;

  final Future<Process> Function(
    String executable,
    List<String> args, {
    String? workingDirectory,
    bool runInShell,
  })
  _starter;

  Stream<MelosRunEvent> run(String workDir, List<String> args) {
    late final StreamController<MelosRunEvent> controller;
    Process? process;

    Future<void> start() async {
      try {
        process = await _starter(
          'melos',
          args,
          workingDirectory: workDir,
          runInShell: true,
        );
      } catch (e) {
        if (!controller.isClosed) {
          controller.add(
            MelosRunLine('Failed to start melos: $e', isError: true),
          );
          controller.add(const MelosRunExit(null));
          await controller.close();
        }
        return;
      }

      void emit(String line, {required bool isError}) {
        if (!controller.isClosed) {
          controller.add(MelosRunLine(line, isError: isError));
        }
      }

      final outDone = process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach((l) => emit(l, isError: false));
      final errDone = process!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach((l) => emit(l, isError: true));

      final code = await process!.exitCode;
      await outDone;
      await errDone;
      if (!controller.isClosed) {
        controller.add(MelosRunExit(code));
        await controller.close();
      }
    }

    controller = StreamController<MelosRunEvent>(
      onListen: start,
      onCancel: () => process?.kill(),
    );
    return controller.stream;
  }
}
