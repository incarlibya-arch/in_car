import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../services/api.dart';
import '../theme.dart';
import 'common.dart';

/// مفتاح عام يخلي الإشعارات تظهر من أي شاشة
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// يسمع للإشعارات الجديدة ويعرضها كشريط أثناء استخدام التطبيق
class InAppNotifier extends StatefulWidget {
  final Widget child;
  const InAppNotifier({super.key, required this.child});
  @override
  State<InAppNotifier> createState() => _InAppNotifierState();
}

class _InAppNotifierState extends State<InAppNotifier> {
  StreamSubscription<List<AppNotification>>? _sub;
  final _seen = <String>{};
  bool _first = true;

  @override
  void initState() {
    super.initState();
    _sub = Api.watchMyNotifications().listen((list) {
      if (_first) {
        _seen.addAll(list.map((n) => n.id));
        _first = false;
        return;
      }
      for (final n in list.reversed) {
        if (_seen.add(n.id) && !n.read) {
          scaffoldMessengerKey.currentState?.showSnackBar(SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
            backgroundColor: n.type == 'sos' ? AppColors.danger : AppColors.ink,
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(n.title, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
              Text(n.body, style: const TextStyle(color: Colors.white)),
            ]),
          ));
        }
      }
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// جرس الإشعارات مع عدد غير المقروءة
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AppNotification>>(
      stream: Api.watchMyNotifications(),
      builder: (context, snap) {
        final unread = (snap.data ?? []).where((n) => !n.read).length;
        return IconButton.filled(
          style: IconButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.ink),
          tooltip: 'الإشعارات',
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())),
          icon: Badge(
            isLabelVisible: unread > 0,
            label: Text('$unread'),
            child: const Icon(Icons.notifications_none),
          ),
        );
      },
    );
  }
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final Stream<List<AppNotification>> _list = Api.watchMyNotifications();

  @override
  void dispose() {
    Api.markNotificationsRead().catchError((_) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإشعارات')),
      body: StreamBuilder<List<AppNotification>>(
        stream: _list,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final list = snap.data!;
          if (list.isEmpty) {
            return const Center(child: Text('ما فيش إشعارات', style: TextStyle(color: AppColors.mute)));
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final n = list[i];
              return ListTile(
                tileColor: n.read ? null : AppColors.accentSoft.withValues(alpha: .4),
                leading: Icon(n.type == 'sos' ? Icons.sos : Icons.notifications_outlined,
                    color: n.type == 'sos' ? AppColors.danger : AppColors.ink),
                title: Text(n.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${n.body}\n${fmtDate(n.createdAt)}'),
                isThreeLine: true,
              );
            },
          );
        },
      ),
    );
  }
}
