import 'package:flutter/foundation.dart' show kIsWeb;

import 'json_local_db.dart';
import 'local_db.dart';
import 'sqflite_local_db.dart';

/// SQLite where it exists, a preferences-backed document store on web.
///
/// `sqflite` has no web implementation without shipping a WASM build and a
/// service worker, so the web build keeps using preferences. Both satisfy the
/// same [LocalDb] contract, including the outbox, so the offline behaviour and
/// the sync logic are identical either way.
LocalDb createLocalDb() =>
    kIsWeb ? JsonLocalDb(PrefsKeyValueStore()) : SqfliteLocalDb();
