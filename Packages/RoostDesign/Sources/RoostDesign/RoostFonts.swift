// Registers the bundled OFL fonts with CoreText. Call once at app launch (or in a preview) before
// using RoostFont. Safe to call repeatedly; already-registered files are skipped.
import Foundation
import CoreText

public enum RoostFonts {
    /// File names bundled under Resources/Fonts. Variable fonts carry their full weight axis.
    public static let files: [String] = [
        "Fraunces-Variable.ttf",
        "NunitoSans-Variable.ttf",
        "IBMPlexMono-Regular.ttf",
        "IBMPlexMono-Medium.ttf",
        "IBMPlexMono-SemiBold.ttf",
    ]

    private static let lock = NSLock()
    nonisolated(unsafe) private static var registered = Set<String>()

    /// Registers every bundled font file. Returns the files that were registered in this call,
    /// or throws if a file is missing from the bundle (a packaging error, not a runtime condition).
    @discardableResult
    public static func register() throws -> [String] {
        lock.lock(); defer { lock.unlock() }
        var done: [String] = []
        for file in files where !registered.contains(file) {
            guard let url = Bundle.module.url(forResource: file, withExtension: nil, subdirectory: "Fonts") else {
                throw RegistrationError.missing(file)
            }
            var err: Unmanaged<CFError>?
            let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &err)
            if !ok, let e = err?.takeRetainedValue() {
                // Already registered by another path (e.g. an app Info.plist) is not a failure.
                let code = CFErrorGetCode(e)
                if code != CTFontManagerError.alreadyRegistered.rawValue {
                    throw RegistrationError.failed(file, String(describing: e))
                }
            }
            registered.insert(file)
            done.append(file)
        }
        return done
    }

    public enum RegistrationError: Error, CustomStringConvertible {
        case missing(String)
        case failed(String, String)
        public var description: String {
            switch self {
            case .missing(let f): return "RoostFonts: \(f) is not in the package bundle"
            case .failed(let f, let why): return "RoostFonts: could not register \(f): \(why)"
            }
        }
    }
}
