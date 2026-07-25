import '../../domain/entities/notification_entity.dart';
import '../../domain/repositories/notification_repository.dart';
import '../datasources/notification_mock_datasource.dart';

/// Mock-backed implementation — what `notificationRepositoryProvider`
/// actually wires up today, since the backend's `notifications` module is
/// scaffolded but not wired into `app.module.ts` yet (no working
/// `GET /notifications` exists). Holds the seeded list in memory as the
/// single source of truth so `markRead`/`markAllRead` are immediately
/// reflected the next time [getNotifications]/[getUnreadCount] is called,
/// the same way a real backend would be — the notifier never needs its own
/// parallel copy of this state (see
/// `features/inbox/data/repositories/conversation_repository_impl.dart`,
/// the precedent this mirrors).
class NotificationRepositoryImpl implements NotificationRepository {
  NotificationRepositoryImpl(this._dataSource);

  final NotificationMockDataSource _dataSource;

  List<NotificationEntity>? _cache;

  Future<List<NotificationEntity>> _load() async {
    return _cache ??= await _dataSource.fetchNotifications();
  }

  @override
  Future<NotificationResultPage> getNotifications({int page = 1, int limit = 20}) async {
    final all = await _load();
    final sorted = [...all]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final start = (page - 1) * limit;
    final end = (start + limit).clamp(0, sorted.length);
    final items = start >= sorted.length
        ? const <NotificationEntity>[]
        : sorted.sublist(start, end);
    return NotificationResultPage(
      items: items,
      page: page,
      limit: limit,
      total: sorted.length,
      hasMore: end < sorted.length,
    );
  }

  @override
  Future<int> getUnreadCount() async {
    final all = await _load();
    return all.where((n) => !n.isRead).length;
  }

  @override
  Future<void> markRead(String id) async {
    final all = await _load();
    _cache = [
      for (final n in all)
        if (n.id == id) n.copyWith(isRead: true) else n,
    ];
  }

  @override
  Future<void> markAllRead() async {
    final all = await _load();
    _cache = [for (final n in all) n.copyWith(isRead: true)];
  }
}
