import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Client-generated primary keys.
///
/// IDs are minted on-device so records can be created offline and later synced
/// without a server round trip and without renumbering. v7 is time-ordered,
/// which keeps SQLite b-tree inserts (and any index on `id`) sequential.
String newId() => _uuid.v7();

/// Deterministic id derived from a namespace and a natural key. Used where the
/// same logical row must converge across devices — e.g. one mood entry per day.
String stableId(String namespace, String naturalKey) =>
    _uuid.v5(Namespace.url.value, '$namespace:$naturalKey');
