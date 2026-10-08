import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Fires (with the server's message) when an authenticated request is
/// rejected because this device is no longer allowed on the account — the
/// server answers 401/403 with a `device_*` `code` (e.g. the center admin
/// reset the student's devices). [App] listens via [deviceLockStreamProvider],
/// logs out cleanly and explains why, since this core network layer can't
/// depend on the auth feature directly.
class DeviceLockEvents {
  final _controller = StreamController<String>.broadcast();

  Stream<String> get stream => _controller.stream;

  void notify(String message) => _controller.add(message);

  void dispose() => _controller.close();
}

final deviceLockEventsProvider = Provider<DeviceLockEvents>((ref) {
  final events = DeviceLockEvents();
  ref.onDispose(events.dispose);
  return events;
});

final deviceLockStreamProvider = StreamProvider<String>((ref) {
  return ref.watch(deviceLockEventsProvider).stream;
});
