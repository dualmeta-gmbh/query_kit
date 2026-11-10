/// The shape D2 declined, written out as the control: a setter and an
/// updater whose data type is a type parameter of the *operation*, in the
/// style of the raw client's `setQueryData<T>`.
///
/// `boundary/generic_setter.dart` shows what the analyzer makes of them, and
/// `runtime/observations.dart` what the cache then holds.
library;

import '../surface.dart';

/// `client.setData<T>(TypedQueryKey<T> key, T value)`, D2's option (a).
T setData<T>(QueryClient client, TypedQueryKey<T> key, T value) =>
    client.setQueryData<T>(key.rawKey, value);

/// The same for an updater.
T? updateData<T>(
  QueryClient client,
  TypedQueryKey<T> key,
  T? Function(T? previous) updater,
) =>
    client.updateQueryData<T>(key.rawKey, updater);

/// And spelled as a method of the client, which changes nothing.
extension ClientStyleSetter on QueryClient {
  T setTyped<T>(TypedQueryKey<T> key, T value) =>
      setQueryData<T>(key.rawKey, value);
}
