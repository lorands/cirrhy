// Copyright 2026 Lóránd Somogyi
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Flutter
import UIKit
import UniformTypeIdentifiers
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var folders: DocumentFolders?
  private var watcher: DocumentFolderWatcher?
  private var changes: FlutterEventChannel?
  private var badge: TimerBadge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CirrhyDocumentFolders")
    guard let messenger = registrar?.messenger() else { return }

    // Built before the folders: they coordinate their own reads and writes
    // *as* this presenter, which is what stops our own saves coming back to us
    // as somebody else's change.
    let watcher = DocumentFolderWatcher()
    self.watcher = watcher
    let changes = FlutterEventChannel(
      name: DocumentFolderWatcher.channelName, binaryMessenger: messenger)
    changes.setStreamHandler(watcher)
    self.changes = changes

    let folders = DocumentFolders(watcher: watcher)
    self.folders = folders
    FlutterMethodChannel(name: DocumentFolders.channelName, binaryMessenger: messenger)
      .setMethodCallHandler { call, result in folders.handle(call, result: result) }

    let badge = TimerBadge()
    self.badge = badge
    FlutterMethodChannel(name: TimerBadge.channelName, binaryMessenger: messenger)
      .setMethodCallHandler { call, result in badge.handle(call, result: result) }
  }
}

/// The iOS half of the running-timer badge (TimerBadge on the Dart side).
///
/// iOS offers exactly one icon adornment, the numeric badge, and gates it
/// behind notification authorization. So a running timer is badge "1", asked
/// for with `.badge` alone the first time a timer starts — that prompt is the
/// OS's, shown once; after a refusal the timer keeps running and only the
/// badge goes missing. Clearing needs no authorization.
final class TimerBadge: NSObject {
  static let channelName = "com.lorands.cirrhy/badge"

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "setTimer" else {
      result(FlutterMethodNotImplemented)
      return
    }
    let arguments = call.arguments as? [String: Any] ?? [:]
    if arguments["running"] as? Bool ?? false {
      UNUserNotificationCenter.current().requestAuthorization(options: [.badge]) {
        granted, _ in
        guard granted else { return }
        DispatchQueue.main.async { Self.apply(1) }
      }
    } else {
      Self.apply(0)
    }
    result(nil)
  }

  private static func apply(_ count: Int) {
    if #available(iOS 16.0, *) {
      UNUserNotificationCenter.current().setBadgeCount(count)
    } else {
      UIApplication.shared.applicationIconBadgeNumber = count
    }
  }
}

/// The iOS half of the file-access port (DESIGN.md §4.1).
///
/// The durable handle is a **security-scoped bookmark**, because a sandboxed
/// app's access to a picked folder does not outlive the process. Every access
/// is wrapped in `startAccessingSecurityScopedResource` and coordinated
/// through `NSFileCoordinator`, which is also what pulls down a file the
/// provider has not materialised yet (§4.4).
///
/// This is deliberately a near-copy of the macOS implementation in
/// `macos/Runner/MainFlutterWindow.swift`. The two differ only in how the
/// folder is chosen and in one bookmark option, and sharing a file between the
/// two Xcode targets would mean editing both project files by hand — a worse
/// trade than keeping two short files honest.
final class DocumentFolders: NSObject, UIDocumentPickerDelegate {
  static let channelName = "com.lorands.cirrhy/documents"

  /// Matches ChannelDocumentDirectory.unavailableCode on the Dart side.
  static let unavailableCode = "unavailable"
  private static let failed = "failed"

  private var pendingPick: FlutterResult?

  /// The folder presenter, so every coordinated access here is made *as* it.
  /// A presenter is never told about changes made through its own coordinator,
  /// which is how our own saves stay out of the change stream — the app
  /// re-reading the file it just wrote is not news.
  private let watcher: DocumentFolderWatcher?

  init(watcher: DocumentFolderWatcher? = nil) {
    self.watcher = watcher
    super.init()
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]

    switch call.method {
    case "pickDirectory":
      pickDirectory(result: result)

    case "isAvailable":
      let handle = arguments["handle"] as? String
      offMainThread(result) { self.isAvailable(handle) }

    case "listDocuments":
      let handle = arguments["handle"] as? String
      let names = arguments["names"] as? [String] ?? []
      offMainThread(result) { try self.listDocuments(handle, names: names) }

    case "readDocument":
      let handle = arguments["handle"] as? String
      let name = arguments["name"] as? String
      offMainThread(result) { try self.readDocument(handle, name: name) }

    case "writeDocument":
      let handle = arguments["handle"] as? String
      let name = arguments["name"] as? String
      let bytes = arguments["bytes"] as? FlutterStandardTypedData
      offMainThread(result) { try self.writeDocument(handle, name: name, bytes: bytes?.data) }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Picking

  private func pickDirectory(result: @escaping FlutterResult) {
    guard pendingPick == nil else {
      result(FlutterError(code: Self.failed, message: "a folder picker is already open", details: nil))
      return
    }
    guard let presenter = Self.topViewController() else {
      result(FlutterError(code: Self.failed, message: "no window to present the picker", details: nil))
      return
    }

    pendingPick = result
    // A folder, not a document (§4.2). Document scope would rule out writing a
    // sibling temp file and renaming over the original, so every save would
    // become an in-place overwrite of the file holding everything.
    //
    // This initialiser and `UTType.folder` are iOS 14, which is why the target
    // is 14.0 rather than Flutter's template default of 13.0. The iOS 13 way
    // in is the deprecated `documentTypes:in:`, not worth carrying.
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
    picker.delegate = self
    picker.allowsMultipleSelection = false
    presenter.present(picker, animated: true)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let result = pendingPick else { return }
    pendingPick = nil
    guard let url = urls.first else {
      result(nil)
      return
    }

    guard url.startAccessingSecurityScopedResource() else {
      result(FlutterError(code: Self.unavailableCode, message: "that folder could not be opened", details: nil))
      return
    }
    defer { url.stopAccessingSecurityScopedResource() }

    do {
      let bookmark = try url.bookmarkData(
        options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
      result([
        "handle": bookmark.base64EncodedString(),
        // The bookmark itself is unshowable, so the folder's name travels
        // with it for the UI to display.
        "label": url.lastPathComponent,
      ])
    } catch {
      result(FlutterError(code: Self.unavailableCode, message: error.localizedDescription, details: nil))
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    let result = pendingPick
    pendingPick = nil
    result?(nil)
  }

  private static func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let windows = scenes.flatMap { $0.windows }
    guard let root = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController else {
      return nil
    }
    var top = root
    while let presented = top.presentedViewController { top = presented }
    return top
  }

  // MARK: - The folder

  /// Resolves the bookmark and runs [body] with the folder access open.
  ///
  /// A bookmark that resolves as stale is still used. Apple's advice is to
  /// rebuild it, which needs a way to hand the replacement back to Dart that
  /// the channel does not have yet; forcing the user to re-pick a folder that
  /// still works would be the worse of the two.
  private func withFolder<T>(_ handle: String?, _ body: (URL) throws -> T) throws -> T {
    guard let handle, let data = Data(base64Encoded: handle) else {
      throw Unavailable("the stored folder handle is unreadable")
    }

    var stale = false
    let url: URL
    do {
      url = try URL(
        resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
    } catch {
      throw Unavailable(error.localizedDescription)
    }

    guard url.startAccessingSecurityScopedResource() else {
      throw Unavailable("access to that folder was withdrawn")
    }
    defer { url.stopAccessingSecurityScopedResource() }
    return try body(url)
  }

  private func isAvailable(_ handle: String?) -> Bool {
    (try? withFolder(handle) { url in
      var isDirectory: ObjCBool = false
      let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
      return exists && isDirectory.boolValue && FileManager.default.isWritableFile(atPath: url.path)
    }) ?? false
  }

  private func listDocuments(_ handle: String?, names: [String]) throws -> [String] {
    try withFolder(handle) { url in
      names.filter { FileManager.default.fileExists(atPath: url.appendingPathComponent($0).path) }
    }
  }

  private func readDocument(_ handle: String?, name: String?) throws -> FlutterStandardTypedData? {
    guard let name else { throw Unavailable("no document name") }
    return try withFolder(handle) { folder in
      let file = folder.appendingPathComponent(name)
      // Nothing there is the ordinary first run. A missing *folder* threw
      // above, because reading that as an empty document would write the
      // user's history away on the next save.
      guard FileManager.default.fileExists(atPath: file.path) else { return nil }

      var coordinationError: NSError?
      var data: Data?
      var readError: Error?
      // Coordinated, which is also what makes a provider materialise a file it
      // has only a placeholder for (§4.4).
      NSFileCoordinator(filePresenter: watcher).coordinate(
        readingItemAt: file, options: [], error: &coordinationError
      ) {
        url in
        do { data = try Data(contentsOf: url) } catch { readError = error }
      }
      if let error = coordinationError ?? readError {
        throw Unavailable(error.localizedDescription)
      }
      return data.map { FlutterStandardTypedData(bytes: $0) }
    }
  }

  private func writeDocument(_ handle: String?, name: String?, bytes: Data?) throws {
    guard let name, let bytes else { throw Unavailable("nothing to write") }
    try withFolder(handle) { folder in
      let file = folder.appendingPathComponent(name)

      var coordinationError: NSError?
      var writeError: Error?
      NSFileCoordinator(filePresenter: watcher).coordinate(
        writingItemAt: file, options: .forReplacing, error: &coordinationError
      ) { url in
        // The block's URL, not ours: under .forReplacing the coordinator is
        // entitled to hand back somewhere else, and that is the item to
        // replace.
        do { try Self.replaceContents(of: url, with: bytes) } catch { writeError = error }
      }
      if let error = coordinationError ?? writeError {
        throw Unavailable(error.localizedDescription)
      }
    }
  }

  /// Temp file, then `replaceItemAt` — KeePass's file transaction (§4.3), and
  /// the reason directory scope was needed (§4.2).
  ///
  /// Deliberately **not** `Data.write(options: .atomic)`, which was here first
  /// and does the same temp-then-rename with none of the care. Measured on
  /// APFS (2026-08-15), replacing a file carrying an extended attribute:
  ///
  ///     strategy          inode   creation date   xattrs
  ///     .atomic           new     lost            LOST
  ///     replaceItemAt     new     kept            kept
  ///     in-place write    same    kept            kept
  ///
  /// The xattr column is the one that matters. A File Provider stamps the
  /// items it tracks, so a save that wipes those stamps hands the provider an
  /// unrecognisable file at a path it thought it owned. Read as
  /// delete-then-create, that leaves the provider holding a brand-new local
  /// item it will happily upload, while remote changes to the original have
  /// nowhere left to land: writes out, nothing back — the exact shape of the
  /// iOS-against-Dropbox report this came from. §4.3 warned that replacing the
  /// file breaks its identity for sync clients; this is what that cost.
  ///
  /// Note neither temp-and-swap strategy keeps the inode, so this is about
  /// carried metadata rather than about the file object surviving.
  /// `replaceItemAt` is also what document-based apps use for this job, and it
  /// keeps §4.3's crash guarantee, which an in-place write would not.
  private static func replaceContents(of file: URL, with bytes: Data) throws {
    // The first save has nothing to replace, and replaceItemAt requires an
    // original.
    guard FileManager.default.fileExists(atPath: file.path) else {
      try bytes.write(to: file)
      return
    }

    // Beside the file it replaces, so the swap stays on one volume, and
    // carrying the prefix from documentTempPrefix on the Dart side so a temp
    // left behind by a crash is recognisably ours.
    let temp = file.deletingLastPathComponent()
      .appendingPathComponent("cirrhy.json.tmp-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: temp) }

    do {
      try bytes.write(to: temp)
      _ = try FileManager.default.replaceItemAt(file, withItemAt: temp)
    } catch {
      // §4.3's escape hatch, the same one PathDocumentStore takes when a cloud
      // client holding the file makes the swap fail: overwrite in place. Safe
      // to take because the caller has already snapshotted the previous bytes
      // (DocumentBackup, app-private, before every write).
      try bytes.write(to: file)
    }
  }

  // MARK: - Plumbing

  private struct Unavailable: Error {
    let message: String
    init(_ message: String) { self.message = message }
  }

  /// Runs the work off the main thread and answers on it, because a
  /// FlutterResult may only be delivered from the platform thread.
  private func offMainThread(_ result: @escaping FlutterResult, _ work: @escaping () throws -> Any?) {
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let value = try work()
        // Void marks a void method (writeDocument); the standard codec
        // cannot encode the empty tuple, so answer nil.
        let reply = value is Void ? nil : value
        DispatchQueue.main.async { result(reply) }
      } catch let error as Unavailable {
        DispatchQueue.main.async {
          result(FlutterError(code: Self.unavailableCode, message: error.message, details: nil))
        }
      } catch {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: Self.failed, message: error.localizedDescription, details: nil))
        }
      }
    }
  }
}

/// The folder saying it changed (DESIGN.md §4.4, the "no change notification"
/// failure mode, partly bought back).
///
/// Registering an `NSFilePresenter` for the chosen folder is the documented way
/// to say *somebody is looking at this*, and it does two jobs at once. The
/// system calls back when an item under the folder changes, which is how the
/// app learns about another device's write the moment it lands instead of on
/// its next scheduled read. And a File Provider is told the item is being
/// observed, which is the hook a provider is supposed to use to keep it fresh.
///
/// **It is a nudge, not a guarantee**, and the Dart side is built accordingly:
/// a provider that never signals still never signals, so `SessionRefresher`
/// keeps asking on its own schedule and this only ever makes it quicker.
///
/// The subscription owns the registration — one Dart listener, one presenter,
/// and the folder's security scope held open for exactly that long, which is
/// the one place in this file where access outlives a single call.
final class DocumentFolderWatcher: NSObject, NSFilePresenter, FlutterStreamHandler {
  static let channelName = "com.lorands.cirrhy/document-changes"

  /// Guards [folder] alone. The presenter machinery reads `presentedItemURL`
  /// from its own thread while listen/cancel write it from the platform one;
  /// `sink` and `scoped` need no lock, being touched only on the latter.
  ///
  /// Never held across `addFilePresenter`/`removeFilePresenter`: those
  /// synchronise with the presenter queue, which is where the read that wants
  /// this lock comes from.
  private let lock = NSLock()
  private var folder: URL?

  private var sink: FlutterEventSink?
  private var scoped = false

  // MARK: - NSFilePresenter

  var presentedItemURL: URL? {
    lock.lock()
    defer { lock.unlock() }
    return folder
  }

  /// Serial, and deliberately not the main queue: the callbacks land here and
  /// the coordination machinery can block on it.
  let presentedItemOperationQueue: OperationQueue = {
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    queue.name = "com.lorands.cirrhy.folder-presenter"
    return queue
  }()

  func presentedItemDidChange() { announce() }
  func presentedSubitemDidChange(at url: URL) { announce() }
  func presentedSubitemDidAppear(at url: URL) { announce() }
  func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) { announce() }

  /// One undifferentiated "something changed". Which file and what about it
  /// are questions Dart answers by re-reading and hashing, and answers better
  /// — the same decision as everywhere else on this channel: the native side
  /// carries bytes and events, never meaning.
  private func announce() {
    DispatchQueue.main.async { self.sink?(nil) }
  }

  // MARK: - FlutterStreamHandler

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    guard let handle = arguments as? String, let data = Data(base64Encoded: handle) else {
      return FlutterError(
        code: DocumentFolders.unavailableCode, message: "the stored folder handle is unreadable",
        details: nil)
    }

    var stale = false
    guard
      let url = try? URL(
        resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
    else {
      return FlutterError(
        code: DocumentFolders.unavailableCode, message: "that folder could not be opened",
        details: nil)
    }

    stop()
    scoped = url.startAccessingSecurityScopedResource()
    sink = events
    lock.lock()
    folder = url
    lock.unlock()
    NSFileCoordinator.addFilePresenter(self)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    stop()
    return nil
  }

  private func stop() {
    lock.lock()
    let previous = folder
    lock.unlock()

    sink = nil
    guard let previous else { return }

    NSFileCoordinator.removeFilePresenter(self)
    lock.lock()
    folder = nil
    lock.unlock()

    if scoped {
      previous.stopAccessingSecurityScopedResource()
      scoped = false
    }
  }
}
