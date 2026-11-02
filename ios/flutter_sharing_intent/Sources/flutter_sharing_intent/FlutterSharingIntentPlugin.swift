import Flutter

// Entry point named in pubspec.yaml (pluginClass). Swift-only so the plugin
// builds as a single Swift Package Manager target as well as a CocoaPod.
@objc(FlutterSharingIntentPlugin)
public class FlutterSharingIntentPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        SwiftFlutterSharingIntentPlugin.register(with: registrar)
    }
}
