import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/design.dart';
import '../data/platform_store.dart';
import '../domain/platform_models.dart';
import 'platform_ui.dart';

class ComplaintsPage extends StatelessWidget {
  const ComplaintsPage({super.key, required this.store});
  final PlatformStore store;
  @override
  Widget build(BuildContext context) => PlatformScaffold(
    title: 'الشكاوى والدعم',
    account: store,
    child: PlatformCollection(
      store: store,
      path: '/me/complaints',
      header: SanadActionHeader(
        title: const Text(
          'نحن هنا للمساعدة',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        actions: [
          SanadPrimaryButton.icon(
            onPressed: () =>
                platformRoute<void>(context, ComplaintPage(store: store)),
            icon: const AppIcon(CupertinoIcons.plus),
            label: const Text('شكوى جديدة'),
          ),
        ],
      ),
      empty: const EmptyPanel(
        icon: CupertinoIcons.bubble_left_bubble_right,
        title: 'كيف يمكننا مساعدتك؟',
        description:
            'أرسل وصفاً واضحاً للمشكلة وصورة إن توفرت، وتابع رد فريق الدعم هنا.',
      ),
      builder: (context, data) => Glass(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppTag(switch (textOf(data['status'])) {
              'resolved' => 'تم الحل',
              'in_review' => 'قيد المتابعة',
              'closed' => 'مغلقة',
              _ => 'تم الاستلام',
            }),
            const SizedBox(height: 14),
            Text(textOf(data['text']), style: const TextStyle(height: 1.8)),
            if (textOf(data['response']).isNotEmpty) ...[
              const Divider(height: 28),
              const Text(
                'رد فريق الدعم',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(textOf(data['response'])),
            ],
            if (textOf(data['image_url']).isNotEmpty) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  textOf(data['image_url']),
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Text('تعذّر عرض المرفق.'),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class ComplaintPage extends StatefulWidget {
  const ComplaintPage({super.key, required this.store, this.conversationId});
  final PlatformStore store;
  final String? conversationId;
  @override
  State<ComplaintPage> createState() => _ComplaintPageState();
}

class _ComplaintPageState extends State<ComplaintPage> {
  final description = TextEditingController();
  Uint8List? image;
  String? mime, uploaded, error;
  bool busy = false, success = false;
  @override
  void dispose() {
    description.dispose();
    super.dispose();
  }

  Future<void> pick() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
        requestFullMetadata: false,
      );
      if (file == null) return;
      if (await file.length() > 5 * 1024 * 1024) {
        throw const PlatformFailure(
          'الصورة كبيرة. اختر صورة بحجم لا يتجاوز 5 ميغابايت.',
        );
      }
      final bytes = await file.readAsBytes();
      final type = bytes.length > 3 && bytes[0] == 0xff && bytes[1] == 0xd8
          ? 'image/jpeg'
          : bytes.length > 8 &&
                bytes[0] == 0x89 &&
                bytes[1] == 0x50 &&
                bytes[2] == 0x4e &&
                bytes[3] == 0x47
          ? 'image/png'
          : bytes.length > 12 &&
                String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
                String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP'
          ? 'image/webp'
          : null;
      if (type == null) {
        throw const PlatformFailure('اختر صورة JPG أو PNG أو WebP.');
      }
      if (mounted) {
        setState(() {
          image = bytes;
          mime = type;
          uploaded = null;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> send() async {
    if (description.text.trim().length < 10) {
      setState(() => error = 'اكتب وصفاً للمشكلة من 10 محارف على الأقل.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (image != null) {
        uploaded ??= await widget.store.uploadComplaintImage(image!, mime!);
      }
      await widget.store.complaint(
        description.text.trim(),
        uploaded,
        conversationId: widget.conversationId,
      );
      if (mounted) setState(() => success = true);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PlatformScaffold(
    title: 'إرسال شكوى',
    account: widget.store,
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: success
          ? [
              EmptyPanel(
                icon: CupertinoIcons.checkmark_shield,
                title: 'وصلت شكواك',
                description:
                    'سيراجع فريق الدعم التفاصيل. يمكنك متابعة الحالة والرد من قسم الشكاوى.',
                action: SanadPrimaryButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('تم'),
                ),
              ),
            ]
          : [
              const Text(
                'أخبرنا بما حدث',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text(
                'اشرح المشكلة دون إضافة كلمات مرور أو معلومات مالية. الصورة اختيارية وتبقى خاصة بفريق الدعم.',
                style: TextStyle(color: context.sanad.secondary, height: 1.8),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: description,
                minLines: 6,
                maxLines: 12,
                maxLength: 4000,
                decoration: const InputDecoration(labelText: 'تفاصيل الشكوى'),
              ),
              const SizedBox(height: 20),
              if (image != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.memory(image!, height: 220, fit: BoxFit.cover),
                ),
                const SizedBox(height: 12),
              ],
              SanadActions(
                children: [
                  OutlinedButton.icon(
                    onPressed: busy ? null : pick,
                    icon: const AppIcon(CupertinoIcons.photo),
                    label: Text(image == null ? 'إرفاق صورة' : 'تغيير الصورة'),
                  ),
                  if (image != null)
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => setState(() {
                              image = null;
                              uploaded = null;
                            }),
                      child: const Text('إزالة الصورة'),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              if (error != null) ...[
                SignalCard(error!),
                const SizedBox(height: 16),
              ],
              SanadPrimaryButton(
                onPressed: busy ? null : send,
                child: Text(busy ? 'جارٍ الإرسال…' : 'إرسال الشكوى'),
              ),
            ],
    ),
  );
}
