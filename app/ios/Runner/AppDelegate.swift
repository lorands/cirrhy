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
    let folders = DocumentFolders()
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
  private static let unavailable = "unavailable"
  private static let failed = "failed"

  private var pendingPick: FlutterResult?

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
      result(FlutterError(code: Self.unavailable, message: "that folder could not be opened", details: nil))
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
      result(FlutterError(code: Self.unavailable, message: error.localizedDescription, details: nil))
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
      NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: &coordinationError) {
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
      NSFileCoordinator().coordinate(
        writingItemAt: file, options: .forReplacing, error: &coordinationError
      ) { url in
        // .atomic is temp-then-rename inside the same directory — KeePass's
        // file transaction (§4.3), and the reason directory scope was needed.
        do { try bytes.write(to: url, options: .atomic) } catch { writeError = error }
      }
      if let error = coordinationError ?? writeError {
        throw Unavailable(error.localizedDescription)
      }
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
          result(FlutterError(code: Self.unavailable, message: error.message, details: nil))
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
