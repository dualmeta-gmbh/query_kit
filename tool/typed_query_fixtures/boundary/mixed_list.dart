/// D9's boundary: a list of references of two data types handed to
/// `QueriesObserver` **compiles**, as a list of raw options does. The list's
/// element type is the common supertype, so the observer is one of
/// `Object`, and it builds `Object` entries that every exact typed read then
/// refuses. What the cache holds afterwards is `runtime/observations.dart`.
///
/// Outside the guarantee, documented. A list of one data type is exact, and
/// that is the control at the end.
library;

import '../support/models.dart';
import '../support/static_type.dart';
import '../surface.dart';

void mixedList(QueryClient client) {
  final device = queries.devices.detail('d1');
  final list = queries.devices.list;

  // Two data types: `Device` and `List<Device>` meet at `Object`.
  final mixed = [device.options(), list.options()];
  mixed.expectStaticType<Exactly<List<QueryObserverOptions<Object>>>>();

  QueriesObserver(client, mixed)
      .expectStaticType<Exactly<QueriesObserver<Object, Object>>>();

  // Inline, the same.
  QueriesObserver(client, [device.options(), list.options()])
      .expectStaticType<Exactly<QueriesObserver<Object, Object>>>();

  // One data type: exact.
  QueriesObserver(client, [
    queries.devices.detail('d1').options(),
    queries.devices.detail('d2').options(),
  ]).expectStaticType<Exactly<QueriesObserver<Device, Device>>>();

  // A list of references of two data types is not a list of references:
  // what a family's reference and a definition share is the target, which
  // has the lifecycle operations and no data type. (The write on its
  // elements is refused in `negative/surface_limits.dart`.)
  final targets = [device, list];
  targets.expectStaticType<Exactly<List<QueryTarget>>>();
  for (final target in targets) {
    target.invalidate(client).ignore();
  }
}
