// The host side of `flutter drive` for the native suite's web run
// (`e2e-native/run.sh web`): it starts the app in Chrome and reports what
// the tests inside it found.
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
