/// Shared tolerance for floating-point geometry operations in metres.
///
/// This is deliberately reserved for numerical comparisons. Physical product
/// thresholds (minimum wall length, snapping distances, closure distances,
/// etc.) must remain explicit domain constants.
const double kGeometryEpsilon = 1e-6;
