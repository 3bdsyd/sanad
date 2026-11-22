import '../../../core/design.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/app_links.dart';
import '../../jobs/domain/job.dart';
import 'platform_ui.dart';

Future<void> showJobShareMenu(
  BuildContext context,
  Job job,
  Offset position,
) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final local = overlay.globalToLocal(position);
  final result = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
      local.dx,
      local.dy,
      overlay.size.width - local.dx,
      overlay.size.height - local.dy,
    ),
    items: [
      const PopupMenuItem(
        value: 'share',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(CupertinoIcons.share, size: 20),
            SizedBox(width: 12),
            Text('مشاركة الفرصة'),
          ],
        ),
      ),
    ],
  );
  if (result != 'share' || !context.mounted) return;
  if (job.isDemo) {
    await platformRoute<void>(
      context,
      const PlatformScaffold(
        title: 'مشاركة الفرصة',
        child: Padding(
          padding: EdgeInsets.all(24),
          child: SignalCard(
            'هذه فرصة توضيحية، ولا تملك رابطاً عاماً للمشاركة.',
          ),
        ),
      ),
    );
    return;
  }
  final link = AppLinks.jobShareUri(job.id);
  if (link == null) return;
  final box = context.findRenderObject() as RenderBox?;
  try {
    await SharePlus.instance.share(
      ShareParams(
        text: '${job.title}\n${job.company}\n${job.locationLabel}\n$link',
        subject: job.title,
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  } catch (_) {
    if (context.mounted) {
      await platformRoute<void>(
        context,
        const PlatformScaffold(
          title: 'مشاركة الفرصة',
          child: Padding(
            padding: EdgeInsets.all(24),
            child: SignalCard('تعذّر فتح قائمة المشاركة. أعد المحاولة.'),
          ),
        ),
      );
    }
  }
}
