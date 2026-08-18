import 'dart:async';

import 'package:flutter_sharing_intent/model/sharing_file.dart';

import 'flutter_sharing_intent_platform_interface.dart';

class FlutterSharingIntent {
  static FlutterSharingIntent instance = FlutterSharingIntent._();
  factory FlutterSharingIntent() => instance;
  Stream<List<SharedFile>>? _streamMedia;

  FlutterSharingIntent._();

  Future<String?> getPlatformVersion() {
    return FlutterSharingIntentPlatform.instance.getPlatformVersion();
  }

  /// Returns a [Future], which completes to one of the following:
  /// NOTE. The returned media on iOS (iOS ONLY) is already copied to a temp folder.
  /// So, you need to delete the file after you finish using it
  Future<List<SharedFile>> getInitialSharing() {
    return FlutterSharingIntentPlatform.instance.getInitialSharing();
  }

  /// Call this method if you already consumed the callback
  /// and don't want the same callback again
  void reset() {
    return FlutterSharingIntentPlatform.instance.reset();
  }

  /// Sets up a broadcast stream for receiving incoming media share change events.
  ///
  /// Returns a broadcast [Stream] which emits events to listeners as follows:
  /// Errors occurring during stream activation or deactivation are reported
  /// through the `FlutterError` facility. Stream activation happens only when
  /// stream listener count changes from 0 to 1. Stream deactivation happens
  /// only when stream listener count changes from 1 to 0.
  ///
  /// If the app was started by a link intent or user activity, the stream
  /// will also emit that initial value to the first listener (in addition to
  /// `getInitialSharing`), so it is safe to rely on either API.
  Stream<List<SharedFile>> getMediaStream() {
    _streamMedia ??= FlutterSharingIntentPlatform.instance.getMediaStream();
    return _streamMedia!;
  }

  /// Returns the accumulated native-side debug log (attachment processing,
  /// App Group read/write, and app-launch hand-off events) as plain text.
  /// Useful for diagnosing sharing issues without an attached debugger.
  Future<String> getDebugLogs() {
    return FlutterSharingIntentPlatform.instance.getDebugLogs();
  }

  /// Clears the accumulated native-side debug log.
  Future<void> clearDebugLogs() {
    return FlutterSharingIntentPlatform.instance.clearDebugLogs();
  }

  /// Opens the native share sheet with the current debug log so it can be
  /// sent to a developer for troubleshooting.
  Future<void> shareDebugLogs() {
    return FlutterSharingIntentPlatform.instance.shareDebugLogs();
  }
}
