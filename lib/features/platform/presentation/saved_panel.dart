import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../core/design.dart';
import '../../jobs/data/jobs_store.dart';
import '../../jobs/domain/job.dart';
import '../../jobs/presentation/job_details.dart';
import 'auth_page.dart';
import 'platform_ui.dart';

class SavedPanel extends StatelessWidget {
  const SavedPanel({super.key, required this.store});
  final JobsStore store;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store.platform,
    builder: (context, _) {
      if (!store.platform.signedIn) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
          children: [
            EmptyPanel(
              icon: CupertinoIcons.heart,
              title: 'احتفظ بالفرص التي تهمّك',
              description:
                  'سجّل الدخول لتبقى فرصك المحفوظة مرتبطة بحسابك ومتاحة على أجهزتك.',
              action: SanadPrimaryButton(
                onPressed: () =>
                    ensureAccount(context, store.platform, reason: 'لحفظ فرصك'),
                child: const Text('تسجيل الدخول أو إنشاء حساب'),
              ),
            ),
          ],
        );
      }
      return PlatformCollection(
        store: store.platform,
        path: '/me/favorites',
        header: const Text(
          'الفرص المحفوظة',
          style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
        ),
        empty: const EmptyPanel(
          icon: CupertinoIcons.heart,
          title: 'كل فرصة مهمّة، في مكانها',
          description:
              'اضغط علامة القلب على أي فرصة للعودة إليها لاحقاً. ستظهر فرصك المحفوظة هنا.',
        ),
        builder: (context, data) {
          final job = Job.fromApi(data);
          return Pressable(
            onTap: () => platformRoute<void>(
              context,
              JobDetails(job: job, store: store),
            ),
            child: Glass(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job.title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    job.company,
                    style: TextStyle(color: context.sanad.secondary),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      AppTag(job.locationLabel),
                      AppTag(job.workType),
                      if (!job.isAvailable) const AppTag('غير متاحة حالياً'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    job.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, height: 1.8),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Expanded(child: Text('عرض التفاصيل')),
                      IconButton(
                        tooltip: 'إزالة من المحفوظات',
                        onPressed: () async {
                          try {
                            await store.platform.setFavorite(job.id, false);
                          } catch (e) {
                            if (context.mounted) {
                              await platformRoute<void>(
                                context,
                                PlatformScaffold(
                                  title: 'تعذّر تحديث المحفوظة',
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: SignalCard(e.toString()),
                                  ),
                                ),
                              );
                            }
                          }
                        },
                        icon: const AppIcon(CupertinoIcons.heart_fill),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
