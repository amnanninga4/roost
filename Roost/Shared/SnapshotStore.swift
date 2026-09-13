// Where the snapshot lives: one file in the App Group container the app and the widget share.
//
// Compiled into both targets. The app calls `write`, the widget calls `read`, and neither one knows
// anything about the other's storage.
//
// The App Group is granted by an entitlement, and an entitlement needs a signature. A build made with
// `CODE_SIGNING_ALLOWED=NO` (CI's simulator build, and any `xcodebuild` with signing off) has no
// entitlements at all, so `containerURL` comes back nil. That is not an error worth crashing or logging on
// every call: `SnapshotStore.appGroup()` is Optional, the writer skips its write, and the widget shows the
// state it shows when there is no file. Tests point the store at a temporary directory instead.
import Foundation

/// A directory that holds `snapshot.json`, plus the two ways of getting one.
struct SnapshotStore: Sendable {
    /// The App Group both the app target and the widget extension declare. Changing this string means
    /// changing both entitlements files in `project.yml`, and the widget goes blank until both are rebuilt.
    static let appGroupIdentifier = "group.xyz.hinescreative.roost"

    static let fileName = "snapshot.json"

    let directory: URL

    /// The shared container, or nil when this build has no App Group entitlement (unsigned builds) or iOS
    /// has not provisioned the container yet.
    static func appGroup() -> SnapshotStore? {
        guard let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        else { return nil }
        return SnapshotStore(directory: url)
    }

    var fileURL: URL {
        directory.appending(path: Self.fileName)
    }

    /// Writes the snapshot, replacing whatever was there. Atomic, so a widget reading mid-write gets the
    /// old file rather than half of the new one.
    func write(_ snapshot: RoostSnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try snapshot.encoded().write(to: fileURL, options: .atomic)
    }

    /// The snapshot on disk, or nil when there is none (a fresh install, or an unsigned build) or it cannot
    /// be decoded (a snapshot from a newer app than this widget). Both read as "no snapshot" on purpose:
    /// the widget has one plain state for "nothing to show yet" and does not need to explain which.
    func read() -> RoostSnapshot? {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? RoostSnapshot.decoded(from: data),
              snapshot.isReadable
        else { return nil }
        return snapshot
    }

    /// Removes the file. Only used by tests; the app overwrites rather than deletes, because an unpaired
    /// phone still has a snapshot to show — the one that says it is not paired.
    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
