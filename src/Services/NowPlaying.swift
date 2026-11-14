import AppKit
import Foundation

struct NowPlaying: Equatable {
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var duration: Double = 0
    var elapsed: Double = 0
    var playbackRate: Double = 0
    var capturedAt: Date = Date()
    var artwork: NSImage?
    var sourceName: String = ""

    var isPlaying: Bool { playbackRate > 0 }

    var liveElapsed: Double {
        guard duration > 0 else { return 0 }
        guard isPlaying else { return min(elapsed, duration) }
        return min(elapsed + Date().timeIntervalSince(capturedAt) * playbackRate, duration)
    }

    static func == (lhs: NowPlaying, rhs: NowPlaying) -> Bool {
        lhs.title == rhs.title
            && lhs.artist == rhs.artist
            && lhs.album == rhs.album
            && lhs.isPlaying == rhs.isPlaying
            && abs(lhs.duration - rhs.duration) < 0.5
            && lhs.artwork === rhs.artwork
    }
}

enum MediaCommand: Int {
    case play = 0
    case pause = 1
    case toggle = 2
    case stop = 3
    case next = 4
    case previous = 5
}

/// 通过 MediaRemote 私有框架读取系统「正在播放」，不需要任何自动化授权弹窗
final class NowPlayingService {
    static let shared = NowPlayingService()

    private typealias GetInfoFn = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    private typealias SendCommandFn = @convention(c) (Int, CFTypeRef?) -> Void

    private var getInfo: GetInfoFn?
    private var sendCommandFn: SendCommandFn?
    private var artworkCache: [String: NSImage] = [:]

    /// MediaRemote 私有框架是否可用（可用时无需任何自动化授权即可读播放信息）
    var isAvailable: Bool { getInfo != nil }

    private init() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        guard let handle = dlopen(path, RTLD_NOW) else { return }
        if let p = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") {
            getInfo = unsafeBitCast(p, to: GetInfoFn.self)
        }
        if let p = dlsym(handle, "MRMediaRemoteSendCommand") {
            sendCommandFn = unsafeBitCast(p, to: SendCommandFn.self)
        }
    }

    func fetch(completion: @escaping (NowPlaying?) -> Void) {
        guard let getInfo else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        getInfo(DispatchQueue.main) { [weak self] info in
            guard let self else { return }
            let title = (info["kMRMediaRemoteNowPlayingInfoTitle"] as? String) ?? ""
            guard !title.isEmpty else {
                completion(nil)
                return
            }

            let artist = (info["kMRMediaRemoteNowPlayingInfoArtist"] as? String) ?? ""
            let album = (info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String) ?? ""
            let duration = (info["kMRMediaRemoteNowPlayingInfoDuration"] as? NSNumber)?.doubleValue ?? 0
            let elapsed = (info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? NSNumber)?.doubleValue ?? 0
            let rate = (info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber)?.doubleValue ?? 0
            let timestamp = (info["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date) ?? Date()

            var image: NSImage?
            if let data = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data {
                let key = "\(title)|\(album)|\(data.count)"
                if let cached = self.artworkCache[key] {
                    image = cached
                } else if let decoded = NSImage(data: data) {
                    image = decoded
                    if self.artworkCache.count > 12 { self.artworkCache.removeAll() }
                    self.artworkCache[key] = decoded
                }
            }

            var np = NowPlaying()
            np.title = title
            np.artist = artist
            np.album = album
            np.duration = duration
            np.elapsed = elapsed
            np.playbackRate = rate
            np.capturedAt = timestamp
            np.artwork = image
            np.sourceName = (info["kMRMediaRemoteNowPlayingInfoClientBundleIdentifier"] as? String) ?? ""
            completion(np)
        }
    }

    func send(_ command: MediaCommand) {
        sendCommandFn?(command.rawValue, nil)
    }
}
