import 'package:flutter_sharing_intent/model/sharing_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_sharing_intent/flutter_sharing_intent.dart';
import 'package:flutter_sharing_intent/flutter_sharing_intent_platform_interface.dart';
import 'package:flutter_sharing_intent/flutter_sharing_intent_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterSharingIntentPlatform
    with MockPlatformInterfaceMixin
    implements FlutterSharingIntentPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Future<List<SharedFile>> getInitialSharing() {
    return Future.value([
      SharedFile(value: "Test", type: SharedMediaType.TEXT),
    ]);
  }

  @override
  void reset() {}

  @override
  Stream<List<SharedFile>> getMediaStream() => Stream.value([]);

  @override
  Future<String> getDebugLogs() => Future.value('');

  @override
  Future<void> clearDebugLogs() => Future.value();

  @override
  Future<void> shareDebugLogs() => Future.value();
}

void main() {
  final FlutterSharingIntentPlatform initialPlatform =
      FlutterSharingIntentPlatform.instance;

  test('$MethodChannelFlutterSharingIntent is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFlutterSharingIntent>());
  });

  FlutterSharingIntent flutterSharingIntentPlugin = FlutterSharingIntent();
  MockFlutterSharingIntentPlatform fakePlatform =
      MockFlutterSharingIntentPlatform();
  FlutterSharingIntentPlatform.instance = fakePlatform;

  test('getPlatformVersion', () async {
    expect(await flutterSharingIntentPlugin.getPlatformVersion(), '42');
  });

  test('getInitialSharing', () async {
    var sharingData = await flutterSharingIntentPlugin.getInitialSharing();
    expect(sharingData.first.value, 'Test');
  });
}
