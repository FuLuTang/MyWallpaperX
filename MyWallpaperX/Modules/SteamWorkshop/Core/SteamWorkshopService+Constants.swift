import Foundation

extension SteamWorkshopService {
    enum Constants {
        static let workshopAppID = "431960"
        static let steamCommunityBase = "https://steamcommunity.com/workshop/browse/"
        static let detailBase = "https://steamcommunity.com/sharedfiles/filedetails/"
        static let publishedFileDetailsAPI = "https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/"
        static let authorWorkshopPageSize = 30
        static let detailHydrationBatchSize = 4
        static let detailHydrationExpandedBatchSize = 6
        static let detailHydrationExpandedThreshold = 18
        static let detailHydrationNormalThreshold = 8
        static let detailHydrationInterBatchDelayNanoseconds: UInt64 = 1_300_000_000
        static let detailHydrationFastInterBatchDelayNanoseconds: UInt64 = 450_000_000
        static let detailHydrationNormalInterBatchDelayNanoseconds: UInt64 = 800_000_000
        static let detailPrefetchBatchSize = 2
        static let detailPrefetchInterBatchDelayNanoseconds: UInt64 = 2_000_000_000
        static let browserInteractionDeferralInterval: TimeInterval = 1.2
        static let detailRequestDeferralInterval: TimeInterval = 4.0
        static let browserDebugLoggingEnabledKey = "SteamWorkshop.browserDebugLoggingEnabled"
        static let bundledSteamBundleName = "SteamCMDRuntime.bundle"
        static let bundledSteamRootName = "Steam"
        static let bundledSteamMetadataName = "runtime-metadata.json"
        static let browserPageSize = 24
        static let cacheTTL: TimeInterval = 60 * 15
        static let detailCacheTTL: TimeInterval = 60 * 60 * 24
        static let defaultsLastUsername = "SteamWorkshop.lastUsername"
        static let defaultsLastAuthenticatedAt = "SteamWorkshop.lastAuthenticatedAt"
        static let authProbeCacheTTL: TimeInterval = 60 * 15
        static let authProbeTimeout: TimeInterval = 20
        static let requiredBundledItems = [
            "steamcmd.sh",
            "steamcmd",
            "steamclient.dylib",
            "libtier0_s.dylib",
            "libvstdlib_s.dylib",
            "crashhandler.dylib",
            "libaudio.dylib",
            "libsteaminput.dylib",
            "steamconsole.dylib",
            "update_hosts_cached.vdf",
            "package",
            "public",
            "Frameworks"
        ]
    }
}
