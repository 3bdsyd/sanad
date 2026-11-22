import 'package:flutter/material.dart';
import '../../jobs/data/jobs_store.dart';
import '../../jobs/domain/job.dart';
import '../../jobs/presentation/job_details.dart';
import '../../jobs/presentation/notifications.dart';
import '../domain/platform_models.dart';
import 'applications_page.dart';
import 'auth_page.dart';
import 'chat_page.dart';
import 'complaints_page.dart';
import 'publisher_panel.dart';
import 'platform_ui.dart';

/// Push payloads contain IDs, never private text or trusted authorization.
/// Every private target is fetched under the current account before opening.
Future<void> openNotificationDestination(
  BuildContext context,
  JobsStore store,
  Json payload,
) async {
  try {
    await _openDestination(context, store, payload);
  } catch (e) {
    if (context.mounted) {
      await platformRoute<void>(
        context,
        PlatformScaffold(
          title: 'عرض التحديث',
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SignalCard(
              e is PlatformFailure
                  ? e.message
                  : 'تعذّر فتح التحديث. أعد المحاولة من الإشعارات.',
            ),
          ),
        ),
      );
    }
  }
}

Future<void> _openDestination(
  BuildContext context,
  JobsStore store,
  Json payload,
) async {
  final recipient = textOf(payload['recipient_id']);
  if (store.platform.signedIn &&
      recipient.isNotEmpty &&
      recipient != store.platform.user?.id) {
    throw const PlatformFailure(
      'هذا التحديث يتبع حساباً آخر. يمكنك العودة إلى إشعارات حسابك الحالي.',
    );
  }
  final kind = textOf(payload['destination']);
  if (![
    'job',
    'application',
    'conversation',
    'own_job',
    'complaint',
    'matches',
  ].contains(kind)) {
    return;
  }
  final id = textOf(payload['entity_id']);
  if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(id) && kind != 'matches') {
    return;
  }
  if (kind == 'job') {
    final job = await store.fetchJob(id);
    if (job == null) {
      throw const PlatformFailure(
        'لم تعد هذه الفرصة متاحة. يمكنك العودة إلى قائمة الفرص.',
      );
    }
    if (context.mounted) {
      await platformRoute<void>(context, JobDetails(job: job, store: store));
    }
    return;
  }
  // Old account push payloads must not reopen removed account workflows.
  if (!store.accountsEnabled) return;
  if (!await ensureAccount(context, store.platform) || !context.mounted) return;
  switch (kind) {
    case 'conversation':
      final data = await store.platform.load('/conversations/$id');
      if (context.mounted) {
        await platformRoute<void>(
          context,
          ChatPage(
            store: store.platform,
            conversation: Conversation(object(data['data'])),
          ),
        );
      }
    case 'application':
      final data = await store.platform.load('/applications/$id');
      if (context.mounted) {
        await platformRoute<void>(
          context,
          ApplicationDetailsPage(
            store: store,
            initial: ApplicationRecord(object(data['data'])),
            employer: object(data['data'])['viewer_role'] == 'employer',
          ),
        );
      }
    case 'own_job':
      final data = await store.platform.load('/me/jobs/$id');
      final jobs = objects([data['data']]);
      if (jobs.isNotEmpty && context.mounted) {
        await platformRoute<void>(
          context,
          OwnedJobDetailsPage(store: store, job: Job.fromApi(jobs.first)),
        );
      }
    case 'complaint':
      if (context.mounted) {
        await platformRoute<void>(
          context,
          ComplaintsPage(store: store.platform),
        );
      }
    case 'matches':
      await store.refreshSavedSearchMatches(force: true);
      if (context.mounted) {
        await platformRoute<void>(
          context,
          NotificationsPage(
            store: store,
            initialNewOnly: true,
            onJob: (job) => platformRoute<void>(
              context,
              JobDetails(job: job, store: store),
            ),
          ),
        );
      }
  }
}
