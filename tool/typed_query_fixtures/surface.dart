/// The one import every fixture takes its API from.
///
/// Phase 0 (TQ0) proved the surface against a prototype that was exported
/// from here beside the package. Phase 1 (TQ1) moved the implementation
/// into `package:query_kit` and deleted that export and the prototype:
/// every fixture now analyzes and runs against the package alone.
library;

export 'package:query_kit/query_kit.dart';
