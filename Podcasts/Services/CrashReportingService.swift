import Foundation
import Sentry

enum CrashReportingService {

  static func start() {
    guard let dsn = configuredValue(for: "SENTRY_DSN") else {
      return
    }

    SentrySDK.start { options in
      options.dsn = dsn
      options.environment = configuredValue(for: "SENTRY_ENVIRONMENT") ?? defaultEnvironment

      #if DEBUG
      options.debug = true
      #endif
    }
  }

  private static func configuredValue(for key: String) -> String? {
    guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
      return nil
    }

    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else {
      return nil
    }

    return trimmed
  }

  private static var defaultEnvironment: String {
    #if DEBUG
    return "debug"
    #else
    return "production"
    #endif
  }
}
