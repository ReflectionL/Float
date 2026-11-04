import Foundation

/// Release feed parsing, version ordering and the update controller's state
/// machine, using fakes for the network and installer.
@main
struct UpdateTests {
    @MainActor
    static func main() async throws {
        versions()
        try feeds()
        checksums()
        try await controller()
        print("PASS: updates")
    }

    static func expect(_ condition: Bool, _ message: String, line: Int = #line) {
        if !condition { fatalError("FAIL (line \(line)): \(message)") }
    }

    static func v(_ text: String) -> ReleaseVersion { ReleaseVersion(text)! }

    static func versions() {
        expect(ReleaseVersion("v0.5.4")?.description == "0.5.4", "leading v")
        expect(ReleaseVersion("1.2") == nil, "two parts")
        expect(ReleaseVersion("1.2.x") == nil, "non-numeric")
        expect(ReleaseVersion("1.2.3-") == nil, "empty prerelease")
        expect(v("0.5.3") < v("0.5.4"), "patch")
        expect(v("0.9.0") < v("0.10.0"), "numeric minor")
        expect(v("0.6.0-beta.2") < v("0.6.0-beta.10"), "numeric prerelease")
        expect(v("0.6.0-rc.1") < v("0.6.0"), "prerelease before release")
        expect(!(v("0.5.3") < v("0.5.3")), "irreflexive")
    }

    static func releaseJSON(_ tag: String, draft: Bool = false, host: String = "github.com", checksum: Bool = true) -> String {
        let name = "Float-\(tag.dropFirst()).zip"
        var assets = #"{"name":"\#(name)","browser_download_url":"https://\#(host)/ReflectionL/Float/releases/download/\#(tag)/\#(name)"}"#
        if checksum {
            assets += #",{"name":"\#(name).sha256","browser_download_url":"https://github.com/ReflectionL/Float/releases/download/\#(tag)/\#(name).sha256"}"#
        }
        return #"{"tag_name":"\#(tag)","draft":\#(draft),"body":"notes","html_url":"https://github.com/ReflectionL/Float/releases/tag/\#(tag)","assets":[\#(assets)]}"#
    }

    static func feeds() throws {
        let list = Data("[\([releaseJSON("v0.5.4"), releaseJSON("v0.5.10"), releaseJSON("v0.5.9")].joined(separator: ","))]".utf8)
        let newest = try ReleaseFeed.newest(from: list)
        expect(newest?.tag == "v0.5.10", "newest regardless of order")
        expect(newest?.archiveName == "Float-0.5.10.zip", "archive name")
        expect(newest?.notes == "notes", "notes")

        let unusable = Data("[\([releaseJSON("v0.9.0", draft: true), releaseJSON("v0.8.0", checksum: false), releaseJSON("v0.7.0", host: "evil.example.com"), releaseJSON("v0.5.4")].joined(separator: ","))]".utf8)
        expect(try ReleaseFeed.newest(from: unusable)?.tag == "v0.5.4", "skips drafts, missing checksums, untrusted hosts")
        expect(try ReleaseFeed.newest(from: Data("[]".utf8)) == nil, "empty list")
        do {
            _ = try ReleaseFeed.newest(from: Data("{}".utf8))
            expect(false, "malformed list must throw")
        } catch {}

        func entry(_ tag: String) -> String {
            #"<entry><link rel="alternate" type="text/html" href="https://github.com/ReflectionL/Float/releases/tag/\#(tag)"/></entry>"#
        }
        let atom = Data(#"<?xml version="1.0"?><feed xmlns="http://www.w3.org/2005/Atom"><link rel="alternate" href="https://github.com/ReflectionL/Float/releases"/>\#(entry("v0.5.4"))\#(entry("v0.6.0"))\#(entry("nightly"))</feed>"#.utf8)
        let fromAtom = try ReleaseFeed.newest(fromAtom: atom, repository: "ReflectionL/Float")
        expect(fromAtom?.tag == "v0.6.0", "atom newest")
        expect(fromAtom?.archiveURL.absoluteString == "https://github.com/ReflectionL/Float/releases/download/v0.6.0/Float-0.6.0.zip", "atom archive URL")
        expect(fromAtom?.checksumURL.absoluteString == "https://github.com/ReflectionL/Float/releases/download/v0.6.0/Float-0.6.0.zip.sha256", "atom checksum URL")

        expect(ReleaseFeed.isTrustedDownload(URL(string: "https://objects.githubusercontent.com/x")!), "github cdn")
        expect(!ReleaseFeed.isTrustedDownload(URL(string: "http://github.com/a")!), "http")
        expect(!ReleaseFeed.isTrustedDownload(URL(string: "https://github.com.evil.io/a")!), "lookalike host")
    }

    static func checksums() {
        let digest = String(repeating: "ab", count: 32)
        expect(ReleaseFeed.checksum(from: "\(digest)  Float-0.5.4.zip\n", expectedName: "Float-0.5.4.zip") == digest, "shasum format")
        expect(ReleaseFeed.checksum(from: "\(digest.uppercased())  Float-0.5.4.zip", expectedName: "Float-0.5.4.zip") == digest, "uppercase")
        expect(ReleaseFeed.checksum(from: "\(digest)  Other.zip", expectedName: "Float-0.5.4.zip") == nil, "other file")
        expect(ReleaseFeed.checksum(from: "abc  Float-0.5.4.zip", expectedName: "Float-0.5.4.zip") == nil, "short digest")
    }

    struct FakeFetcher: ReleaseFetching {
        let result: Result<AvailableRelease?, ReleaseFeedError>
        func newestRelease() async throws -> AvailableRelease? { try result.get() }
    }

    final class FakeInstaller: UpdateInstalling, @unchecked Sendable {
        var relaunched = false
        func prepare(_ release: AvailableRelease, replacing appURL: URL) async throws -> PreparedUpdate {
            PreparedUpdate(stagedApp: appURL, workDirectory: appURL, version: release.version)
        }
        @MainActor func relaunch(with update: PreparedUpdate, replacing appURL: URL) throws { relaunched = true }
    }

    @MainActor
    static func controller() async throws {
        let release = try ReleaseFeed.newest(from: Data("[\(releaseJSON("v0.6.0"))]".utf8))!
        let app = URL(fileURLWithPath: "/Applications/Float.app")
        func defaults() -> UserDefaults {
            let name = "float-update-tests-\(UUID().uuidString)"
            let d = UserDefaults(suiteName: name)!
            d.removePersistentDomain(forName: name)
            return d
        }

        let newer = UpdateController(installedVersion: v("0.5.4"), appURL: app,
                                     fetcher: FakeFetcher(result: .success(release)),
                                     installer: FakeInstaller(), defaults: defaults())
        await newer.checkForUpdates()
        expect(newer.availableRelease?.version == v("0.6.0"), "offers newer release")

        let same = UpdateController(installedVersion: v("0.6.0"), appURL: app,
                                    fetcher: FakeFetcher(result: .success(release)),
                                    installer: FakeInstaller(), defaults: defaults())
        await same.checkForUpdates()
        expect(same.state == .upToDate, "same version is up to date")

        let shared = defaults()
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let quiet = UpdateController(installedVersion: v("0.5.4"), appURL: app,
                                     fetcher: FakeFetcher(result: .failure(.rateLimited)),
                                     installer: FakeInstaller(), defaults: shared, now: { clock })
        await quiet.checkAutomatically()
        expect(quiet.state == .idle, "automatic check hides errors")
        let throttled = UpdateController(installedVersion: v("0.5.4"), appURL: app,
                                         fetcher: FakeFetcher(result: .success(release)),
                                         installer: FakeInstaller(), defaults: shared, now: { clock })
        await throttled.checkAutomatically()
        expect(throttled.state == .idle, "automatic check waits for the interval")
        clock += UpdateController.automaticCheckInterval + 1
        await throttled.checkAutomatically()
        expect(throttled.availableRelease != nil, "automatic check runs after the interval")

        await quiet.checkForUpdates()
        if case .failed = quiet.state {} else { expect(false, "manual check reports errors") }

        let dev = UpdateController(installedVersion: nil, appURL: app,
                                   fetcher: FakeFetcher(result: .success(release)),
                                   installer: FakeInstaller(), defaults: defaults())
        expect(!dev.canInstall, "unreleased build cannot install")
        await dev.checkAutomatically()
        expect(dev.state == .idle, "unreleased build does not check automatically")

        let installer = FakeInstaller()
        let installing = UpdateController(installedVersion: v("0.5.4"), appURL: app,
                                          fetcher: FakeFetcher(result: .success(release)),
                                          installer: installer, defaults: defaults())
        await installing.checkForUpdates()
        await installing.installUpdate()
        expect(installer.relaunched, "installs and relaunches")
        if case .failed = installing.state {} else { expect(false, "a cancelled quit is reported") }
    }
}
