import Combine
import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
  case english = "en"
  case chinese = "zh-Hans"

  var id: String {
    rawValue
  }

  var iTunesCountryCode: String {
    switch self {
    case .english:
      return "US"
    case .chinese:
      return "CN"
    }
  }

  var iTunesStorefrontPath: String {
    iTunesCountryCode.lowercased()
  }
}

enum AppText: String {
  case podcasts
  case browse
  case settings
  case noSavedPodcasts
  case searchForShows
  case search
  case cancel
  case top
  case arts
  case news
  case comedy
  case business
  case technology
  case sports
  case trueCrime
  case society
  case education
  case health
  case leisure
  case noPodcastsFound
  case unableToLoadPodcasts
  case unsubscribe
  case subscribe
  case subscribed
  case noEpisodesAvailable
  case invalidFeedURL
  case pause
  case play
  case playEpisode
  case resumeEpisode
  case resumeAt
  case played
  case unplayed
  case markAsPlayed
  case markAsUnplayed
  case downloaded
  case download
  case previousEpisode
  case back15Seconds
  case forward30Seconds
  case nextEpisode
  case upNext
  case playAll
  case episodes
  case library
  case language
  case importOPML
  case importing
  case downloads
  case autoDownloadEpisodes
  case autoDownloadWifiOnly
  case episodesPerPodcast
  case storage
  case downloadedEpisodes
  case storageUsed
  case clearDownloads
  case notifications
  case subscriptions
  case subscribedPodcasts
  case notificationsNeedPermission
  case notificationsBlocked
  case notificationPermissionUnknown
  case noPodcastFeedsFound
  case selectedFileEmpty
  case invalidOPMLFile
  case importedPodcast
  case podcastFeedUnavailable
  case untitledEpisode
}

final class LocalizationService: ObservableObject {

  static let shared = LocalizationService()

  @Published private(set) var language: AppLanguage

  private let userDefaults: UserDefaults
  private let translations: [AppLanguage: [AppText: String]] = [
    .english: [
      .podcasts: "Podcasts",
      .browse: "Browse",
      .settings: "Settings",
      .noSavedPodcasts: "No saved podcasts",
      .searchForShows: "Search for shows to build your library",
      .search: "Search",
      .cancel: "Cancel",
      .top: "Top",
      .arts: "Arts",
      .news: "News",
      .comedy: "Comedy",
      .business: "Business",
      .technology: "Technology",
      .sports: "Sports",
      .trueCrime: "True Crime",
      .society: "Society & Culture",
      .education: "Education",
      .health: "Health & Fitness",
      .leisure: "Leisure",
      .noPodcastsFound: "No podcasts found",
      .unableToLoadPodcasts: "Unable to load podcasts",
      .unsubscribe: "Unsubscribe",
      .subscribe: "Subscribe",
      .subscribed: "Subscribed",
      .noEpisodesAvailable: "No episodes available",
      .invalidFeedURL: "Invalid feed URL",
      .pause: "Pause",
      .play: "Play",
      .playEpisode: "Play Episode",
      .resumeEpisode: "Resume Episode",
      .resumeAt: "Resume",
      .played: "Played",
      .unplayed: "Unplayed",
      .markAsPlayed: "Mark as Played",
      .markAsUnplayed: "Mark as Unplayed",
      .downloaded: "Downloaded",
      .download: "Download",
      .previousEpisode: "Previous episode",
      .back15Seconds: "Back 15 seconds",
      .forward30Seconds: "Forward 30 seconds",
      .nextEpisode: "Next episode",
      .upNext: "Up Next",
      .playAll: "Play All",
      .episodes: "episodes",
      .library: "Library",
      .language: "Language",
      .importOPML: "Import OPML",
      .importing: "Importing...",
      .downloads: "Downloads",
      .autoDownloadEpisodes: "Auto-download episodes",
      .autoDownloadWifiOnly: "Only on Wi-Fi",
      .episodesPerPodcast: "Episodes per podcast",
      .storage: "Storage",
      .downloadedEpisodes: "Downloaded episodes",
      .storageUsed: "Storage used",
      .clearDownloads: "Clear downloads",
      .notifications: "Notifications",
      .subscriptions: "Subscriptions",
      .subscribedPodcasts: "Subscribed podcasts",
      .notificationsNeedPermission: "Notifications need permission from iOS",
      .notificationsBlocked: "Notifications are blocked by iOS",
      .notificationPermissionUnknown: "Notification permission status is unknown",
      .noPodcastFeedsFound: "No podcast feeds found",
      .selectedFileEmpty: "The selected file is empty",
      .invalidOPMLFile: "The selected file is not a valid OPML file",
      .importedPodcast: "Imported Podcast",
      .podcastFeedUnavailable: "This podcast feed is not available",
      .untitledEpisode: "Untitled Episode"
    ],
    .chinese: [
      .podcasts: "播客",
      .browse: "浏览",
      .settings: "设置",
      .noSavedPodcasts: "暂无保存的播客",
      .searchForShows: "搜索节目来建立你的播客库",
      .search: "搜索",
      .cancel: "取消",
      .top: "热门",
      .arts: "艺术",
      .news: "新闻",
      .comedy: "喜剧",
      .business: "商业",
      .technology: "科技",
      .sports: "体育",
      .trueCrime: "真实犯罪",
      .society: "社会与文化",
      .education: "教育",
      .health: "健康与健身",
      .leisure: "休闲",
      .noPodcastsFound: "未找到播客",
      .unableToLoadPodcasts: "无法加载播客",
      .unsubscribe: "取消订阅",
      .subscribe: "订阅",
      .subscribed: "已订阅",
      .noEpisodesAvailable: "暂无单集",
      .invalidFeedURL: "无效的订阅源地址",
      .pause: "暂停",
      .play: "播放",
      .playEpisode: "播放单集",
      .resumeEpisode: "继续播放",
      .resumeAt: "继续",
      .played: "已播放",
      .unplayed: "未播放",
      .markAsPlayed: "标记为已播放",
      .markAsUnplayed: "标记为未播放",
      .downloaded: "已下载",
      .download: "下载",
      .previousEpisode: "上一集",
      .back15Seconds: "后退 15 秒",
      .forward30Seconds: "前进 30 秒",
      .nextEpisode: "下一集",
      .upNext: "待播列表",
      .playAll: "全部播放",
      .episodes: "单集",
      .library: "资料库",
      .language: "语言",
      .importOPML: "导入 OPML",
      .importing: "正在导入...",
      .downloads: "下载",
      .autoDownloadEpisodes: "自动下载单集",
      .autoDownloadWifiOnly: "仅限 Wi-Fi",
      .episodesPerPodcast: "每个播客单集数",
      .storage: "存储",
      .downloadedEpisodes: "已下载单集",
      .storageUsed: "已用存储",
      .clearDownloads: "清除下载",
      .notifications: "通知",
      .subscriptions: "订阅",
      .subscribedPodcasts: "已订阅播客",
      .notificationsNeedPermission: "通知需要 iOS 授权",
      .notificationsBlocked: "通知已被 iOS 阻止",
      .notificationPermissionUnknown: "通知权限状态未知",
      .noPodcastFeedsFound: "未找到播客订阅源",
      .selectedFileEmpty: "所选文件为空",
      .invalidOPMLFile: "所选文件不是有效的 OPML 文件",
      .importedPodcast: "导入的播客",
      .podcastFeedUnavailable: "此播客订阅源不可用",
      .untitledEpisode: "未命名单集"
    ]
  ]

  init(userDefaults: UserDefaults = .standard) {
    self.userDefaults = userDefaults
    let savedLanguage = userDefaults.string(forKey: UserDefaults.appLanguageKey)
    self.language = savedLanguage.flatMap(AppLanguage.init(rawValue:)) ?? .english
  }

  var localeIdentifier: String {
    switch language {
    case .english:
      return "en"
    case .chinese:
      return "zh-Hans"
    }
  }

  func setLanguage(_ language: AppLanguage) {
    guard language != self.language else {
      return
    }

    self.language = language
    userDefaults.set(language.rawValue, forKey: UserDefaults.appLanguageKey)
  }

  func title(for language: AppLanguage) -> String {
    switch language {
    case .english:
      return "English"
    case .chinese:
      return "中文"
    }
  }

  func text(_ key: AppText) -> String {
    translations[language]?[key]
      ?? translations[.english]?[key]
      ?? key.rawValue
  }

  func episodeCount(_ count: Int) -> String {
    switch language {
    case .english:
      return count == 1 ? "1 episode" : "\(count) episodes"
    case .chinese:
      return "\(count) 集"
    }
  }

  func importMessage(addedCount: Int, totalCount: Int) -> String {
    if totalCount == 0 {
      return text(.noPodcastFeedsFound)
    }

    if addedCount == 0 {
      switch language {
      case .english:
        let suffix = totalCount == 1 ? "podcast was" : "podcasts were"
        return "All \(totalCount) \(suffix) already subscribed"
      case .chinese:
        return "\(totalCount) 个播客均已订阅"
      }
    }

    switch language {
    case .english:
      let noun = totalCount == 1 ? "podcast" : "podcasts"
      return "Imported \(addedCount) of \(totalCount) \(noun)"
    case .chinese:
      return "已导入 \(addedCount) / \(totalCount) 个播客"
    }
  }

  func podcastDuration(hours: Int, minutes: Int) -> String {
    switch language {
    case .english:
      if hours > 0 {
        return "\(hours)h \(minutes)m"
      }

      return "\(minutes)m"
    case .chinese:
      if hours > 0 {
        return "\(hours)小时 \(minutes)分钟"
      }

      return "\(minutes)分钟"
    }
  }
}
