import ActivityKit
import SwiftUI
import WidgetKit
import OneSignalLiveActivities

// MARK: - Dictionary Helper Extensions

private extension Dictionary where Key == String, Value == AnyCodable {
  func asString(_ key: String) -> String? {
    return self[key]?.asString()
  }

  func asDouble(_ key: String) -> Double? {
    return self[key]?.asDouble()
  }

  func asInt(_ key: String) -> Int? {
    return self[key]?.asInt()
  }

  func asIntValue(_ key: String) -> Int? {
    if let intValue = self[key]?.asInt() {
      return intValue
    }
    if let doubleValue = self[key]?.asDouble() {
      return Int(doubleValue)
    }
    if let stringValue = self[key]?.asString(), let intValue = Int(stringValue) {
      return intValue
    }
    return nil
  }
}

// MARK: - Design System

private enum ChessDesign {
  // Colors - Dark elegant theme
  static let background = Color(red: 0.047, green: 0.047, blue: 0.055) // #0C0C0E
  static let surface = Color(red: 0.1, green: 0.1, blue: 0.12)
  static let surfaceLight = Color(red: 0.15, green: 0.15, blue: 0.18)
  static let accent = Color(red: 0.059, green: 0.706, blue: 0.898) // #0FB4E5
  static let accentBright = Color(red: 0.22, green: 0.78, blue: 0.94)
  static let white = Color.white
  static let textPrimary = Color.white
  static let textSecondary = Color(white: 0.55)
  static let highlightFrom = ChessDesign.accent.opacity(0.28)
  static let highlightTo = ChessDesign.accent.opacity(0.5)

  // Board colors - Classic wooden style
  static let lightSquare = Color(red: 0.94, green: 0.90, blue: 0.80) // Cream
  static let darkSquare = Color(red: 0.71, green: 0.53, blue: 0.39)  // Warm brown

  // Eval bar
  static let evalWhite = Color.white
  static let evalBlack = Color(red: 0.12, green: 0.12, blue: 0.14)

  // Piece colors with depth
  static let whitePiece = Color(red: 0.98, green: 0.98, blue: 0.96)
  static let blackPiece = Color(red: 0.08, green: 0.08, blue: 0.1)
}

// MARK: - Live Game State

private struct LiveGameState {
  let whiteName: String
  let blackName: String
  let lastMove: String
  let lastMoveUci: String?
  let fen: String
  let evalCp: Double?
  let evalMate: Int?
  let whitePhoto: String?
  let blackPhoto: String?
  let eventName: String?
  let roundName: String?
  let whiteClockSeconds: Int?
  let blackClockSeconds: Int?
  let lastMoveTime: Date?
  let isWhiteToMove: Bool
  let gameId: String?
  let widgetURL: URL?

  init(context: ActivityViewContext<DefaultLiveActivityAttributes>) {
    let data = context.state.data
    let attrData = context.attributes.data
    whiteName = data.asString("player_white") ?? "White"
    blackName = data.asString("player_black") ?? "Black"
    lastMove = data.asString("last_move_numbered") ??
      data.asString("last_move_san") ??
      data.asString("last_move") ??
      "..."
    lastMoveUci = data.asString("last_move_uci") ?? data.asString("last_move")
    fen = data.asString("fen") ?? "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    evalCp = data.asDouble("eval_cp")
    evalMate = data.asInt("eval_mate")
    whitePhoto = data.asString("white_photo")
    blackPhoto = data.asString("black_photo")
    eventName = LiveGameState.prettifyLabel(
      data.asString("event_name") ?? attrData.asString("event_name")
    )
    roundName = LiveGameState.prettifyLabel(
      data.asString("round_name") ?? attrData.asString("round_name")
    )
    whiteClockSeconds = data.asIntValue("white_clock_seconds")
    blackClockSeconds = data.asIntValue("black_clock_seconds")
    lastMoveTime = LiveGameState.parseDate(data.asString("last_move_time"))
    isWhiteToMove = LiveGameState.parseSideToMove(fen)
    gameId = data.asString("game_id") ?? attrData.asString("game_id")
    if let gameId, !gameId.isEmpty {
      widgetURL = URL(string: "https://chessever.com/games/\(gameId)")
    } else {
      widgetURL = nil
    }
  }

  var highlightSquares: [BoardSquare] {
    LiveGameState.parseUciSquares(lastMoveUci)
  }

  var evalText: String {
    if let mate = evalMate, mate != 0 {
      return mate > 0 ? "M\(mate)" : "M\(-mate)"
    }
    if let cp = evalCp {
      let eval = cp / 100.0
      let sign = eval >= 0 ? "+" : ""
      return "\(sign)\(String(format: "%.1f", eval))"
    }
    return "0.0"
  }

  var shortEval: String {
    if let mate = evalMate, mate != 0 {
      return mate > 0 ? "M\(mate)" : "M\(-mate)"
    }
    if let cp = evalCp {
      let eval = abs(cp / 100.0)
      return String(format: "%.1f", eval)
    }
    return "="
  }

  var isWhiteAdvantage: Bool {
    if let mate = evalMate { return mate > 0 }
    return (evalCp ?? 0) >= 0
  }

  var evalRatio: Double {
    let eval: Double
    if let mate = evalMate, mate != 0 {
      eval = mate > 0 ? 10.0 : -10.0
    } else {
      eval = (evalCp ?? 0.0) / 100.0
    }
    let clamped = max(-10.0, min(10.0, eval))
    return (clamped + 10.0) / 20.0
  }

  func clockState(isWhite: Bool) -> ClockState? {
    let seconds = isWhite ? whiteClockSeconds : blackClockSeconds
    guard let seconds else { return nil }
    let clampedSeconds = max(0, seconds)
    if isWhiteToMove == isWhite, let lastMoveTime {
      let endDate = lastMoveTime.addingTimeInterval(TimeInterval(clampedSeconds))
      return ClockState(seconds: clampedSeconds, endDate: endDate)
    }
    return ClockState(seconds: clampedSeconds, endDate: nil)
  }

  private static func parseSideToMove(_ fen: String) -> Bool {
    let parts = fen.split(separator: " ")
    guard parts.count > 1 else { return true }
    return parts[1] == "w"
  }

  private static func parseDate(_ value: String?) -> Date? {
    guard let value else { return nil }
    if let date = isoFormatterWithFraction.date(from: value) {
      return date
    }
    return isoFormatter.date(from: value)
  }

  private static let isoFormatterWithFraction: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  private static let isoFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()

  private static func prettifyLabel(_ value: String?) -> String? {
    guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return nil
    }
    let cleaned = value
      .replacingOccurrences(of: "-", with: " ")
      .replacingOccurrences(of: "_", with: " ")
      .replacingOccurrences(of: "/", with: " ")
    return cleaned
      .split(separator: " ")
      .map { word in
        let lower = word.lowercased()
        return lower.prefix(1).uppercased() + lower.dropFirst()
      }
      .joined(separator: " ")
  }

  private static func parseUciSquares(_ uci: String?) -> [BoardSquare] {
    guard let uci, uci.count >= 4 else { return [] }
    let chars = Array(uci)
    let from = String(chars[0...1])
    let to = String(chars[2...3])
    var squares: [BoardSquare] = []
    if let fromSquare = BoardSquare.fromAlgebraic(from) {
      squares.append(fromSquare)
    }
    if let toSquare = BoardSquare.fromAlgebraic(to) {
      squares.append(toSquare)
    }
    return squares
  }
}

private struct ClockState {
  let seconds: Int
  let endDate: Date?

  var isRunning: Bool {
    endDate != nil
  }
}

// MARK: - Widget Bundle

@main
struct ChessEverLiveActivityBundle: WidgetBundle {
  var body: some Widget {
    ChessEverLiveActivityWidget()
  }
}

// MARK: - Main Widget

struct ChessEverLiveActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: DefaultLiveActivityAttributes.self) { context in
      let state = LiveGameState(context: context)
      LockScreenView(state: state)
        .activityBackgroundTint(ChessDesign.background)
        .widgetURL(state.widgetURL)
    } dynamicIsland: { context in
      let state = LiveGameState(context: context)
      return DynamicIsland {
        // Expanded view - Beautiful full layout
        DynamicIslandExpandedRegion(.leading) {
          DynamicIslandAvatar(
            name: state.whiteName,
            photoUrl: state.whitePhoto,
            isWhite: true,
            isAdvantage: state.isWhiteAdvantage
          )
        }
        DynamicIslandExpandedRegion(.trailing) {
          DynamicIslandAvatar(
            name: state.blackName,
            photoUrl: state.blackPhoto,
            isWhite: false,
            isAdvantage: !state.isWhiteAdvantage
          )
        }
        DynamicIslandExpandedRegion(.center) {
          VStack(spacing: 4) {
            EvalBarHorizontal(evalCp: state.evalCp, evalMate: state.evalMate)
              .frame(width: 90, height: 8)

            Text(state.lastMove)
              .font(.system(size: 14, weight: .heavy, design: .monospaced))
              .foregroundStyle(ChessDesign.white)
              .lineLimit(1)
              .minimumScaleFactor(0.7)
          }
        }
      } compactLeading: {
        // Compact: White avatar
        CompactAvatar(
          name: state.whiteName,
          photoUrl: state.whitePhoto,
          isWhite: true
        )
      } compactTrailing: {
        // Compact: Black avatar
        CompactAvatar(
          name: state.blackName,
          photoUrl: state.blackPhoto,
          isWhite: false
        )
      } minimal: {
        // Minimal: Just the eval indicator
        MiniEvalCircle(ratio: state.evalRatio)
      }
      .widgetURL(state.widgetURL)
    }
  }

}

// MARK: - Lock Screen View (Premium Design)

private struct LockScreenView: View {
  let state: LiveGameState

  var body: some View {
    HStack(spacing: 0) {
      // Left: Eval bar with glow effect
      ZStack {
        EvalBarVertical(evalCp: state.evalCp, evalMate: state.evalMate)
          .frame(width: 12)

        // Glow indicator for advantage
        Circle()
          .fill(state.isWhiteAdvantage ? ChessDesign.white : ChessDesign.evalBlack)
          .frame(width: 8, height: 8)
          .shadow(color: state.isWhiteAdvantage ? .white.opacity(0.6) : .clear, radius: 4)
          .offset(y: state.isWhiteAdvantage ? 40 : -40)
      }
      .padding(.trailing, 14)

      // Center: Chess board with subtle shadow
      ZStack {
        // Shadow layer
        RoundedRectangle(cornerRadius: 10)
          .fill(Color.black.opacity(0.3))
          .blur(radius: 8)
          .offset(y: 4)

        MiniBoard(fen: state.fen, highlightSquares: state.highlightSquares)
          .clipShape(RoundedRectangle(cornerRadius: 10))
          .overlay(
            RoundedRectangle(cornerRadius: 10)
              .strokeBorder(
                LinearGradient(
                  colors: [ChessDesign.surfaceLight, ChessDesign.surface],
                  startPoint: .topLeading,
                  endPoint: .bottomTrailing
                ),
                lineWidth: 1
              )
          )
      }
      .frame(width: 110, height: 110)
      .padding(.trailing, 14)

      // Right: Game info
      VStack(alignment: .leading, spacing: 0) {
        // Event badge
        if let event = state.eventName ?? state.roundName {
          HStack(spacing: 4) {
            Circle()
              .fill(ChessDesign.accent)
              .frame(width: 6, height: 6)
            Text(event)
              .font(.system(size: 10, weight: .semibold))
              .foregroundStyle(ChessDesign.accent)
              .lineLimit(1)
          }
          .padding(.bottom, 8)
        }

        // Players section
        VStack(alignment: .leading, spacing: 6) {
          PlayerInfoRow(
            name: state.whiteName,
            photoUrl: state.whitePhoto,
            isWhite: true,
            isAdvantage: state.isWhiteAdvantage,
            clock: state.clockState(isWhite: true)
          )

          // VS divider
          HStack {
            Rectangle()
              .fill(ChessDesign.surface)
              .frame(height: 1)
            Text("vs")
              .font(.system(size: 9, weight: .medium))
              .foregroundStyle(ChessDesign.textSecondary)
            Rectangle()
              .fill(ChessDesign.surface)
              .frame(height: 1)
          }
          .frame(height: 12)

          PlayerInfoRow(
            name: state.blackName,
            photoUrl: state.blackPhoto,
            isWhite: false,
            isAdvantage: !state.isWhiteAdvantage,
            clock: state.clockState(isWhite: false)
          )
        }
        .padding(.bottom, 10)

        // Move + Eval display
        HStack(spacing: 10) {
          Text(state.lastMove)
            .font(.system(size: 20, weight: .black, design: .monospaced))
            .foregroundStyle(ChessDesign.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)

          // Eval badge
          HStack(spacing: 4) {
            Circle()
              .fill(state.isWhiteAdvantage ? ChessDesign.white : ChessDesign.evalBlack)
              .frame(width: 8, height: 8)
            Text(state.evalText)
              .font(.system(size: 13, weight: .bold, design: .monospaced))
              .foregroundStyle(ChessDesign.white)
          }
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(
            Capsule()
              .fill(ChessDesign.surface)
          )
        }
      }

      Spacer(minLength: 0)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
  }
}

// MARK: - Player Components

private struct PlayerInfoRow: View {
  let name: String
  let photoUrl: String?
  let isWhite: Bool
  let isAdvantage: Bool
  let clock: ClockState?

  var body: some View {
    HStack(spacing: 8) {
      PlayerAvatar(name: name, photoUrl: photoUrl, isWhite: isWhite, size: 22)
        .overlay(
          Circle()
            .strokeBorder(isAdvantage ? ChessDesign.accent : Color.clear, lineWidth: 2)
        )

      Text(name)
        .font(.system(size: 13, weight: isAdvantage ? .bold : .medium))
        .foregroundStyle(isAdvantage ? ChessDesign.white : ChessDesign.textSecondary)
        .lineLimit(1)

      Spacer(minLength: 6)

      LiveClockPill(clock: clock, isWhite: isWhite)
    }
  }
}

private struct DynamicIslandAvatar: View {
  let name: String
  let photoUrl: String?
  let isWhite: Bool
  let isAdvantage: Bool

  var body: some View {
    ZStack {
      PlayerAvatar(name: name, photoUrl: photoUrl, isWhite: isWhite, size: 36)
      if isAdvantage {
        Circle()
          .strokeBorder(ChessDesign.accent, lineWidth: 2)
          .frame(width: 40, height: 40)
      }
    }
  }
}

private struct PlayerAvatar: View {
  let name: String
  let photoUrl: String?
  let isWhite: Bool
  let size: CGFloat

  var body: some View {
    ZStack {
      // Background circle
      Circle()
        .fill(
          isWhite
            ? LinearGradient(colors: [.white, Color(white: 0.9)], startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [Color(white: 0.2), Color(white: 0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
        )

      if let urlString = photoUrl, let url = URL(string: urlString) {
        AsyncImage(url: url) { image in
          image.resizable().scaledToFill()
        } placeholder: {
          InitialsView(name: name, isWhite: isWhite, size: size)
        }
        .clipShape(Circle())
      } else {
        InitialsView(name: name, isWhite: isWhite, size: size)
      }
    }
    .frame(width: size, height: size)
  }
}

private struct LiveClockPill: View {
  let clock: ClockState?
  let isWhite: Bool
  var compact: Bool = false

  var body: some View {
    let fontSize: CGFloat = compact ? 9 : 11
    let verticalPadding: CGFloat = compact ? 2 : 4
    let horizontalPadding: CGFloat = compact ? 6 : 8

    return HStack(spacing: 4) {
      if let clock {
        if clock.isRunning, let endDate = clock.endDate {
          let safeEnd = endDate > Date() ? endDate : Date()
          Text(timerInterval: Date()...safeEnd, countsDown: true)
            .font(.system(size: fontSize, weight: .bold, design: .monospaced))
            .foregroundStyle(ChessDesign.white)
        } else {
          Text(formatSeconds(clock.seconds))
            .font(.system(size: fontSize, weight: .bold, design: .monospaced))
            .foregroundStyle(ChessDesign.white)
        }
      } else {
        Text("--:--")
          .font(.system(size: fontSize, weight: .medium, design: .monospaced))
          .foregroundStyle(ChessDesign.textSecondary)
      }
    }
    .padding(.vertical, verticalPadding)
    .padding(.horizontal, horizontalPadding)
    .background(
      Capsule()
        .fill(ChessDesign.surface)
    )
    .overlay(
      Capsule()
        .strokeBorder(
          isWhite ? ChessDesign.surfaceLight : ChessDesign.surface,
          lineWidth: 0.5
        )
    )
  }

  private func formatSeconds(_ seconds: Int) -> String {
    let clamped = max(0, seconds)
    let hours = clamped / 3600
    let minutes = (clamped % 3600) / 60
    let secs = clamped % 60
    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    return String(format: "%d:%02d", minutes, secs)
  }
}

private struct InitialsView: View {
  let name: String
  let isWhite: Bool
  let size: CGFloat

  var body: some View {
    Text(initials)
      .font(.system(size: size * 0.38, weight: .bold))
      .foregroundStyle(isWhite ? ChessDesign.blackPiece : ChessDesign.whitePiece)
  }

  private var initials: String {
    let parts = name.split(separator: " ")
    if let first = parts.first?.first {
      if parts.count > 1, let last = parts.last?.first {
        return "\(first)\(last)"
      }
      return String(first)
    }
    return "?"
  }
}

private struct CompactAvatar: View {
  let name: String
  let photoUrl: String?
  let isWhite: Bool

  var body: some View {
    PlayerAvatar(name: name, photoUrl: photoUrl, isWhite: isWhite, size: 22)
  }
}

// MARK: - Evaluation Components

private struct MiniEvalPill: View {
  let ratio: Double
  let isWhiteAdvantage: Bool

  var body: some View {
    ZStack {
      // Track
      Capsule()
        .fill(ChessDesign.surface)
        .frame(width: 20, height: 8)

      // Fill
      GeometryReader { geo in
        Capsule()
          .fill(isWhiteAdvantage ? ChessDesign.white : ChessDesign.evalBlack)
          .frame(width: max(4, geo.size.width * ratio), height: 6)
          .offset(x: isWhiteAdvantage ? 0 : geo.size.width * (1 - ratio))
      }
      .frame(width: 18, height: 6)
    }
    .frame(width: 20, height: 8)
  }
}

private struct MiniEvalCircle: View {
  let ratio: Double

  var body: some View {
    ZStack {
      Circle()
        .fill(ChessDesign.evalBlack)

      // White portion as arc
      Circle()
        .trim(from: 0, to: ratio)
        .stroke(ChessDesign.white, lineWidth: 4)
        .rotationEffect(.degrees(-90))
        .frame(width: 18, height: 18)
    }
    .frame(width: 24, height: 24)
  }
}

private struct EvalBarVertical: View {
  let evalCp: Double?
  let evalMate: Int?

  var body: some View {
    GeometryReader { proxy in
      let whiteRatio = evalRatio
      ZStack(alignment: .bottom) {
        // Black side (top)
        Rectangle()
          .fill(ChessDesign.evalBlack)

        // White side (bottom) with gradient
        Rectangle()
          .fill(
            LinearGradient(
              colors: [ChessDesign.white, Color(white: 0.9)],
              startPoint: .bottom,
              endPoint: .top
            )
          )
          .frame(height: proxy.size.height * whiteRatio)
      }
      .clipShape(RoundedRectangle(cornerRadius: 6))
      .overlay(
        RoundedRectangle(cornerRadius: 6)
          .strokeBorder(ChessDesign.surface, lineWidth: 0.5)
      )
    }
  }

  private var evalRatio: Double {
    let eval = effectiveEval
    let clamped = max(-10.0, min(10.0, eval))
    return (clamped + 10.0) / 20.0
  }

  private var effectiveEval: Double {
    if let mate = evalMate, mate != 0 {
      return mate > 0 ? 10.0 : -10.0
    }
    return (evalCp ?? 0.0) / 100.0
  }
}

private struct EvalBarHorizontal: View {
  let evalCp: Double?
  let evalMate: Int?

  var body: some View {
    GeometryReader { proxy in
      let ratio = evalRatio
      let radius = proxy.size.height / 2

      ZStack(alignment: .leading) {
        RoundedRectangle(cornerRadius: radius)
          .fill(ChessDesign.evalBlack)

        RoundedRectangle(cornerRadius: radius)
          .fill(
            LinearGradient(
              colors: [ChessDesign.white, Color(white: 0.92)],
              startPoint: .leading,
              endPoint: .trailing
            )
          )
          .frame(width: max(2, proxy.size.width * ratio))
      }
      .overlay(
        RoundedRectangle(cornerRadius: radius)
          .strokeBorder(ChessDesign.surface, lineWidth: 0.5)
      )
    }
  }

  private var evalRatio: Double {
    let eval = effectiveEval
    let clamped = max(-10.0, min(10.0, eval))
    return (clamped + 10.0) / 20.0
  }

  private var effectiveEval: Double {
    if let mate = evalMate, mate != 0 {
      return mate > 0 ? 10.0 : -10.0
    }
    return (evalCp ?? 0.0) / 100.0
  }
}

// MARK: - Mini Chess Board

private struct BoardSquare: Hashable {
  let file: Int
  let rank: Int

  static func fromAlgebraic(_ square: String) -> BoardSquare? {
    guard square.count >= 2 else { return nil }
    let chars = Array(square.lowercased())
    guard let fileChar = chars.first,
          let fileValue = fileChar.asciiValue else { return nil }
    let file = Int(fileValue - Character("a").asciiValue!)
    let rankValue = Int(String(chars[1])) ?? -1
    guard file >= 0, file < 8, rankValue >= 1, rankValue <= 8 else { return nil }
    let rank = 8 - rankValue
    return BoardSquare(file: file, rank: rank)
  }
}

private struct MiniBoard: View {
  let fen: String
  let highlightSquares: [BoardSquare]

  var body: some View {
    let board = FenBoard(fen: fen)
    let fromSquare = highlightSquares.first
    let toSquare = highlightSquares.count > 1 ? highlightSquares[1] : nil
    GeometryReader { proxy in
      Canvas { context, size in
        let sq = size.width / 8

        for rank in 0..<8 {
          for file in 0..<8 {
            let isLight = (rank + file) % 2 == 0
            let rect = CGRect(x: CGFloat(file) * sq, y: CGFloat(rank) * sq, width: sq, height: sq)

            // Draw square
            context.fill(
              Path(rect),
              with: .color(isLight ? ChessDesign.lightSquare : ChessDesign.darkSquare)
            )

            // Highlight last move squares
            let currentSquare = BoardSquare(file: file, rank: rank)
            if let fromSquare, currentSquare == fromSquare {
              context.fill(Path(rect), with: .color(ChessDesign.highlightFrom))
            } else if let toSquare, currentSquare == toSquare {
              context.fill(Path(rect), with: .color(ChessDesign.highlightTo))
            }

            // Draw piece
            if let piece = board.pieceAt(rank: rank, file: file) {
              let inset = sq * 0.12
              let pieceRect = rect.insetBy(dx: inset, dy: inset)
              let fillColor = piece.isWhite ? ChessDesign.whitePiece : ChessDesign.blackPiece
              let textColor = piece.isWhite ? ChessDesign.blackPiece : ChessDesign.whitePiece

              context.fill(Path(ellipseIn: pieceRect), with: .color(fillColor))
              context.stroke(
                Path(ellipseIn: pieceRect),
                with: .color(Color.black.opacity(piece.isWhite ? 0.2 : 0.6)),
                lineWidth: 1
              )

              let text = Text(piece.label)
                .font(.system(size: sq * 0.45, weight: .bold, design: .rounded))
                .foregroundColor(textColor)

              context.draw(
                context.resolve(text),
                at: CGPoint(x: rect.midX, y: rect.midY + 0.2),
                anchor: .center
              )
            }
          }
        }
      }
    }
    .aspectRatio(1, contentMode: .fit)
  }
}

// MARK: - FEN Parsing

private struct FenBoard {
  private var grid: [[FenPiece?]] = Array(
    repeating: Array(repeating: nil, count: 8),
    count: 8
  )

  init(fen: String) {
    let boardPart = fen.split(separator: " ").first ?? ""
    let ranks = boardPart.split(separator: "/")
    guard ranks.count == 8 else { return }

    for (rankIndex, rank) in ranks.enumerated() {
      var fileIndex = 0
      for char in rank {
        if let empty = char.wholeNumberValue {
          fileIndex += empty
        } else {
          if fileIndex < 8 {
            grid[rankIndex][fileIndex] = FenPiece(raw: char)
          }
          fileIndex += 1
        }
      }
    }
  }

  func pieceAt(rank: Int, file: Int) -> FenPiece? {
    guard rank >= 0 && rank < 8 && file >= 0 && file < 8 else { return nil }
    return grid[rank][file]
  }
}

private struct FenPiece {
  let raw: Character

  var isWhite: Bool {
    raw.isUppercase
  }

  var label: String {
    switch raw {
    case "K", "k": return "K"
    case "Q", "q": return "Q"
    case "R", "r": return "R"
    case "B", "b": return "B"
    case "N", "n": return "N"
    case "P", "p": return "P"
    default: return "?"
    }
  }
}
