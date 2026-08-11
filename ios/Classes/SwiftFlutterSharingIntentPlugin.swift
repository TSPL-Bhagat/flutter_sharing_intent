import Flutter
import Photos
import UIKit

public class SwiftFlutterSharingIntentPlugin: NSObject, FlutterStreamHandler, FlutterPlugin, FlutterSceneLifeCycleDelegate {
    static let kMessagesChannel = "\(kAppChannel)/messages"
    static let kEventsChannelMedia = "\(kAppChannel)/events-sharing";
    
    private var initialSharing: [SharingFile]? = nil
    private var latestSharing: [SharingFile]? = nil
    
    
    private var eventSinkMedia: FlutterEventSink? = nil;
    // Singleton is required for calling functions directly from AppDelegate
    // - it is required if the developer is using also another library, which requires to call "application(_:open:options:)"
    // -> see Example app
    public static let instance = SwiftFlutterSharingIntentPlugin()

    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: kAppChannel,binaryMessenger:registrar.messenger())

        registrar.addMethodCallDelegate(instance, channel: channel)

        let chargingChannelMedia = FlutterEventChannel(name: kEventsChannelMedia, binaryMessenger: registrar.messenger())
        chargingChannelMedia.setStreamHandler(instance)


        registrar.addApplicationDelegate(instance)
        // addSceneDelegate is part of FlutterPluginRegistrar (requires Flutter >=3.3.0 with UIScene support on iOS 13+)
        registrar.addSceneDelegate(instance)
        // registrar.addMethodCallDelegate(instance, channel: channel)
    }

    //  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    //    result("iOS " + UIDevice.current.systemVersion)
    //  }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        
        switch call.method {
        case "getInitialSharing":
            result(toJson(data: self.initialSharing));
            /// Clear cache data to send only once
            self.initialSharing = nil
            self.latestSharing = nil

        case "reset":
            self.initialSharing = nil
            self.latestSharing = nil
            result(nil);
            
        case "getPlatformVersion" :
            result("iOS " + UIDevice.current.systemVersion);
        default:
            result(FlutterMethodNotImplemented);
        }
    }
    
    // By Adding bundle id to prefix, we will ensure that the correct app will be openned
    public func hasSameSchemePrefix(url: URL?) -> Bool {
        if let url = url, let appDomain = Bundle.main.bundleIdentifier {
            return url.absoluteString.hasPrefix("\(kSchemePrefix)-\(appDomain)")
        }
        return false
    }
    
    // This is the function called on app startup with a shared link if the app had been closed already.
    // It is called as the launch process is finishing and the app is almost ready to run.
    // If the URL includes the module's ShareMedia prefix, then we process the URL and return true if we know how to handle that kind of URL or false if the app is not able to.
    // If the URL does not include the module's prefix, we must return true since while our module cannot handle the link, other modules might be and returning false can prevent
    // them from getting the chance to.
    // Reference: https://developer.apple.com/documentation/uikit/uiapplicationdelegate/1622921-application
    public func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [AnyHashable : Any] = [:]) -> Bool {
        if let url = launchOptions[UIApplication.LaunchOptionsKey.url] as? URL {
            if (hasSameSchemePrefix(url: url)) {
                return handleUrl(url: url, setInitialData: true)
            }
            return true
        } else if let activityDictionary = launchOptions[UIApplication.LaunchOptionsKey.userActivityDictionary] as? [AnyHashable: Any] {
            // Handle multiple URLs shared in
            for key in activityDictionary.keys {
                if let userActivity = activityDictionary[key] as? NSUserActivity {
                    if let url = userActivity.webpageURL {
                        if (hasSameSchemePrefix(url: url)) {
                            return handleUrl(url: url, setInitialData: true)
                        }
                        return true
                    }
                }
            }
        }
        return true
    }
    
    // This is the function called on resuming the app from a shared link.
    // It handles requests to open a resource by a specified URL. Returning true means that it was handled successfully, false means the attempt to open the resource failed.
    // If the URL includes the module's ShareMedia prefix, then we process the URL and return true if we know how to handle that kind of URL or false if we are not able to.
    // If the URL does not include the module's prefix, then we return false to indicate our module's attempt to open the resource failed and others should be allowed to.
    // Reference: https://developer.apple.com/documentation/uikit/uiapplicationdelegate/1623112-application
    public func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        if (hasSameSchemePrefix(url: url)) {
            return handleUrl(url: url, setInitialData: false)
        }
        return false
    }
    
    // This function is called by other modules like Firebase DeepLinks.
    // It tells the delegate that data for continuing an activity is available. Returning true means that our module handled the activity and that others do not have to. Returning false tells
    // iOS that our app did not handle the activity.
    // If the URL includes the module's ShareMedia prefix, then we process the URL and return true if we know how to handle that kind of URL or false if we are not able to.
    // If the URL does not include the module's prefix, then we must return false to indicate that this module did not handle the prefix and that other modules should try to.
    // Reference: https://developer.apple.com/documentation/uikit/uiapplicationdelegate/1623072-application
    public func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([Any]) -> Void) -> Bool {
        if let url = userActivity.webpageURL {
            if (hasSameSchemePrefix(url: url)) {
                return handleUrl(url: url, setInitialData: true)
            }
        }
        return false
    }

    // MARK: - UIScene lifecycle
    // Mirrors the AppDelegate hooks above for hosts that have migrated to
    // UISceneDelegate. See https://docs.flutter.dev/to/uiscene-migration

    // FlutterSceneLifeCycleDelegate methods must return Bool to signal that the
    // URL/activity has been handled, otherwise FlutterSceneDelegate will forward
    // it to the engine's deep-link channel.

    // connectionOptions is nullable per FlutterSceneLifeCycleDelegate protocol (another plugin
    // may have already consumed it, in which case it arrives as nil).
    public func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions?) -> Bool {
        guard let connectionOptions = connectionOptions else { return false }
        if let urlContext = connectionOptions.urlContexts.first {
            let url = urlContext.url
            if hasSameSchemePrefix(url: url) {
                return handleUrl(url: url, setInitialData: true)
            }
            return true
        }
        for userActivity in connectionOptions.userActivities {
            if let url = userActivity.webpageURL {
                if hasSameSchemePrefix(url: url) {
                    return handleUrl(url: url, setInitialData: true)
                }
                return true
            }
        }
        return true
    }

    public func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
        for urlContext in URLContexts {
            if hasSameSchemePrefix(url: urlContext.url) {
                return handleUrl(url: urlContext.url, setInitialData: false)
            }
        }
        return false
    }

    public func scene(_ scene: UIScene, continue userActivity: NSUserActivity) -> Bool {
        if let url = userActivity.webpageURL, hasSameSchemePrefix(url: url) {
            return handleUrl(url: url, setInitialData: true)
        }
        return false
    }

    private func handleUrl(url: URL?, setInitialData: Bool) -> Bool {
           let appGroupId = Bundle.main.object(forInfoDictionaryKey: kAppGroupIdKey) as? String
           let defaultGroupId = "group.\(Bundle.main.bundleIdentifier!)"
           let userDefaults = UserDefaults(suiteName: appGroupId ?? defaultGroupId)
           
           let message = userDefaults?.string(forKey: kUserDefaultsMessageKey)
           if let json = userDefaults?.object(forKey: kUserDefaultsKey) as? Data {
               let sharedArray = decode(data: json)
               let sharedMediaFiles: [SharingFile] = sharedArray.compactMap {
                   guard let value = $0.type == .text || $0.type == .url ? $0.value
                           : getAbsolutePath(for: $0.value) else {
                       return nil
                   }
                   
                   return SharingFile(
                    value: value,
                       mimeType: $0.mimeType,
                       thumbnail: getAbsolutePath(for: $0.thumbnail),
                       duration: $0.duration,
                       type: $0.type,
                       message: message
                   )
               }
               latestSharing = sharedMediaFiles
               if(setInitialData) {
                   initialSharing = latestSharing
               }
               eventSinkMedia?(toJson(data: latestSharing))
           }
           return true
       }
    
//    private func handleUrl(url: URL?, setInitialData: Bool) -> Bool {
//        if let url = url {
//            let appGroupId = (Bundle.main.object(forInfoDictionaryKey: kAppGroupIdKey) as? String) ?? "group.\(Bundle.main.bundleIdentifier!)"
//            let userDefaults = UserDefaults(suiteName: appGroupId)
//            let message = userDefaults?.string(forKey: kUserDefaultsMessageKey)
//            if let json = userDefaults?.object(forKey: kUserDefaultsKey) as? Data {
//                print("SwiftFlutterSharingIntentPlugin : [handleUrl] \(json)")
//            }
//            if url.fragment == "media" {
//                if let key = url.host?.components(separatedBy: "=").last,
//                   let json = userDefaults?.object(forKey: key) as? Data {
//                    let sharedArray = decode(data: json)
//                    
//                    let sharedMediaFiles: [SharingFile] = sharedArray.compactMap {
//                        guard let value = getAbsolutePath(for: $0.value) else {
//                            return nil
//                        }
//                        if ($0.type == .video && $0.thumbnail != nil) {
//                            let thumbnail = getAbsolutePath(for: $0.thumbnail!)
//                            return SharingFile.init(value: value, thumbnail: thumbnail, duration: $0.duration, type: $0.type)
//                        } else if ($0.type == .video && $0.thumbnail == nil) {
//                            return SharingFile.init(value: value, thumbnail: nil, duration: $0.duration, type: $0.type)
//                        }
//                        
//                        return SharingFile.init(value: value, thumbnail: nil, duration: $0.duration, type: $0.type)
//                    }
//                    latestSharing = sharedMediaFiles
//                    if(setInitialData) {
//                        initialSharing = latestSharing
//                    }
//                    eventSinkMedia?(toJson(data: latestSharing))
//                }
//            } else if url.fragment == "file" {
//                if let key = url.host?.components(separatedBy: "=").last,
//                   let json = userDefaults?.object(forKey: key) as? Data {
//                    let sharedArray = decode(data: json)
//                    let sharedMediaFiles: [SharingFile] = sharedArray.compactMap{
//                        guard getAbsolutePath(for: $0.value) != nil else {
//                            return nil
//                        }
//                        return SharingFile.init(value: $0.value,
//                                                thumbnail: nil, duration: nil,
//                                                type: $0.type)
//                    }
//                    latestSharing = sharedMediaFiles
//                    if(setInitialData) {
//                        initialSharing = latestSharing
//                    }
//                    eventSinkMedia?(toJson(data: latestSharing))
//                }
//            } else if url.fragment == "url" {
//                if let key = url.host?.components(separatedBy: "=").last,
//                   let sharedArray = userDefaults?.object(forKey: key) as? [String] {
//                    latestSharing = [SharingFile.init(value:  sharedArray.joined(separator: ","), thumbnail: nil, duration: nil, type:  SharingFileType.url)]
//                    if(setInitialData) {
//                        initialSharing = latestSharing
//                    }
//                    eventSinkMedia?(toJson(data: latestSharing))
//                }
//            } else if url.fragment == "text" {
//                if let key = url.host?.components(separatedBy: "=").last,
//                   let sharedArray = userDefaults?.object(forKey: key) as? [String] {
//                    latestSharing = [SharingFile.init(value:  sharedArray.joined(separator: ","), thumbnail: nil, duration: nil, type: SharingFileType.text)]
//                    if(setInitialData) {
//                        initialSharing = latestSharing
//                    }
//                    eventSinkMedia?(toJson(data: latestSharing))
//                }
//            } else {
//                latestSharing = [SharingFile.init(value: url.absoluteString, thumbnail: nil, duration: nil, type: SharingFileType.text)]
//
//                if(setInitialData) {
//                    initialSharing = latestSharing
//                }
//                eventSinkMedia?(latestSharing)
//            }
//            return true
//        }
//        latestSharing = nil
//        return false
//    }
    
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        guard let argument = arguments as? String else {
            return FlutterError.init(code: "INVALID_ARGUMENT", message: "Invalid argument passed", details: nil);
        }
        if (argument == "sharing" || argument == "text") {
            eventSinkMedia = events;
            if let latestSharing = latestSharing {
                eventSinkMedia?(toJson(data: latestSharing))
            }
        } else {
            return FlutterError.init(code: "NO_SUCH_ARGUMENT", message: "No such argument\(String(describing: arguments))", details: nil);
        }
        return nil;
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        if (arguments as! String? == "sharing" || arguments as! String? == "text" ) {
            eventSinkMedia = nil;
        }  else {
            return FlutterError.init(code: "NO_SUCH_ARGUMENT", message: "No such argument as \(String(describing: arguments))", details: nil);
        }
        return nil;
    }
    
    private func getAbsolutePath(for identifier: String?) -> String? {
        guard let identifier else {
                  return nil
              }
        
        // A file URL — only produced by older extension builds, which reported
        // `absoluteString`. Go through URL so percent-escapes (umlauts, "#",
        // spaces) are decoded back into a usable filesystem path.
        if identifier.starts(with: "file://") {
            return URL(string: identifier)?.path
                ?? identifier.replacingOccurrences(of: "file://", with: "")
        }
        // Already an absolute filesystem path. Covers the device container
        // (/private/var/mobile/...) and the simulator's CoreSimulator path,
        // which no fixed prefix can match. Photos local identifiers are UUID
        // based and never start with "/".
        if identifier.starts(with: "/") {
            return identifier
        }
        guard let phAsset = PHAsset.fetchAssets(
                 withLocalIdentifiers: [identifier],
                 options: .none).firstObject else {
                 return nil
             }
        
        let (url, _) = getFullSizeImageURLAndOrientation(for: phAsset)
        return url
    }
    
    private func getFullSizeImageURLAndOrientation(for asset: PHAsset)-> (String?, Int) {
        var url: String? = nil
        var orientation: Int = 0
        let semaphore = DispatchSemaphore(value: 0)
        let options2 = PHContentEditingInputRequestOptions()
        options2.isNetworkAccessAllowed = true
        asset.requestContentEditingInput(with: options2){(input, info) in
            orientation = Int(input?.fullSizeImageOrientation ?? 0)
            url = input?.fullSizeImageURL?.path
            semaphore.signal()
        }
        semaphore.wait()
        return (url, orientation)
    }
    
    private func decode(data: Data) -> [SharingFile] {
        do {
            let encodedData = try JSONDecoder().decode([SharingFile].self, from: data)
            return encodedData
        } catch {
            return []
        }
    }
    
    private func toJson(data: [SharingFile]?) -> String? {
        if data == nil {
            return nil
        }
        do {
            let encodedData = try JSONEncoder().encode(data)
            let json = String(data: encodedData, encoding: .utf8)!
            return json
        } catch {
            fatalError(error.localizedDescription)
        }
    }
}


