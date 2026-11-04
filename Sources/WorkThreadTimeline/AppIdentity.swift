import Foundation

enum AppIdentity {
    static let displayName = "Float"
    static let bundleIdentifier = "local.xline.WorkThreadTimeline"
    static let executableName = "WorkThreadTimeline"
    /// Written into Info.plist only by the release workflow, so local and QA
    /// builds never try to replace themselves.
    static let releaseTagKey = "FloatReleaseTag"
    static let releaseRepository = "ReflectionL/Float"

    /// The release this build was packaged from, or nil for unpackaged builds.
    static var installedVersion: ReleaseVersion? {
        (Bundle.main.object(forInfoDictionaryKey: releaseTagKey) as? String)
            .flatMap(ReleaseVersion.init)
    }

    /// The release asset name, as the release workflow writes it.
    static func archiveName(for version: ReleaseVersion) -> String {
        "Float-\(version).dmg"
    }
}
