import '../../ca/params.dart';
import '../entities/diagnostic.entity.dart';

class DiagnosticsFilterParams extends Params {
  const DiagnosticsFilterParams({this.category, this.text});

  final DiagnosticCategory? category;
  final String? text;
}
