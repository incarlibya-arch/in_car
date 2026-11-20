import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets.dart';

/// محادثة بين الراكب والسواق أثناء الرحلة
class ChatScreen extends StatefulWidget {
  final String rideId;
  final String otherName;
  const ChatScreen({super.key, required this.rideId, required this.otherName});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final Stream<List<ChatMessage>> _messages = Api.watchMessages(widget.rideId);
  final _ctrl = TextEditingController();
  bool _sending = false;

  static const _quick = ['أنا في المكان', 'جاي في الثنية', 'نراجي فيك', 'وينك بالضبط؟'];

  Future<void> _send([String? text]) async {
    final t = (text ?? _ctrl.text).trim();
    if (t.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await Api.sendMessage(widget.rideId, t);
      if (text == null) _ctrl.clear();
    } catch (e) {
      if (mounted) showMsg(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.otherName)),
      body: Column(children: [
        Expanded(
          child: StreamBuilder<List<ChatMessage>>(
            stream: _messages,
            builder: (context, snap) {
              final list = (snap.data ?? []).reversed.toList();
              if (list.isEmpty) {
                return const Center(child: Text('ما فيش رسائل لين توا', style: TextStyle(color: AppColors.mute)));
              }
              return ListView.builder(
                reverse: true,
                padding: const EdgeInsets.all(12),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final m = list[i];
                  final mine = m.senderId == Api.uid;
                  return Align(
                    alignment: mine ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
                    child: Container(
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .75),
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: mine ? AppColors.ink : Colors.white,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(m.body, style: TextStyle(color: mine ? Colors.white : AppColors.ink, fontSize: 15)),
                        Text(
                          '${m.createdAt.hour.toString().padLeft(2, '0')}:${m.createdAt.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(fontSize: 11, color: mine ? const Color(0xFFC9D2E0) : AppColors.mute),
                        ),
                      ]),
                    ),
                  );
                },
              );
            },
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              for (final q in _quick)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ActionChip(label: Text(q), onPressed: () => _send(q)),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 1000,
                  decoration: const InputDecoration(hintText: 'اكتب رسالة', counterText: '', isDense: true),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                tooltip: 'إرسال',
                onPressed: _sending ? null : _send,
                icon: const Icon(Icons.send),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
