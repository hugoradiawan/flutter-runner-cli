import '../../core/base/params.dart';
import '../entities/diagnostic.dart';

class DiagnosticsFilterParams extends Params {
  const DiagnosticsFilterParams({this.category, this.text});

  final DiagnosticCategory? category;
  final String? text;
}
