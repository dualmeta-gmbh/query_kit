/// How a fixture pins an inferred static type exactly.
///
/// "It compiles" proves only assignability, and every type is assignable to
/// a supertype. [Exactly] is invariant in its argument, so the bound below
/// holds for one type only (up to the top types, which are subtypes of each
/// other): a wider *and* a narrower static type both fail, with
/// `type_argument_not_matching_bounds` on the type argument. The Dart SDK's
/// own language tests pin static types the same way.
library;

/// A function type that has `T` in both positions, and so is a subtype of
/// `Exactly<S>` only when `T` and `S` are subtypes of each other.
typedef Exactly<T> = T Function(T);

/// See [expectStaticType].
extension StaticType<T> on T {
  /// Compiles only when the static type of the receiver is exactly the `X`
  /// of `R = Exactly<X>`. `T` is taken from the receiver alone — an extension
  /// receiver has no context type — so nothing can widen it.
  ///
  /// ```dart
  /// device.read(client).expectStaticType<Exactly<Device?>>();
  /// ```
  T expectStaticType<R extends Exactly<T>>() => this;
}
