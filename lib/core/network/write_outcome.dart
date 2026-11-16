import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/settings/domain/service_not_configured.dart';

/// Whether a write that failed with [error] may nonetheless have been carried
/// out: the request was sent and nothing readable came back (a timeout after
/// the connection was made, a reply that broke off, a 5xx). A request that
/// certainly never arrived (refused, unresolved, not set up, refused by the
/// key or the address) changed nothing.
///
/// The services take no idempotency key, so before such a write is offered
/// again the app reads what the server holds.
bool writeMayHaveLanded(Object error) {
  if (unwrapFailure(error) is ServiceNotConfigured) return false;
  return switch (classifyConnectionFailure(error)) {
    ServiceFailureReason.timeout ||
    ServiceFailureReason.serverError ||
    ServiceFailureReason.invalidResponse ||
    ServiceFailureReason.unknown => true,
    _ => false,
  };
}
