// FSIShareViewController.swift
// Merged, optimized controller: uses RSI architecture with all FSI features preserved
// Uses model name `SharingFile` (same fields as SharedMediaFile) where `value` = path

import AVFoundation
import MobileCoreServices
import Social
import UIKit
import UniformTypeIdentifiers

public let kSchemePrefix = "SharingMedia"
public let kUserDefaultsKey = "SharingKey"
public let kUserDefaultsMessageKey = "SharingMessageKey"
public let kAppGroupIdKey = "AppGroupId"
public let kAppChannel = "flutter_sharing_intent"

// extension UIViewController {
//     func showToast(_ message: String, duration: Double = 2.0) {
//         let toastLabel = UILabel()
//         toastLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
//         toastLabel.textColor = UIColor.white
//         toastLabel.textAlignment = .center
//         toastLabel.font = UIFont.systemFont(ofSize: 14)
//         toastLabel.text = message
//         toastLabel.alpha = 0.0
//         toastLabel.numberOfLines = 0
//         toastLabel.layer.cornerRadius = 10
//         toastLabel.clipsToBounds = true
//
//         let maxWidthPercentage: CGFloat = 0.8
//         let maxMessageSize = CGSize(
//             width: self.view.bounds.size.width * maxWidthPercentage,
//             height: self.view.bounds.size.height * maxWidthPercentage
//         )
//
//         var expectedSize = toastLabel.sizeThatFits(maxMessageSize)
//         expectedSize.width += 24
//         expectedSize.height += 16
//
//         toastLabel.frame = CGRect(
//             x: (self.view.frame.size.width - expectedSize.width) / 2,
//             y: self.view.frame.size.height - expectedSize.height - 50,
//             width: expectedSize.width,
//             height: expectedSize.height
//         )
//
//         self.view.addSubview(toastLabel)
//
//         UIView.animate(withDuration: 0.5, animations: {
//             toastLabel.alpha = 1.0
//         }) { _ in
//             UIView.animate(withDuration: 0.5, delay: duration, options: .curveEaseOut, animations: {
//                 toastLabel.alpha = 0.0
//             }) { _ in
//                 toastLabel.removeFromSuperview()
//             }
//         }
//     }
// }

// @objc(FSIShareViewController)
@available(swift, introduced: 5.0)
open class FSIShareViewController: SLComposeServiceViewController {
    // MARK: - Config
    private(set) var hostAppBundleIdentifier: String = ""
    private(set) var appGroupId: String = ""
    
    // Results
    private var sharedMedia: [SharingFile] = []
    
    // Debug
    private let debugLogs = false
    
    // MARK: - Lifecycle
    open override func viewDidLoad() {
        super.viewDidLoad()
        loadIds()
    }
    
    open override func isContentValid() -> Bool {
        return true
    }

    // Override this method to return false if you don't want to redirect
    // to the host app automatically once the attachments are processed.
    // When false, the share compose UI stays visible and redirection
    // happens only when the user taps "Post". Default is true.
    open func shouldAutoRedirect() -> Bool {
        return true
    }

    open override func didSelectPost() {
        if self.sharedMedia.isEmpty {
            if let text = self.contentText, !text.isEmpty {
                self.sharedMedia.append(
                    SharingFile(value: text, thumbnail: nil, duration: nil, type: .text)
                )
                self.saveAndRedirect(message: text)
                return
            }
            self.completeAndExit()
        } else {
            self.saveAndRedirect()
        }
        // If the UI Post is used, save and redirect using contentText
//        saveAndRedirect(message: contentText)
    }
    
    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Process attachments automatically on appear like original FSI
        processAttachments()
    }
    
    // MARK: - Load Ids
    private func loadIds() {
        let shareExtId = Bundle.main.bundleIdentifier ?? ""
        if let idx = shareExtId.lastIndex(of: ".") {
            hostAppBundleIdentifier = String(shareExtId[..<idx])
        } else {
            hostAppBundleIdentifier = shareExtId
        }
        let custom = Bundle.main.object(forInfoDictionaryKey: kAppGroupIdKey) as? String
        appGroupId = custom ?? "group.\(hostAppBundleIdentifier)"
        log("loaded host=\(hostAppBundleIdentifier) group=\(appGroupId)")
    }
    
    // MARK: - Attachment processing (clean RSI style, preserve FSI features)
    private func processAttachments() {
        guard let content = extensionContext?.inputItems.first as? NSExtensionItem else {
            completeAndExit()
            return
        }
        
        guard let attachments = content.attachments, !attachments.isEmpty else {
            completeAndExit()
            return
        }
        
        // Use DispatchGroup to wait for async loads
        let group = DispatchGroup()
        for (index, provider) in attachments.enumerated() {
            group.enter()
            // Try all SharedMediaType options similar to RSI but preserve explicit FSI order
            if provider.isImage {
                // Use loadFileRepresentation so that Photos-library assets and transient
                // screenshot files (e.g. freshly taken screenshots on iOS 16+) are
                // materialised to a readable file:// URL before we try to copy them.
                // loadItem can return a ph:// or other non-file URL that FileManager
                // cannot copy, causing silent failure and the host app never opening.
                provider.loadFileRepresentation(forTypeIdentifier: UType.image) { [weak self] url, error in
                    defer { group.leave() }
                    guard let self = self, error == nil, let url = url else { self?.dismissWithError(); return }
                    self.handleImageItem(data: url as NSURL, index: index, total: attachments.count)
                }
                continue
            }
            
            if provider.isMovie {
                provider.loadItem(forTypeIdentifier: UType.movie, options: nil) { [weak self] data, error in
                    defer { group.leave() }
                    guard let self = self, error == nil else { self?.dismissWithError(); return }
                    self.handleVideoItem(data: data, index: index, total: attachments.count)
                }
                continue
            }
            
            if provider.isFile {
                provider.loadItem(forTypeIdentifier: UType.fileURL, options: nil) { [weak self] data, error in
                    defer { group.leave() }
                    guard let self = self, error == nil else { self?.dismissWithError(); return }
                    self.handleFileItem(data: data, index: index, total: attachments.count)
                }
                continue
            }
            
            if provider.isURL {
                provider.loadItem(forTypeIdentifier: UType.url, options: nil) { [weak self] data, error in
                    defer { group.leave() }
                    guard let self = self, error == nil else { self?.dismissWithError(); return }
                    self.handleUrlItem(data: data, index: index, total: attachments.count)
                }
                continue
            }
            
            if provider.isText {
                let id = provider.hasItemConformingToTypeIdentifier(UType.plainText)
                ? UType.plainText
                : UType.text
                provider.loadItem(forTypeIdentifier: id, options: nil) { [weak self] data, error in
                    defer { group.leave() }
                    guard let self = self, error == nil else { self?.dismissWithError(); return }
                    self.handleTextItem(data: data, index: index, total: attachments.count)
                }
                continue
            }
            
            if provider.isData {
                provider.loadItem(forTypeIdentifier: UType.data, options: nil) { [weak self] data, error in
                    defer { group.leave() }
                    guard let self = self, error == nil else { self?.dismissWithError(); return }
                    self.handleFileItem(data: data, index: index, total: attachments.count)
                }
                continue
            }
            
            if provider.isItem {
                provider.loadItem(forTypeIdentifier: UType.item, options: nil) { [weak self] data, error in
                    defer { group.leave() }
                    guard let self = self, error == nil else { self?.dismissWithError(); return }
                    self.handleFileItem(data: data, index: index, total: attachments.count)
                }
                continue
            }
                    
            log("Unknown provider type: \(provider.registeredTypeIdentifiers)")

            // Unknown type: just leave
            group.leave()
        }
        
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            // if we have media -> media, else fallback to complete
            if !self.sharedMedia.isEmpty {
                // Auto-redirect to the host app unless the subclass opted out.
                // When opted out, keep the compose UI so the user can add a
                // message and tap "Post" (handled in didSelectPost).
                if self.shouldAutoRedirect() {
                    self.saveAndRedirect()
                }
            } else {
                self.log("No shared media — stopping.")
                self.completeAndExit()
            }
        }
    }
    
    // MARK: - Individual handlers (preserve FSI behavior)
    private func handleTextItem(data: NSSecureCoding?, index: Int, total: Int) {
        if let s = data as? String {
            sharedMedia.append(SharingFile(value: s, thumbnail: nil, duration: nil, type: .text))
        } else if let url = data as? URL {
            sharedMedia.append(SharingFile(value: url.absoluteString, thumbnail: nil, duration: nil, type: .url))
        }
        
    }
    
    private func handleUrlItem(data: NSSecureCoding?, index: Int, total: Int) {
        if let url = data as? URL {
            sharedMedia.append(SharingFile(value: url.absoluteString, thumbnail: nil, duration: nil, type: .url))
        } else if let s = data as? String {
            sharedMedia.append(SharingFile(value: s, thumbnail: nil, duration: nil, type: .text))
        }
        
    }
    
    private func handleImageItem(data: NSSecureCoding?, index: Int, total: Int) {
        // data can be URL, UIImage, or Data
        if let url = data as? URL {
            let filename = getFileName(from: url, type: .image)
            if let dst = containerURL()?.appendingPathComponent(filename) {
                if copyFile(at: url, to: dst) {
                    sharedMedia.append(SharingFile(value: dst.path, mimeType: url.mimeType(), thumbnail: nil, duration: nil, type: .image))
                }
            }
        } else if let img = data as? UIImage {
            if let saved = writeTempImage(img) {
                sharedMedia.append(saved)
            }
        } else if let raw = data as? Data, let img = UIImage(data: raw) {
            if let saved = writeTempImage(img) {
                sharedMedia.append(saved)
            }
        }
        
    }
    
    private func handleVideoItem(data: NSSecureCoding?, index: Int, total: Int) {
        if let url = data as? URL {
            let filename = getFileName(from: url, type: .video)
            if let dst = containerURL()?.appendingPathComponent(filename) {
                if copyFile(at: url, to: dst) {
                    if let m = getSharedMediaFile(forVideo: dst) {
                        sharedMedia.append(m)
                    }
                }
            }
        }
        
    }
    
    private func handleFileItem(data: NSSecureCoding?, index: Int, total: Int) {
        if let url = data as? URL {
            let filename = getFileName(from: url, type: .file)
            if let dst = containerURL()?.appendingPathComponent(filename) {
                if copyFile(at: url, to: dst) {
                    sharedMedia.append(SharingFile(value: dst.path, mimeType: url.mimeType(), thumbnail: nil, duration: nil, type: .file))
                }
            }
        }
        else if let raw = data as? Data {
            let filename = "File_\(UUID().uuidString)"
            if let dst = containerURL()?.appendingPathComponent(filename) {
                do {
                    try raw.write(to: dst)
                    sharedMedia.append(SharingFile(value: dst.path, mimeType: "application/octet-stream", thumbnail: nil, duration: nil, type: .file))
                } catch {}
            }
        }
        
        
    }
    
    // MARK: - Helpers: write temp image
    private func writeTempImage(_ image: UIImage) -> SharingFile? {
        guard let container = containerURL() else { return nil }
        let tempName = "TempImage_\(UUID().uuidString).png"
        let dst = container.appendingPathComponent(tempName)
        do {
            if let d = image.pngData() {
                try d.write(to: dst)
                return SharingFile(value: dst.path, mimeType: "image/png", thumbnail: nil, duration: nil, type: .image)
            }
        } catch {
            log("writeTempImage error: \(error)")
        }
        return nil
    }
    
    
    private func saveAndRedirect(message: String? = nil) {
        let ud = UserDefaults(suiteName: appGroupId)
        if !sharedMedia.isEmpty {
            if let data = try? JSONEncoder().encode(sharedMedia) {
                ud?.set(data, forKey: kUserDefaultsKey)
            }
        }
        ud?.set(message, forKey: kUserDefaultsMessageKey)
        ud?.synchronize()
        redirectToHostApp()
    }
    
    
    private func redirectToHostApp() {
        loadIds()
        let raw = "\(kSchemePrefix)-\(hostAppBundleIdentifier)://dataUrl=\(kUserDefaultsKey)"
        guard let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            log("redirectToHostApp error: addingPercentEncoding failed for \(raw)")
            completeAndExit()
            return
        }
        guard let url = URL(string: encoded) else { completeAndExit(); return }

        // Walking the responder chain for UIApplication is undocumented, but it is
        // the only mechanism that actually opens a custom scheme from a Share
        // extension — verified working on iOS 18 hardware. Do not gate it behind an
        // availability check: NSExtensionContext.open is the documented API but is
        // honoured only for the Today and iMessage extension points, so for a Share
        // extension it silently does nothing and the host app never comes forward.
        // It is kept as a fallback in case a future iOS closes the responder route.
        if !openViaResponderChain(url) {
            log("redirectToHostApp: no responder could open \(url), falling back to extensionContext")
            extensionContext?.open(url, completionHandler: nil)
        }
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    /// Walks up from this view controller looking for something able to open a
    /// URL. Returns whether the open was actually dispatched, so the caller can
    /// fall back rather than fail silently.
    private func openViaResponderChain(_ url: URL) -> Bool {
        let sel = sel_registerName("openURL:")
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication {
                application.open(url, options: [:], completionHandler: nil)
                return true
            }
            if current.responds(to: sel) {
                _ = current.perform(sel, with: url)
                return true
            }
            responder = current.next
        }
        return false
    }

    // MARK: - File / thumbnail / metadata helpers
    func getExtension(from url: URL, type: SharingFileType) -> String {
        let parts = url.lastPathComponent.components(separatedBy: ".")
        var ex: String? = nil
        if parts.count > 1 { ex = parts.last }
        if ex == nil {
            switch type {
            case .image: ex = "png"
            case .video: ex = "mp4"
            case .file: ex = "txt"
            case .text: ex = "txt"
            case .url: ex = "txt"
            }
        }
        return ex ?? "bin"
    }
    
    func getFileName(from url: URL, type: SharingFileType) -> String {
        var name = url.lastPathComponent
        if name.isEmpty { name = UUID().uuidString + "." + getExtension(from: url, type: type) }
        return name
    }
    
    func copyFile(at srcURL: URL, to dstURL: URL) -> Bool {
        guard srcURL.isFileURL else {
            log("copyFile error: srcURL is not a file URL: \(srcURL)")
            return false
        }
        guard dstURL.isFileURL else {
            log("copyFile error: dstURL is not a file URL: \(dstURL)")
            return false
        }

        // Files provided by the Files app (iCloud Drive, third-party file
        // providers, etc.) are exposed as security-scoped URLs. Without
        // starting access and coordinating the read, the source file may
        // not be materialized and copyItem silently produces a 0-byte file.
        let needsSecurityScope = srcURL.startAccessingSecurityScopedResource()
        defer {
            if needsSecurityScope { srcURL.stopAccessingSecurityScopedResource() }
        }

        var success = false
        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: srcURL, options: [], error: &coordinatorError) { coordinatedURL in
            guard FileManager.default.fileExists(atPath: coordinatedURL.path) else {
                log("copyFile error: source file does not exist at coordinated path: \(coordinatedURL.path)")
                return
            }
            do {
                if FileManager.default.fileExists(atPath: dstURL.path) { try FileManager.default.removeItem(at: dstURL) }
                try FileManager.default.copyItem(at: coordinatedURL, to: dstURL)
                success = true
            } catch {
                log("copyFile error copying from \(coordinatedURL.path) to \(dstURL.path): \(error)")
            }
        }
        if let coordinatorError = coordinatorError {
            log("copyFile coordinator error for \(srcURL.path): \(coordinatorError), userInfo: \(coordinatorError.userInfo)")
            return false
        }
        return success
    }
    
    private func getSharedMediaFile(forVideo: URL) -> SharingFile? {
        let asset = AVAsset(url: forVideo)
        let duration = (CMTimeGetSeconds(asset.duration) * 1000).rounded()
        let thumbnailPath = getThumbnailPath(for: forVideo)
        
        if FileManager.default.fileExists(atPath: thumbnailPath.path) {
            return SharingFile(value: forVideo.path, mimeType: forVideo.mimeType(), thumbnail: thumbnailPath.path, duration: Int(duration), type: .video)
        }
        
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 360, height: 360)
        
        // Use first second or zero
        let time = CMTime(seconds: min(1.0, CMTimeGetSeconds(asset.duration)), preferredTimescale: 600)
        do {
            let cg = try gen.copyCGImage(at: time, actualTime: nil)
            if let data = UIImage(cgImage: cg).jpegData(compressionQuality: 0.8) {
                try data.write(to: thumbnailPath)
                return SharingFile(value: forVideo.path, mimeType: forVideo.mimeType(), thumbnail: thumbnailPath.path, duration: Int(duration), type: .video)
            }
        } catch {
            log("getSharedMediaFile thumbnail error: \(error)")
        }
        
        // fallback
        return SharingFile(value: forVideo.path, mimeType: forVideo.mimeType(), thumbnail: nil, duration: Int(duration), type: .video)
    }
    
    private func getThumbnailPath(for url: URL) -> URL {
        guard let container = containerURL() else { fatalError("App group not configured or missing") }
        let fileName = Data(url.lastPathComponent.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
        return container.appendingPathComponent("\(fileName).jpg")
    }
    
    private func containerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
    }
    
    private func completeAndExit() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
    
    private func dismissWithError() {
        log("[ERROR] Error loading data!")
        let alert = UIAlertController(title: "Error", message: "Error loading data", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .cancel) { _ in self.dismiss(animated: true, completion: nil) })
        present(alert, animated: true, completion: nil)
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
    
    private func writeTempFile(_ image: UIImage, to dstURL: URL) -> Bool {
        do {
            if FileManager.default.fileExists(atPath: dstURL.path) { try FileManager.default.removeItem(at: dstURL) }
            let pngData = image.pngData()
            try pngData?.write(to: dstURL)
            return true
        } catch (let error) {
            log("writeTempFile error: \(error)")
            return false
        }
    }
    
    private func saveToUserDefaults(data: [SharingFile]) {
        let ud = UserDefaults(suiteName: appGroupId)
        if let enc = try? JSONEncoder().encode(data) { ud?.set(enc, forKey: kUserDefaultsKey); ud?.synchronize() }
    }
    
    // MARK: - Logging
    // NSLog rather than print: a Share extension's stdout is not captured, so
    // print() is only visible with a debugger already attached. NSLog reaches the
    // unified log, where `log stream --predicate 'process == "ShareExtension"'`
    // can pick it up without attaching to a process that is not running yet.
    private func log(_ s: String) { if debugLogs { NSLog("[FSIShareVC] %@", s) } }
    
}

// MARK: - Extensions
extension URL {
    func mimeType() -> String {
        if #available(iOS 14.0, *) {
            if let ut = UTType(filenameExtension: self.pathExtension), let m = ut.preferredMIMEType { return m }
        } else {
            if let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, self.pathExtension as NSString, nil)?.takeRetainedValue() {
                if let mimetype = UTTypeCopyPreferredTagWithClass(uti, kUTTagClassMIMEType)?.takeRetainedValue() { return mimetype as String }
            }
        }
        return "application/octet-stream"
    }
}

extension NSItemProvider {
    var isImage: Bool { return hasItemConformingToTypeIdentifier(UType.image) }
    var isMovie: Bool { return hasItemConformingToTypeIdentifier(UType.movie) }
    var isText: Bool {
        hasItemConformingToTypeIdentifier(UType.plainText) || hasItemConformingToTypeIdentifier(UType.text)
    }
    var isURL: Bool { return hasItemConformingToTypeIdentifier(UType.url) }
    var isFile: Bool { return hasItemConformingToTypeIdentifier(UType.fileURL) }
    var isData:Bool { return hasItemConformingToTypeIdentifier(UType.data) }
    var isItem: Bool { hasItemConformingToTypeIdentifier(UType.item) }

}

extension Array {
    subscript(safe index: UInt) -> Element? { return Int(index) < count ? self[Int(index)] : nil }
}


class SharingFile: Codable {
    var value: String
    var mimeType: String?
    var thumbnail: String?; // video thumbnail
    var duration: Int?; // video duration in milliseconds
    var type: SharingFileType;
    var message: String? // post message
    
    enum CodingKeys: String, CodingKey {
        case value
        case mimeType
        case thumbnail
        case duration
        case type
        case message
    }
    
    init(value: String, mimeType: String? = nil, thumbnail: String?, duration: Int?,
         type: SharingFileType, message: String?=nil) {
        self.value = value
        self.mimeType = mimeType
        self.thumbnail = thumbnail
        self.duration = duration
        self.type = type
        self.message = message
    }
    
    // Debug method to print out SharedMediaFile details in the console
    func toString() {
        print("[SharingFile] \n\tvalue: \(self.value)\n\tthumbnail: \(self.thumbnail ?? "--" )\n\tduration: \(self.duration ?? 0)\n\ttype: \(self.type)\n\tmimeType: \(String(describing: self.mimeType))\n\tmessage: \(String(describing: self.message))")
    }
}


enum SharingFileType: Int, Codable {
    case text
    case url
    case image
    case video
    case file
}

// Unified UTType → works on iOS 11–18
enum UType {
    static var image: String {
        if #available(iOS 14.0, *) {
            return UTType.image.identifier
        } else {
            return kUTTypeImage as String   // old API
        }
    }
    
    static var movie: String {
        if #available(iOS 14.0, *) {
            return UTType.movie.identifier
        } else {
            return kUTTypeMovie as String
        }
    }
    
    
    static var url: String {
        if #available(iOS 14.0, *) {
            return UTType.url.identifier
        } else {
            return kUTTypeURL as String
        }
    }
    
    static var fileURL: String {
        if #available(iOS 14.0, *) {
            return UTType.fileURL.identifier
        } else {
            return kUTTypeFileURL as String
        }
    }
    
    static var text: String {
        if #available(iOS 14.0, *) {
            return UTType.text.identifier
        } else {
            return kUTTypeText as String
        }
    }
    
    static var plainText: String {
        if #available(iOS 14.0, *) {
            return UTType.plainText.identifier
        } else {
            return kUTTypePlainText as String
        }
    }
    
    static var data: String {
        if #available(iOS 14.0, *) {
            return UTType.data.identifier
        } else {
            return kUTTypeData as String
        }
    }
    
    static var item: String {
        if #available(iOS 14.0, *) {
            return UTType.item.identifier
        } else {
            return kUTTypeItem as String
        }
    }
}

