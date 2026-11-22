import 'dart:async';
import 'package:snad/features/jobs/data/jobs_store.dart';

/// Existing tests verify the legacy/device API kept for older releases.
/// platform_* tests explicitly enable the production-default account flow.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  JobsStore.accountFeaturesOverride = false;
  await testMain();
}
