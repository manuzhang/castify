import SwiftUI
import UIKit

struct EpisodeView: View {

  let episode: Episode
  let episodes: [Episode]
  let networkingService = NetworkingService()
  let podcastsService = PodcastsService()
  @ObservedObject var viewModel = EpisodeViewModel()
  @ObservedObject var player: Player
  @EnvironmentObject var localization: LocalizationService
  @State private var playbackState: EpisodePlaybackState?

  init(episode: Episode,
       episodes: [Episode] = [],
       player: Player = Container.player) {
    self.episode = episode
    self.episodes = episodes.isEmpty ? [episode] : episodes
    self.player = player
  }

  var body: some View {
    VStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          HStack(alignment: .top, spacing: 16) {
            RemoteImage(url: episode.imageURL())
              .frame(width: 112, height: 112)
              .background(Color(.tertiarySystemFill))
              .cornerRadius(8)
              .clipped()

            VStack(alignment: .leading, spacing: 8) {
              Text(episode.title)
                .font(.headline)
                .lineLimit(nil)
              Text(episode.author)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)
              Text(episode.pubDate.formatMedium)
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }

          Button(action: togglePlayback) {
            HStack {
              Image(systemName: isCurrentEpisodePlaying ? "pause.fill" : "play.fill")
              Text(playbackButtonTitle)
                .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .foregroundColor(.white)
            .background(Color.blue)
            .cornerRadius(8)
          }

          playbackStateSection

          downloadSection

          showNotesSection
        }
        .padding()
      }

      PlayerView()
    }
    .navigationBarTitle(Text(episode.title), displayMode: .inline)
    .onAppear {
      self.refreshPlaybackState()
    }
    .onReceive(player.$state) { _ in
      self.refreshPlaybackState()
    }
  }

  private var playbackStateSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        Image(systemName: playbackStatusIconName)
          .foregroundColor(playbackState?.played == true ? .green : .blue)
        Text(playbackStatusText)
          .foregroundColor(.secondary)
        Spacer()
      }

      HStack(spacing: 16) {
        Button(action: toggleStarredState) {
          HStack(spacing: 5) {
            Image(systemName: playbackState?.starred == true ? "star.fill" : "star")
            Text(localization.text(playbackState?.starred == true ? .unstarEpisode : .starEpisode))
          }
        }

        Button(action: togglePlayedState) {
          Text(localization.text(playbackState?.played == true ? .markAsUnplayed : .markAsPlayed))
        }
      }
    }
    .font(.subheadline)
  }

  private var downloadSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      if podcastsService.episodeDownloaded(episode) {
        HStack {
          Image(systemName: "checkmark.circle.fill")
          Text(localization.text(.downloaded))
        }
        .font(.subheadline)
        .foregroundColor(.secondary)
      } else {
        DownloadProgressView(progress: self.viewModel.progress)

        Button(
          action: {
            self.networkingService.downloadEpisode(self.episode) { progress in
              self.viewModel.progress = Float(progress.fractionCompleted)
            }
          },
          label: {
            HStack {
              Image(systemName: "arrow.down.circle")
              Text(localization.text(.download))
            }
          })
      }
    }
  }

  private var showNotesSection: some View {
    ShowNotesText(
      html: episode.description,
      fallbackText: episode.cleanDescription,
      onTimestampTapped: playFromTimestamp
    )
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var isCurrentEpisodePlaying: Bool {
    player.current == episode && player.isPlaying
  }

  private var playbackButtonTitle: String {
    if isCurrentEpisodePlaying {
      return localization.text(.pause)
    }

    if playbackState?.hasResumePosition == true {
      return localization.text(.resumeEpisode)
    }

    return localization.text(.playEpisode)
  }

  private var playbackStatusIconName: String {
    if playbackState?.played == true {
      return "checkmark.circle.fill"
    }

    if playbackState?.hasResumePosition == true {
      return "play.circle.fill"
    }

    return "circle"
  }

  private var playbackStatusText: String {
    if playbackState?.played == true {
      return localization.text(.played)
    }

    if let state = playbackState, state.hasResumePosition {
      return "\(localization.text(.resumeAt)) \(formatTimestamp(state.position))"
    }

    return localization.text(.unplayed)
  }

  private func togglePlayback() {
    if isCurrentEpisodePlaying {
      player.pause()
    } else {
      player.play(episode: episode, in: episodes)
    }
  }

  private func playFromTimestamp(_ time: TimeInterval) {
    player.play(episode: episode, in: episodes, at: time)
  }

  private func togglePlayedState() {
    if playbackState?.played == true {
      podcastsService.markEpisodeUnplayed(episode)
    } else {
      podcastsService.markEpisodePlayed(episode)
    }

    refreshPlaybackState()
  }

  private func toggleStarredState() {
    podcastsService.setEpisodeStarred(episode, starred: playbackState?.starred != true)
    refreshPlaybackState()
  }

  private func refreshPlaybackState() {
    playbackState = podcastsService.playbackState(for: episode)
  }

  private func formatTimestamp(_ time: TimeInterval) -> String {
    let totalSeconds = max(0, Int(time))
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }

    return String(format: "%d:%02d", minutes, seconds)
  }
}

private struct ShowNotesText: View {

  let html: String
  let fallbackText: String
  let onTimestampTapped: (TimeInterval) -> Void
  @State private var height: CGFloat = 1

  var body: some View {
    GeometryReader { geometry in
      ShowNotesTextView(
        html: html,
        fallbackText: fallbackText,
        onTimestampTapped: onTimestampTapped,
        width: geometry.size.width,
        height: $height
      )
    }
    .frame(height: max(height, 1))
  }
}

private struct ShowNotesTextView: UIViewRepresentable {

  private static let sectionURLScheme = "castify-section"
  private static let timestampURLScheme = "castify-timestamp"

  let html: String
  let fallbackText: String
  let onTimestampTapped: (TimeInterval) -> Void
  let width: CGFloat
  @Binding var height: CGFloat

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeUIView(context: Context) -> UITextView {
    let textView = UITextView()
    textView.backgroundColor = .clear
    textView.dataDetectorTypes = [.link]
    textView.delegate = context.coordinator
    textView.isEditable = false
    textView.isScrollEnabled = false
    textView.isSelectable = true
    textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
    textView.textContainer.lineBreakMode = .byCharWrapping
    textView.textContainer.lineFragmentPadding = 0
    textView.textContainerInset = .zero
    textView.textContainer.widthTracksTextView = true
    textView.adjustsFontForContentSizeCategory = true
    textView.linkTextAttributes = [
      .foregroundColor: UIColor.systemBlue,
      .underlineStyle: NSUnderlineStyle.single.rawValue
    ]

    return textView
  }

  func updateUIView(_ textView: UITextView, context: Context) {
    let content = Self.attributedShowNotes(html: html, fallbackText: fallbackText)

    textView.attributedText = content.attributedText
    context.coordinator.sectionTargets = content.sectionTargets
    context.coordinator.onTimestampTapped = onTimestampTapped
    textView.textContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)
    updateHeight(for: textView, width: width)
  }

  private func updateHeight(for textView: UITextView, width: CGFloat) {
    DispatchQueue.main.async {
      guard width > 0 else {
        return
      }

      let fittingSize = textView.sizeThatFits(
        CGSize(width: width, height: .greatestFiniteMagnitude)
      )
      let fittingHeight = ceil(fittingSize.height)

      if abs(height - fittingHeight) > 0.5 {
        height = fittingHeight
      }
    }
  }

  private static func attributedShowNotes(html: String, fallbackText: String) -> ShowNotesContent {
    let attributedText = parsedHTML(html) ?? NSMutableAttributedString(string: fallbackText)
    var sectionTargets = sectionTargets(in: html, renderedText: attributedText.string)

    style(attributedText)
    rewriteSectionLinks(in: attributedText, sectionTargets: &sectionTargets)
    linkPlainTextURLs(in: attributedText)
    linkTimestamps(in: attributedText)

    return ShowNotesContent(attributedText: attributedText, sectionTargets: sectionTargets)
  }

  private static func parsedHTML(_ html: String) -> NSMutableAttributedString? {
    guard let data = html.data(using: .utf8) else {
      return nil
    }

    let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
      .documentType: NSAttributedString.DocumentType.html,
      .characterEncoding: String.Encoding.utf8.rawValue
    ]

    guard let attributedText = try? NSMutableAttributedString(
      data: data,
      options: options,
      documentAttributes: nil
    ) else {
      return nil
    }

    return attributedText
  }

  private static func style(_ attributedText: NSMutableAttributedString) {
    let fullRange = NSRange(location: 0, length: attributedText.length)

    guard fullRange.length > 0 else {
      return
    }

    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineBreakMode = .byCharWrapping
    paragraphStyle.lineSpacing = 4
    paragraphStyle.paragraphSpacing = 8

    attributedText.addAttributes(
      [
        .font: UIFont.preferredFont(forTextStyle: .body),
        .foregroundColor: UIColor.label,
        .paragraphStyle: paragraphStyle
      ],
      range: fullRange
    )
  }

  private static func linkPlainTextURLs(in attributedText: NSMutableAttributedString) {
    guard let detector = try? NSDataDetector(
      types: NSTextCheckingResult.CheckingType.link.rawValue
    ) else {
      return
    }

    let text = attributedText.string
    let fullRange = NSRange(location: 0, length: (text as NSString).length)

    detector.enumerateMatches(in: text, range: fullRange) { result, _, _ in
      guard let result = result,
            let url = result.url,
            result.range.location < attributedText.length,
            attributedText.attribute(.link, at: result.range.location, effectiveRange: nil) == nil else {
        return
      }

      attributedText.addAttribute(.link, value: url, range: result.range)
    }
  }

  private static func linkTimestamps(in attributedText: NSMutableAttributedString) {
    let pattern = "(?<!\\d)(?:(\\d{1,2}):([0-5]\\d):([0-5]\\d)|(\\d{1,3}):([0-5]\\d))(?!\\d)"

    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return
    }

    let text = attributedText.string
    let nsText = text as NSString
    let fullRange = NSRange(location: 0, length: nsText.length)
    let matches = regex.matches(in: text, range: fullRange)

    for match in matches {
      guard attributedText.attribute(.link, at: match.range.location, effectiveRange: nil) == nil,
            let time = timestamp(from: match, in: nsText),
            let url = timestampURL(for: time) else {
        continue
      }

      attributedText.addAttribute(.link, value: url, range: match.range)
    }
  }

  private static func timestamp(from match: NSTextCheckingResult, in text: NSString) -> TimeInterval? {
    if match.range(at: 1).location != NSNotFound {
      guard let hours = TimeInterval(text.substring(with: match.range(at: 1))),
            let minutes = TimeInterval(text.substring(with: match.range(at: 2))),
            let seconds = TimeInterval(text.substring(with: match.range(at: 3))) else {
        return nil
      }

      return hours * 3600 + minutes * 60 + seconds
    }

    guard match.range(at: 4).location != NSNotFound,
          let minutes = TimeInterval(text.substring(with: match.range(at: 4))),
          let seconds = TimeInterval(text.substring(with: match.range(at: 5))) else {
      return nil
    }

    return minutes * 60 + seconds
  }

  private static func timestampURL(for time: TimeInterval) -> URL? {
    var components = URLComponents()
    components.scheme = timestampURLScheme
    components.host = "seek"
    components.queryItems = [URLQueryItem(name: "seconds", value: "\(Int(time))")]

    return components.url
  }

  private static func timestamp(fromTimestampURL url: URL) -> TimeInterval? {
    guard url.scheme == timestampURLScheme,
          let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
          let secondsValue = queryItems.first(where: { $0.name == "seconds" })?.value,
          let seconds = TimeInterval(secondsValue) else {
      return nil
    }

    return seconds
  }

  private static func rewriteSectionLinks(
    in attributedText: NSMutableAttributedString,
    sectionTargets: inout [String: NSRange]
  ) {
    let text = attributedText.string
    let fullRange = NSRange(location: 0, length: (text as NSString).length)
    var sectionLinks: [(range: NSRange, url: URL)] = []

    attributedText.enumerateAttribute(.link, in: fullRange, options: []) { value, range, _ in
      guard let value = value,
            let identifier = sectionIdentifier(fromLinkValue: value),
            let sectionURL = sectionURL(for: identifier) else {
        return
      }

      let linkText = (text as NSString).substring(with: range)
      let readableIdentifier = identifier.replacingOccurrences(
        of: "[-_]+",
        with: " ",
        options: .regularExpression,
        range: nil
      )

      if sectionTargets[identifier] == nil {
        sectionTargets[identifier] = rangeForSectionText(linkText, in: text, avoiding: range)
          ?? rangeForSectionText(readableIdentifier, in: text, avoiding: range)
      }

      sectionLinks.append((range: range, url: sectionURL))
    }

    for sectionLink in sectionLinks {
      attributedText.addAttribute(.link, value: sectionLink.url, range: sectionLink.range)
    }
  }

  private static func sectionTargets(in html: String, renderedText: String) -> [String: NSRange] {
    let pattern = "(?is)<([A-Za-z][A-Za-z0-9]*)\\b([^>]*)>(.*?)</\\s*\\1\\s*>"

    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return [:]
    }

    let nsHTML = html as NSString
    let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
    var targets: [String: NSRange] = [:]

    for match in matches {
      guard let rawIdentifier = anchorIdentifier(in: nsHTML.substring(with: match.range(at: 2))) else {
        continue
      }

      let identifier = normalizedSectionIdentifier(rawIdentifier)

      guard !identifier.isEmpty, targets[identifier] == nil else {
        continue
      }

      var targetText = candidateSectionText(from: nsHTML.substring(with: match.range(at: 3)))

      if targetText.isEmpty {
        let nextLocation = NSMaxRange(match.range)
        let remainingLength = max(0, nsHTML.length - nextLocation)
        let snippetLength = min(remainingLength, 1000)

        if snippetLength > 0 {
          targetText = candidateSectionText(
            from: nsHTML.substring(with: NSRange(location: nextLocation, length: snippetLength))
          )
        }
      }

      targets[identifier] = rangeForSectionText(targetText, in: renderedText, avoiding: nil)
    }

    return targets
  }

  private static func anchorIdentifier(in attributes: String) -> String? {
    let pattern = "(?i)\\b(?:id|name)\\s*=\\s*(?:\"([^\"]+)\"|'([^']+)'|([^\\s\"'>]+))"

    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return nil
    }

    let nsAttributes = attributes as NSString

    guard let match = regex.firstMatch(
      in: attributes,
      range: NSRange(location: 0, length: nsAttributes.length)
    ) else {
      return nil
    }

    for group in 1...3 {
      let range = match.range(at: group)

      if range.location != NSNotFound {
        return nsAttributes.substring(with: range)
      }
    }

    return nil
  }

  private static func candidateSectionText(from html: String) -> String {
    let cleanedText = html.strippingHTML

    for line in cleanedText.components(separatedBy: .newlines) {
      let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

      if !trimmedLine.isEmpty {
        return trimmedLine
      }
    }

    return cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func sectionIdentifier(fromLinkValue value: Any) -> String? {
    if let url = value as? URL {
      return sectionIdentifier(fromURL: url)
    }

    if let url = value as? NSURL {
      return sectionIdentifier(fromURL: url as URL)
    }

    if let string = value as? String {
      return sectionIdentifier(fromLinkString: string)
    }

    return nil
  }

  private static func sectionIdentifier(fromLinkString string: String) -> String? {
    let trimmedString = string.trimmingCharacters(in: .whitespacesAndNewlines)

    if trimmedString.hasPrefix("#") {
      return normalizedSectionIdentifier(String(trimmedString.dropFirst()))
    }

    guard let url = URL(string: trimmedString) else {
      return nil
    }

    return sectionIdentifier(fromURL: url)
  }

  private static func sectionIdentifier(fromURL url: URL) -> String? {
    if url.absoluteString.hasPrefix("#") {
      return normalizedSectionIdentifier(String(url.absoluteString.dropFirst()))
    }

    guard url.scheme == nil,
          url.host == nil,
          url.path.isEmpty,
          let fragment = url.fragment else {
      return nil
    }

    return normalizedSectionIdentifier(fragment)
  }

  private static func normalizedSectionIdentifier(_ identifier: String) -> String {
    let decodedIdentifier = identifier.removingPercentEncoding ?? identifier

    return decodedIdentifier
      .trimmingCharacters(in: CharacterSet(charactersIn: "# \n\t"))
      .lowercased()
  }

  private static func sectionURL(for identifier: String) -> URL? {
    var components = URLComponents()
    components.scheme = sectionURLScheme
    components.host = "target"
    components.queryItems = [URLQueryItem(name: "id", value: identifier)]

    return components.url
  }

  private static func sectionIdentifier(fromSectionURL url: URL) -> String? {
    guard url.scheme == sectionURLScheme,
          let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
          let identifier = queryItems.first(where: { $0.name == "id" })?.value else {
      return nil
    }

    return normalizedSectionIdentifier(identifier)
  }

  private static func rangeForSectionText(
    _ sectionText: String,
    in renderedText: String,
    avoiding avoidedRange: NSRange?
  ) -> NSRange? {
    let text = sectionText.trimmingCharacters(in: .whitespacesAndNewlines)

    guard text.count > 1 else {
      return nil
    }

    let nsText = renderedText as NSString
    var candidates: [NSRange] = []
    var searchRange = NSRange(location: 0, length: nsText.length)

    while searchRange.length > 0 {
      let foundRange = nsText.range(
        of: text,
        options: [.caseInsensitive, .diacriticInsensitive],
        range: searchRange
      )

      guard foundRange.location != NSNotFound else {
        break
      }

      candidates.append(foundRange)

      let nextLocation = NSMaxRange(foundRange)
      searchRange = NSRange(
        location: nextLocation,
        length: max(0, nsText.length - nextLocation)
      )
    }

    guard !candidates.isEmpty else {
      return nil
    }

    if let avoidedRange = avoidedRange {
      return candidates.first { !rangesOverlap($0, avoidedRange) && $0.location > avoidedRange.location }
        ?? candidates.first { !rangesOverlap($0, avoidedRange) }
    }

    return candidates.first
  }

  private static func rangesOverlap(_ lhs: NSRange, _ rhs: NSRange) -> Bool {
    lhs.location < NSMaxRange(rhs) && rhs.location < NSMaxRange(lhs)
  }

  private struct ShowNotesContent {

    let attributedText: NSAttributedString
    let sectionTargets: [String: NSRange]
  }

  final class Coordinator: NSObject, UITextViewDelegate {

    var sectionTargets: [String: NSRange] = [:]
    var onTimestampTapped: (TimeInterval) -> Void = { _ in }

    func textView(
      _ textView: UITextView,
      shouldInteractWith URL: URL,
      in characterRange: NSRange,
      interaction: UITextItemInteraction
    ) -> Bool {
      if let sectionIdentifier = ShowNotesTextView.sectionIdentifier(fromSectionURL: URL) {
        scrollToSection(sectionIdentifier, linkedRange: characterRange, in: textView)
        return false
      }

      if let timestamp = ShowNotesTextView.timestamp(fromTimestampURL: URL) {
        onTimestampTapped(timestamp)
        return false
      }

      UIApplication.shared.open(URL)
      return false
    }

    private func scrollToSection(
      _ identifier: String,
      linkedRange: NSRange,
      in textView: UITextView
    ) {
      let text = textView.attributedText.string
      let linkText = (text as NSString).substring(with: linkedRange)
      let readableIdentifier = identifier.replacingOccurrences(
        of: "[-_]+",
        with: " ",
        options: .regularExpression,
        range: nil
      )

      guard let targetRange = sectionTargets[identifier]
              ?? ShowNotesTextView.rangeForSectionText(linkText, in: text, avoiding: linkedRange)
              ?? ShowNotesTextView.rangeForSectionText(readableIdentifier, in: text, avoiding: linkedRange) else {
        return
      }

      scroll(targetRange, in: textView)
    }

    private func scroll(_ targetRange: NSRange, in textView: UITextView) {
      textView.layoutManager.ensureLayout(for: textView.textContainer)

      let glyphRange = textView.layoutManager.glyphRange(
        forCharacterRange: targetRange,
        actualCharacterRange: nil
      )
      var targetRect = textView.layoutManager.boundingRect(
        forGlyphRange: glyphRange,
        in: textView.textContainer
      )
      targetRect.origin.x += textView.textContainerInset.left
      targetRect.origin.y += textView.textContainerInset.top

      guard let scrollView = enclosingScrollView(containing: textView) else {
        textView.scrollRangeToVisible(targetRange)
        return
      }

      let convertedRect = textView.convert(targetRect, to: scrollView)
      let topPadding: CGFloat = 12
      let proposedOffsetY = scrollView.contentOffset.y
        + convertedRect.minY
        - scrollView.adjustedContentInset.top
        - topPadding
      let minOffsetY = -scrollView.adjustedContentInset.top
      let maxOffsetY = max(
        minOffsetY,
        scrollView.contentSize.height
          - scrollView.bounds.height
          + scrollView.adjustedContentInset.bottom
      )
      let targetOffsetY = min(max(proposedOffsetY, minOffsetY), maxOffsetY)

      scrollView.setContentOffset(
        CGPoint(x: scrollView.contentOffset.x, y: targetOffsetY),
        animated: true
      )
    }

    private func enclosingScrollView(containing view: UIView) -> UIScrollView? {
      var currentView = view.superview

      while let candidate = currentView {
        if let scrollView = candidate as? UIScrollView {
          return scrollView
        }

        currentView = candidate.superview
      }

      return nil
    }
  }
}
