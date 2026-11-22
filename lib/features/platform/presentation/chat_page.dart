import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/app_links.dart';
import '../../../core/design.dart';
import '../../../core/motion.dart';
import '../data/platform_store.dart';
import '../domain/platform_models.dart';
import 'complaints_page.dart';
import 'platform_ui.dart';

class ConversationsPage extends StatelessWidget {
  const ConversationsPage({super.key, required this.store});
  final PlatformStore store;
  @override
  Widget build(BuildContext context) => PlatformScaffold(
    title: 'الرسائل',
    account: store,
    child: PlatformCollection(
      store: store,
      path: '/conversations',
      header: const Text(
        'محادثات مهنية، في مكان واحد',
        style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
      ),
      empty: const EmptyPanel(
        icon: CupertinoIcons.chat_bubble_2,
        title: 'لا توجد محادثات بعد',
        description:
            'عندما يبدأ صاحب الفرصة محادثة بشأن طلبك، ستجدها هنا. يمكن للمعلنين مراسلة المتقدمين من صفحة الفرصة.',
      ),
      builder: (context, row) {
        final conversation = Conversation(row);
        return Pressable(
          onTap: () => platformRoute<void>(
            context,
            ChatPage(store: store, conversation: conversation),
          ),
          child: Glass(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Avatar(conversation.peer.name),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        conversation.peer.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        conversation.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.sanad.primary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        conversation.preview.isEmpty
                            ? 'ابدأ المحادثة'
                            : conversation.preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.sanad.secondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                if (conversation.unread > 0)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 8),
                    child: AppTag('${conversation.unread}'),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.store, required this.conversation});
  final PlatformStore store;
  final Conversation conversation;
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  final composer = TextEditingController();
  final scroll = ScrollController();
  Timer? timer;
  String? error;
  bool fetching = false,
      older = false,
      options = false,
      sending = false,
      foreground = true,
      atLatest = true;
  bool blocked = false;
  String? lastRead;
  int failures = 0;
  PlatformStore get store => widget.store;
  String get path => '/conversations/${widget.conversation.id}/messages';
  bool get canSend =>
      !blocked &&
      (object(store.snapshot(path)['meta'])['can_send'] as bool? ??
          widget.conversation.canSend);
  @override
  void initState() {
    super.initState();
    blocked = widget.conversation.blocked;
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    store.activeConversation = widget.conversation.id;
    scroll.addListener(onScroll);
    unawaited(refresh());
  }

  void schedule() {
    timer?.cancel();
    if (!foreground || !mounted) return;
    timer = Timer(Duration(seconds: failures > 0 ? 30 : 8), () {
      if (ModalRoute.isCurrentOf(context) ?? true) {
        unawaited(refresh());
      } else {
        schedule();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    timer?.cancel();
    if (foreground) {
      store.activeConversation = widget.conversation.id;
      unawaited(refresh());
    } else if (store.activeConversation == widget.conversation.id) {
      store.activeConversation = null;
    }
  }

  void onScroll() {
    if (!scroll.hasClients) return;
    final value = scroll.offset < 100;
    if (value != atLatest && mounted) setState(() => atLatest = value);
    if (value) unawaited(read());
    if (scroll.position.pixels >= scroll.position.maxScrollExtent - 120) {
      unawaited(loadOlder());
    }
  }

  Future<void> read() async {
    if (!mounted ||
        !foreground ||
        !(ModalRoute.isCurrentOf(context) ?? true) ||
        !atLatest) {
      return;
    }
    final messages = store
        .messages(widget.conversation.id)
        .where((m) => m.id.isNotEmpty && m.senderId != store.user?.id)
        .toList();
    if (messages.isEmpty || lastRead == messages.last.id) return;
    final id = messages.last.id;
    try {
      await store.markRead(widget.conversation.id, id);
      if (mounted) lastRead = id;
    } catch (_) {
      /* Keep unread until a server acknowledgement. */
    }
  }

  Future<void> refresh() async {
    if (fetching || !store.signedIn || !foreground) return;
    fetching = true;
    try {
      await store.load(path);
      failures = 0;
      if (mounted) setState(() => error = null);
      await read();
    } catch (e) {
      failures++;
      if (mounted) setState(() => error = e.toString());
    } finally {
      fetching = false;
      if (mounted) {
        setState(() {});
        schedule();
      }
    }
  }

  Future<void> loadOlder() async {
    if (older || object(store.snapshot(path)['meta'])['next_cursor'] == null) {
      return;
    }
    older = true;
    try {
      await store.loadMore(path);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      older = false;
    }
  }

  Future<void> send() async {
    if (sending || composer.text.trim().isEmpty || !canSend) return;
    final value = composer.text.trim();
    composer.clear();
    setState(() {
      sending = true;
      error = null;
    });
    try {
      await store.sendMessage(widget.conversation.id, value);
    } catch (e) {
      if (mounted) {
        setState(
          () => error =
              '$e الرسالة محفوظة بحالة «تعذّر الإرسال»؛ اضغط عليها لإعادة المحاولة.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => sending = false);
        if (scroll.hasClients) {
          scroll.animateTo(
            0,
            duration: motionDuration(context, 220),
            curve: Curves.easeOutCubic,
          );
        }
      }
    }
  }

  Future<void> toggleBlock() async {
    try {
      await store.block(widget.conversation.peer.id, !blocked);
      if (mounted) {
        setState(() {
          blocked = !blocked;
          options = false;
        });
      }
      await refresh();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (store.activeConversation == widget.conversation.id) {
      store.activeConversation = null;
    }
    composer.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PlatformScaffold(
    title: widget.conversation.peer.name,
    account: store,
    actions: [
      IconButton(
        tooltip: 'خيارات المحادثة',
        onPressed: () => setState(() => options = !options),
        icon: const AppIcon(CupertinoIcons.ellipsis),
      ),
      const SizedBox(width: 8),
    ],
    child: Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          color: context.sanad.tint,
          child: Row(
            children: [
              AppIcon(
                CupertinoIcons.briefcase,
                color: context.sanad.primary,
                size: 19,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.conversation.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              if (widget.conversation.jobId.isNotEmpty)
                TextButton(
                  onPressed: () {
                    final uri = AppLinks.jobShareUri(widget.conversation.jobId);
                    if (uri != null) {
                      launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                  child: const Text('الفرصة'),
                ),
            ],
          ),
        ),
        if (options)
          Padding(
            padding: const EdgeInsets.all(12),
            child: SanadActions(
              children: [
                OutlinedButton.icon(
                  onPressed: toggleBlock,
                  icon: const AppIcon(CupertinoIcons.hand_raised),
                  label: Text(blocked ? 'إلغاء الحظر' : 'حظر المستخدم'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    store.activeConversation = null;
                    await platformRoute<void>(
                      context,
                      ComplaintPage(
                        store: store,
                        conversationId: widget.conversation.id,
                      ),
                    );
                    if (mounted && foreground) {
                      store.activeConversation = widget.conversation.id;
                    }
                  },
                  icon: const AppIcon(CupertinoIcons.flag),
                  label: const Text('الإبلاغ عن المحادثة'),
                ),
              ],
            ),
          ),
        if (store.demo)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'محادثة توضيحية — لا تصل الرسائل إلى شخص حقيقي.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: SignalCard(error!, action: refresh, actionLabel: 'تحديث'),
          ),
        Expanded(
          child: ListenableBuilder(
            listenable: store,
            builder: (context, _) {
              final rows = store.messages(widget.conversation.id)
                ..sort((a, b) => a.sentAt.compareTo(b.sentAt));
              if (rows.isEmpty) {
                return Center(
                  child: fetching
                      ? const SanadLoader(size: 40)
                      : const Padding(
                          padding: EdgeInsets.all(24),
                          child: EmptyPanel(
                            icon: CupertinoIcons.chat_bubble_2,
                            title: 'بداية تواصل مهني',
                            description:
                                'عرّف بنفسك وناقش تفاصيل الفرصة. تجنّب مشاركة معلوماتك المالية أو المستندات الحساسة.',
                          ),
                        ),
                );
              }
              final reversed = rows.reversed.toList();
              return Stack(
                children: [
                  ListView.builder(
                    controller: scroll,
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    itemCount: reversed.length,
                    itemBuilder: (context, index) {
                      final message = reversed[index],
                          own = message.senderId == store.user?.id;
                      final bubbleInk = own
                          ? Theme.of(context).colorScheme.onPrimary
                          : context.sanad.ink;
                      final date = message.sentAt.split('T').first;
                      final showDate =
                          index == reversed.length - 1 ||
                          reversed[index + 1].sentAt.split('T').first != date;
                      return Column(
                        children: [
                          if (showDate)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                date,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: context.sanad.secondary,
                                ),
                              ),
                            ),
                          Align(
                            alignment: own
                                ? AlignmentDirectional.centerEnd
                                : AlignmentDirectional.centerStart,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.sizeOf(
                                      context,
                                    ).width.clamp(0, 760) *
                                    .78,
                              ),
                              child: GestureDetector(
                                onTap: message.failed
                                    ? () async {
                                        try {
                                          await store.retryMessage(
                                            message.clientId,
                                          );
                                        } catch (e) {
                                          if (mounted) {
                                            setState(
                                              () => error = e.toString(),
                                            );
                                          }
                                        }
                                      }
                                    : null,
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.fromLTRB(
                                    14,
                                    12,
                                    14,
                                    8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: own
                                        ? context.sanad.primary
                                        : context.sanad.surface,
                                    borderRadius: BorderRadius.circular(20),
                                    border: own
                                        ? null
                                        : Border.all(
                                            color: context.sanad.border,
                                          ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      SelectableText(
                                        message.text,
                                        textDirection: textDirectionFor(
                                          message.text,
                                        ),
                                        style: TextStyle(
                                          color: bubbleInk,
                                          height: 1.65,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Wrap(
                                        spacing: 6,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          Text(
                                            _time(message.sentAt),
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: own
                                                  ? bubbleInk.withValues(
                                                      alpha: .75,
                                                    )
                                                  : context.sanad.secondary,
                                            ),
                                          ),
                                          if (own) ...[
                                            AppIcon(
                                              message.failed
                                                  ? CupertinoIcons
                                                        .exclamationmark_circle
                                                  : message.pending
                                                  ? CupertinoIcons.clock
                                                  : message.state == 'read'
                                                  ? CupertinoIcons
                                                        .checkmark_seal_fill
                                                  : CupertinoIcons.check_mark,
                                              size: 12,
                                              color: bubbleInk.withValues(
                                                alpha: .75,
                                              ),
                                            ),
                                            if (message.failed)
                                              Text(
                                                'تعذّر الإرسال · إعادة المحاولة',
                                                style: TextStyle(
                                                  color: bubbleInk,
                                                  fontSize: 10,
                                                ),
                                              ),
                                            if (message.failed)
                                              TextButton(
                                                onPressed: () =>
                                                    store.discardMessage(
                                                      message.clientId,
                                                    ),
                                                style: TextButton.styleFrom(
                                                  foregroundColor: bubbleInk,
                                                ),
                                                child: const Text('إزالة'),
                                              ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  if (!atLatest)
                    PositionedDirectional(
                      bottom: 12,
                      end: 12,
                      child: FloatingActionButton.small(
                        heroTag: 'chat-latest',
                        tooltip: 'أحدث الرسائل',
                        onPressed: () => scroll.animateTo(
                          0,
                          duration: motionDuration(context, 240),
                          curve: Curves.easeOutCubic,
                        ),
                        child: const AppIcon(CupertinoIcons.arrow_down),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        if (!canSend)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              blocked
                  ? 'المستخدم محظور. ألغِ الحظر لاستئناف التواصل.'
                  : 'هذه المحادثة للقراءة فقط.',
            ),
          ),
        if (canSend)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: composer,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 4000,
                      textDirection: textDirectionFor(composer.text),
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        hintText: 'اكتب رسالتك…',
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton.filled(
                    tooltip: 'إرسال الرسالة',
                    onPressed: sending || composer.text.trim().isEmpty
                        ? null
                        : send,
                    icon: sending
                        ? const SanadLoader(size: 22)
                        : const AppIcon(CupertinoIcons.paperplane_fill),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
  String _time(String raw) {
    final d = DateTime.tryParse(raw)?.toLocal();
    return d == null
        ? ''
        : '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.name);
  final String name;
  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: 24,
    backgroundColor: context.sanad.tint,
    child: Text(
      name.isEmpty ? 'س' : name.characters.first,
      style: TextStyle(
        color: context.sanad.primary,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
