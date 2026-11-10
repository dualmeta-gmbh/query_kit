/// The typed samples of the dependent and parallel queries guides, beside
/// their raw ones in `c4a_guides.dart`: the same home, the same devices and
/// the same repository, declared as definitions.
///
/// A library of its own because the devices of `c4a_guides.dart` are not
/// the devices of `typed_guides.dart`: each set of pages has its own small
/// domain, and one library cannot import two classes named `Device`.
library;

import 'package:flutter/material.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'c4a_guides.dart' show Device, EnergyReading, repository;

final QueryNamespace devices = QueryNamespace(<Object?>['devices']);

// ---------------------------------------------------------------------------
// guides/dependent-queries.md
// ---------------------------------------------------------------------------

// >>> guides/dependent-queries.md#typed-home-devices
/// ['devices', 'home', homeId]. The input is nullable, so "no home yet" has
/// a reference too, and the definition says what it does then: wait.
final QueryFamily<String?, List<Device>> homeDevices =
    QueryFamily<String?, List<Device>>(
  namespace: devices,
  name: 'home',
  queryFn: (homeId, context) =>
      repository.homeDevices(homeId!, signal: context.signal),
  // No home yet: nothing to ask the server.
  configure: (base, homeId) =>
      base.copyWith(enabled: homeId == null ? Enabled.no : Enabled.yes),
);

// The screen reads homeDevices(account.dataOrNull?.homeId).options().
// <<<

QueryObserverOptions<List<Device>> typedHomeDevicesQuery(String? homeId) =>
    homeDevices(homeId).options();

// ---------------------------------------------------------------------------
// guides/parallel-queries.md
// ---------------------------------------------------------------------------

// >>> guides/parallel-queries.md#typed-energy
/// ['energy', 'reading', deviceId]
final QueryFamily<String, EnergyReading> energy =
    QueryFamily<String, EnergyReading>(
  namespace: QueryNamespace(<Object?>['energy']),
  name: 'reading',
  queryFn: (deviceId, context) =>
      repository.energy(deviceId, signal: context.signal),
);

// One reading per device on screen — however many that is.
Widget energyPanel(List<String> deviceIds) =>
    QueriesBuilder<EnergyReading, double>(
      queries: <QuerySelectOptions<EnergyReading, double>>[
        for (final id in deviceIds)
          energy(id).options().withSelect((reading) => reading.watts),
      ],
      builder: (context, results) => switch (results.combine(
        (watts) => watts.fold<double>(0, (sum, each) => sum + each),
      )) {
        CombinedPending() => const Text('Measuring…'),
        CombinedError(:final error) => Text('No reading: $error'),
        CombinedData(:final data) => Text('${data.toStringAsFixed(1)} W now'),
      },
    );
// <<<

/// The indicator's filters, from the namespace: every key under ['devices'].
IsFetchingController devicesFetching(QueryClient client) =>
    IsFetchingController(client, filters: devices.filters());
