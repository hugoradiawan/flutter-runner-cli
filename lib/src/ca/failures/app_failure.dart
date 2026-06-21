abstract class AppFailure {
  const AppFailure({required this.message, this.cause, this.stackTrace});

  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  String get failureType;

  @override
  String toString() {
    final b = StringBuffer('$failureType(message: $message}');
    if (cause != null) b.write(', cause: $cause');
    if (stackTrace != null) b.write('\n$stackTrace');
    b.write(')');
    return b.toString();
  }
}
