import 'package:flutter/widgets.dart';
import '../../../core/motion.dart';
import '../data/jobs_store.dart';

class SavedMatchesNotice extends StatelessWidget {
  const SavedMatchesNotice({
    super.key,
    required this.store,
    required this.onView,
  });
  final JobsStore store;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final jobs = store.newMatchAlertJobs;
    if (jobs.isEmpty) return const SizedBox.shrink();
    final message = switch (jobs.length) {
      1 => 'تتوفر فرصة عمل جديدة تطابق إحدى عمليات البحث المحفوظة.',
      2 => 'تتوفر فرصتا عمل جديدتان تطابقان عمليات البحث المحفوظة.',
      <= 10 =>
        'تتوفر ${jobs.length} فرص عمل جديدة تطابق عمليات البحث المحفوظة.',
      _ => 'تتوفر ${jobs.length} فرصة عمل جديدة تطابق عمليات البحث المحفوظة.',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: SignalCard(
        message,
        actionLabel: 'عرض الفرص',
        action: onView,
        onClose: () => store.acknowledgeMatchAlert(jobs.map((job) => job.id)),
      ),
    );
  }
}
