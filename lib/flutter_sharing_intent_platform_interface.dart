import 'dart:async';

import 'package:flutter_sharing_intent/model/sharing_file.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_sharing_intent_method_channel.dart';

abstract class FlutterSharingIntentPlatform extends PlatformInterface {
  /// Constructs a FlutterSharingIntentPlatform.
  FlutterSharingIntentPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterSharingIntentPlatform _instance =
      MethodChannelFlutterSharingIntent();

  /// The default instance of [FlutterSharingIntentPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterSharingIntent].
  static FlutterSharingIntentPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterSharingIntentPlatform] when
  /// they register themselves.
  static set instance(FlutterSharingIntentPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<List<SharedFile>> getInitialSharing() async {
    throw UnimplementedError('getInitialSharing() has not been implemented.');
  }

  void reset() async {
    throw UnimplementedError('reset() has not been implemented.');
  }

  Stream<List<SharedFile>> getMediaStream() {
    throw UnimplementedError('getMediaStream() has not been implemented.');
  }

  Future<String> getDebugLogs() async {
    throw UnimplementedError('getDebugLogs() has not been implemented.');
  }

  Future<void> clearDebugLogs() async {
    throw UnimplementedError('clearDebugLogs() has not been implemented.');
  }

  Future<void> shareDebugLogs() async {
    throw UnimplementedError('shareDebugLogs() has not been implemented.');
  }
}
