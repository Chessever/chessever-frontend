import ActivityKit
import SwiftUI
import WidgetKit
import OneSignalLiveActivities
import UIKit

// MARK: - Dictionary Helper Extensions

private extension Dictionary where Key == String, Value == AnyCodable {
  func asNonEmptyString(_ key: String) -> String? {
    guard let value = self[key]?.asString() else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : value
  }

  func asString(_ key: String) -> String? {
    return self[key]?.asString()
  }

  func asDouble(_ key: String) -> Double? {
    return self[key]?.asDouble()
  }

  func asDoubleValue(_ key: String) -> Double? {
    if let doubleValue = self[key]?.asDouble() {
      return doubleValue
    }
    if let intValue = self[key]?.asInt() {
      return Double(intValue)
    }
    if let stringValue = self[key]?.asString(), let doubleValue = Double(stringValue) {
      return doubleValue
    }
    return nil
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

  // Check / game state
  static let checkRed = Color(red: 0.95, green: 0.25, blue: 0.2)
  static let timePressure = Color(red: 0.95, green: 0.35, blue: 0.2)
  static let timeCritical = Color(red: 1.0, green: 0.2, blue: 0.15)
}

// MARK: - Board Theme Palette

private struct BoardThemePalette {
  let lightSquare: Color
  let darkSquare: Color

  static func palette(for index: Int?) -> BoardThemePalette {
    let safeIndex = max(0, min((index ?? 0), palettes.count - 1))
    return palettes[safeIndex]
  }

  private static func color(hex: UInt32) -> Color {
    let r = Double((hex >> 16) & 0xff) / 255.0
    let g = Double((hex >> 8) & 0xff) / 255.0
    let b = Double(hex & 0xff) / 255.0
    return Color(red: r, green: g, blue: b)
  }

  // Must match kBoardThemes order in lib/utils/board_customization_utils.dart
  private static let palettes: [BoardThemePalette] = [
    BoardThemePalette(lightSquare: color(hex: 0xf0d9b6), darkSquare: color(hex: 0xb58863)), // Brown
    BoardThemePalette(lightSquare: color(hex: 0xdee3e6), darkSquare: color(hex: 0x8ca2ad)), // Blue
    BoardThemePalette(lightSquare: color(hex: 0xffffffdd), darkSquare: color(hex: 0x86a666)), // Green
    BoardThemePalette(lightSquare: color(hex: 0xececec), darkSquare: color(hex: 0xc1c18e)), // IC
    BoardThemePalette(lightSquare: color(hex: 0x97b2c7), darkSquare: color(hex: 0x546f82)), // Blue 2
    BoardThemePalette(lightSquare: color(hex: 0xd9e0e6), darkSquare: color(hex: 0x315991)), // Blue 3
    BoardThemePalette(lightSquare: color(hex: 0xeae6dd), darkSquare: color(hex: 0x7c7f87)), // Blue Marble
    BoardThemePalette(lightSquare: color(hex: 0xd7daeb), darkSquare: color(hex: 0x547388)), // Canvas
    BoardThemePalette(lightSquare: color(hex: 0xf2f9bb), darkSquare: color(hex: 0x59935d)), // Green Plastic
    BoardThemePalette(lightSquare: color(hex: 0xb8b8b8), darkSquare: color(hex: 0x7d7d7d)), // Grey
    BoardThemePalette(lightSquare: color(hex: 0xf0d9b5), darkSquare: color(hex: 0x946f51)), // Horsey
    BoardThemePalette(lightSquare: color(hex: 0xd1d1c9), darkSquare: color(hex: 0xc28e16)), // Leather
    BoardThemePalette(lightSquare: color(hex: 0xe8ceab), darkSquare: color(hex: 0xbc7944)), // Maple
    BoardThemePalette(lightSquare: color(hex: 0xe2c89f), darkSquare: color(hex: 0x996633)), // Maple 2
    BoardThemePalette(lightSquare: color(hex: 0x93ab91), darkSquare: color(hex: 0x4f644e)), // Marble
    BoardThemePalette(lightSquare: color(hex: 0xc9c9c9), darkSquare: color(hex: 0x727272)), // Metal
    BoardThemePalette(lightSquare: color(hex: 0xffffff), darkSquare: color(hex: 0x8d8d8d)), // Newspaper
    BoardThemePalette(lightSquare: color(hex: 0xb8b19f), darkSquare: color(hex: 0x6d6655)), // Olive
    BoardThemePalette(lightSquare: color(hex: 0xe8e9b7), darkSquare: color(hex: 0xed7272)), // Pink Pyramid
    BoardThemePalette(lightSquare: color(hex: 0x9f90b0), darkSquare: color(hex: 0x7d4a8d)), // Purple
    BoardThemePalette(lightSquare: color(hex: 0xe5daf0), darkSquare: color(hex: 0x957ab0)), // Purple Diag
    BoardThemePalette(lightSquare: color(hex: 0xd8a45b), darkSquare: color(hex: 0x9b4d0f)), // Wood
    BoardThemePalette(lightSquare: color(hex: 0xa38b5d), darkSquare: color(hex: 0x6c5017)), // Wood 2
    BoardThemePalette(lightSquare: color(hex: 0xd0ceca), darkSquare: color(hex: 0x755839)), // Wood 3
    BoardThemePalette(lightSquare: color(hex: 0xcaaf7d), darkSquare: color(hex: 0x7b5330)), // Wood 4
  ]
}

// MARK: - Live Game State

private struct LiveGameState {
  let whiteName: String
  let blackName: String
  let shortWhiteName: String
  let shortBlackName: String
  let whiteTitle: String?
  let blackTitle: String?
  let whiteFed: String?
  let blackFed: String?
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
  let isCheck: Bool
  let isCheckmate: Bool
  let isGameOver: Bool
  let gameStatus: String?
  let gameId: String?
  let widgetURL: URL?
  let boardThemeIndex: Int
  let boardTheme: BoardThemePalette
  let pieceStyleIndex: Int
  let pieceSetDirectory: String

  init(context: ActivityViewContext<DefaultLiveActivityAttributes>) {
    let data = context.state.data
    let attrData = context.attributes.data
    whiteName =
      data.asNonEmptyString("player_white") ??
      attrData.asNonEmptyString("player_white") ??
      "White"
    blackName =
      data.asNonEmptyString("player_black") ??
      attrData.asNonEmptyString("player_black") ??
      "Black"
    whiteTitle =
      data.asNonEmptyString("white_title") ??
      attrData.asNonEmptyString("white_title")
    blackTitle =
      data.asNonEmptyString("black_title") ??
      attrData.asNonEmptyString("black_title")
    whiteFed = LiveGameState.normalizeFed(
      data.asNonEmptyString("white_fed") ?? attrData.asNonEmptyString("white_fed")
    )
    blackFed = LiveGameState.normalizeFed(
      data.asNonEmptyString("black_fed") ?? attrData.asNonEmptyString("black_fed")
    )
    shortWhiteName = LiveGameState.shortDisplayName(whiteName)
    shortBlackName = LiveGameState.shortDisplayName(blackName)
    lastMove = data.asNonEmptyString("last_move_numbered") ??
      data.asNonEmptyString("last_move_san") ??
      data.asNonEmptyString("last_move") ??
      "—"
    lastMoveUci =
      data.asNonEmptyString("last_move_uci") ??
      data.asNonEmptyString("last_move")
    fen =
      data.asNonEmptyString("fen") ??
      attrData.asNonEmptyString("fen") ??
      "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    evalCp = data.asDoubleValue("eval_cp")
    evalMate = data.asIntValue("eval_mate")
    whitePhoto = data.asNonEmptyString("white_photo")
    blackPhoto = data.asNonEmptyString("black_photo")
    eventName = LiveGameState.prettifyLabel(
      data.asNonEmptyString("event_name") ?? attrData.asNonEmptyString("event_name")
    )
    roundName = LiveGameState.prettifyLabel(
      data.asNonEmptyString("round_name") ?? attrData.asNonEmptyString("round_name")
    )
    whiteClockSeconds = data.asIntValue("white_clock_seconds")
    blackClockSeconds = data.asIntValue("black_clock_seconds")
    lastMoveTime = LiveGameState.parseDate(data.asNonEmptyString("last_move_time"))
    boardThemeIndex =
      data.asIntValue("board_theme_index") ??
      attrData.asIntValue("board_theme_index") ??
      0
    boardTheme = BoardThemePalette.palette(for: boardThemeIndex)
    pieceStyleIndex =
      data.asIntValue("piece_style_index") ??
      attrData.asIntValue("piece_style_index") ??
      0
    pieceSetDirectory = PieceImageProvider.directory(for: pieceStyleIndex)
    isWhiteToMove = LiveGameState.parseSideToMove(fen)
    isCheck = (data.asInt("is_check") ?? 0) != 0
    isCheckmate = (data.asInt("is_checkmate") ?? 0) != 0
    isGameOver = (data.asInt("is_game_over") ?? 0) != 0
    gameStatus = data.asNonEmptyString("status")
    gameId = data.asNonEmptyString("game_id") ?? attrData.asNonEmptyString("game_id")
    if let gameId, !gameId.isEmpty {
      widgetURL = URL(string: "com.chessever.app://games/\(gameId)")
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
    return "—"
  }

  var hasEval: Bool {
    (evalCp != nil) || (evalMate != nil && evalMate != 0)
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

  private static func shortDisplayName(_ name: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.contains(",") {
      let parts = trimmed.split(separator: ",")
      if let last = parts.first {
        return String(last).trimmingCharacters(in: .whitespaces)
      }
    }
    let words = trimmed.split(separator: " ")
    if words.count > 1 {
      return String(words.last ?? words[0])
    }
    return trimmed
  }

  private static func normalizeFed(_ value: String?) -> String? {
    guard let value, !value.isEmpty else { return nil }
    return value.uppercased()
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
      SafeLockScreenView(state: state)
        .activityBackgroundTint(ChessDesign.background)
        .widgetURL(state.widgetURL)
    } dynamicIsland: { context in
      let state = LiveGameState(context: context)
      return DynamicIsland {
        // Expanded view - Beautiful full layout
        DynamicIslandExpandedRegion(.leading) {
          DynamicIslandPlayerBadge(
            name: state.shortWhiteName,
            title: state.whiteTitle,
            fed: state.whiteFed,
            photoUrl: state.whitePhoto,
            isWhite: true,
            isAdvantage: state.isWhiteAdvantage
          )
        }
        DynamicIslandExpandedRegion(.trailing) {
          DynamicIslandPlayerBadge(
            name: state.shortBlackName,
            title: state.blackTitle,
            fed: state.blackFed,
            photoUrl: state.blackPhoto,
            isWhite: false,
            isAdvantage: !state.isWhiteAdvantage
          )
        }
        DynamicIslandExpandedRegion(.center) {
          VStack(spacing: 4) {
            if state.isGameOver {
              Text(state.gameStatus ?? "Final")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(ChessDesign.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .allowsTightening(true)
            } else {
              HStack(spacing: 6) {
                EvalBarHorizontal(evalCp: state.evalCp, evalMate: state.evalMate)
                  .frame(width: 70, height: 8)
                Text(state.evalText)
                  .font(.system(size: 11, weight: .bold, design: .monospaced))
                  .foregroundStyle(ChessDesign.textSecondary)
              }

              Text(state.lastMove)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(state.isCheck ? ChessDesign.checkRed : ChessDesign.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .allowsTightening(true)
            }
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

// MARK: - Safe Lock Screen View (Crash Guard)

private struct SafeLockScreenView: View {
  let state: LiveGameState

  var body: some View {
    HStack(spacing: 12) {
      SafeMiniBoard(lightSquare: state.boardTheme.lightSquare, darkSquare: state.boardTheme.darkSquare)
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
          RoundedRectangle(cornerRadius: 8)
            .strokeBorder(ChessDesign.surfaceLight, lineWidth: 1)
        )

      VStack(alignment: .leading, spacing: 4) {
        Text("\(state.shortWhiteName) vs \(state.shortBlackName)")
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(ChessDesign.white)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
          .allowsTightening(true)

        Text(state.lastMove)
          .font(.system(size: 16, weight: .medium))
          .foregroundStyle(ChessDesign.white)
          .lineLimit(1)
          .minimumScaleFactor(0.6)
          .allowsTightening(true)

        if let event = state.eventName ?? state.roundName {
          Text(event)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(ChessDesign.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .allowsTightening(true)
        }
      }

      Spacer(minLength: 0)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
  }
}

private struct SafeMiniBoard: View {
  let lightSquare: Color
  let darkSquare: Color

  var body: some View {
    GeometryReader { proxy in
      let sq = proxy.size.width / 8
      VStack(spacing: 0) {
        ForEach(0..<8, id: \.self) { rank in
          HStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { file in
              let isLight = (rank + file) % 2 == 0
              Rectangle()
                .fill(isLight ? lightSquare : darkSquare)
                .frame(width: sq, height: sq)
            }
          }
        }
      }
    }
  }
}

// MARK: - Lock Screen View (Premium Design)

private struct LockScreenView: View {
  let state: LiveGameState

  var body: some View {
    HStack(spacing: 0) {
      // Left: Eval bar
      EvalBarVertical(evalCp: state.evalCp, evalMate: state.evalMate)
        .frame(width: 12)
        .padding(.trailing, 14)

      // Center: Chess board with subtle shadow
      ZStack {
        // Shadow layer
        RoundedRectangle(cornerRadius: 10)
          .fill(Color.black.opacity(0.3))
          .blur(radius: 8)
          .offset(y: 4)

        MiniBoard(
          fen: state.fen,
          highlightSquares: state.highlightSquares,
          isCheck: state.isCheck,
          lightSquare: state.boardTheme.lightSquare,
          darkSquare: state.boardTheme.darkSquare,
          pieceSetDirectory: state.pieceSetDirectory
        )
          .clipShape(RoundedRectangle(cornerRadius: 10))
          .overlay(
            RoundedRectangle(cornerRadius: 10)
              .strokeBorder(
                state.isCheck
                  ? LinearGradient(colors: [ChessDesign.checkRed.opacity(0.6), ChessDesign.checkRed.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                  : LinearGradient(colors: [ChessDesign.surfaceLight, ChessDesign.surface], startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: state.isCheck ? 1.5 : 1
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
              .minimumScaleFactor(0.7)
              .allowsTightening(true)
          }
          .padding(.bottom, 8)
        }

        // Players section
        VStack(alignment: .leading, spacing: 6) {
          PlayerInfoRow(
            name: state.blackName,
            photoUrl: state.blackPhoto,
            isWhite: false,
            isAdvantage: !state.isWhiteAdvantage,
            clock: state.clockState(isWhite: false),
            title: state.blackTitle,
            fed: state.blackFed,
            isActiveTurn: !state.isWhiteToMove && !state.isGameOver
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
            name: state.whiteName,
            photoUrl: state.whitePhoto,
            isWhite: true,
            isAdvantage: state.isWhiteAdvantage,
            clock: state.clockState(isWhite: true),
            title: state.whiteTitle,
            fed: state.whiteFed,
            isActiveTurn: state.isWhiteToMove && !state.isGameOver
          )
        }
        .padding(.bottom, 10)

        // Move + Eval display
        if state.isGameOver {
          // Game over: show result prominently
          VStack(alignment: .leading, spacing: 4) {
            Text(state.gameStatus ?? "Final")
              .font(.system(size: 18, weight: .bold))
              .foregroundStyle(ChessDesign.white)
              .lineLimit(1)
              .minimumScaleFactor(0.6)
              .allowsTightening(true)

            Text(state.lastMove)
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(ChessDesign.textSecondary)
              .lineLimit(1)
              .minimumScaleFactor(0.6)
              .allowsTightening(true)
          }
        } else {
          HStack(spacing: 10) {
            Text(state.lastMove)
              .font(.system(size: 20, weight: .medium))
              .foregroundStyle(state.isCheck ? ChessDesign.checkRed : ChessDesign.white)
              .lineLimit(1)
              .minimumScaleFactor(0.6)
              .allowsTightening(true)

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
                .fill(state.isCheck ? ChessDesign.checkRed.opacity(0.2) : ChessDesign.surface)
            )
          }
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
  let title: String?
  let fed: String?
  var isActiveTurn: Bool = false

  var body: some View {
    HStack(spacing: 8) {
      PlayerAvatar(name: name, photoUrl: photoUrl, isWhite: isWhite, size: 22)
        .overlay(
          Circle()
            .strokeBorder(isAdvantage ? ChessDesign.accent : Color.clear, lineWidth: 2)
        )

      VStack(alignment: .leading, spacing: 2) {
        Text(name)
          .font(.system(size: 13, weight: isAdvantage ? .bold : .medium))
          .foregroundStyle(isAdvantage ? ChessDesign.white : ChessDesign.textSecondary)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
          .allowsTightening(true)

        if !metaText.isEmpty {
          Text(metaText)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(ChessDesign.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .allowsTightening(true)
        }
      }

      Spacer(minLength: 6)

      LiveClockPill(clock: clock, isWhite: isWhite, isActiveTurn: isActiveTurn)
    }
  }

  private var metaText: String {
    [title, fed]
      .compactMap { $0 }
      .filter { !$0.isEmpty }
      .joined(separator: " • ")
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

private struct DynamicIslandPlayerBadge: View {
  let name: String
  let title: String?
  let fed: String?
  let photoUrl: String?
  let isWhite: Bool
  let isAdvantage: Bool

  var body: some View {
    VStack(spacing: 3) {
      DynamicIslandAvatar(
        name: name,
        photoUrl: photoUrl,
        isWhite: isWhite,
        isAdvantage: isAdvantage
      )

      Text(name)
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(ChessDesign.white)
        .lineLimit(1)
        .minimumScaleFactor(0.55)
        .allowsTightening(true)

      if !metaText.isEmpty {
        Text(metaText)
          .font(.system(size: 7, weight: .medium))
          .foregroundStyle(ChessDesign.textSecondary)
          .lineLimit(1)
          .minimumScaleFactor(0.6)
          .allowsTightening(true)
      }
    }
    .frame(maxWidth: 72)
  }

  private var metaText: String {
    [title, fed]
      .compactMap { $0 }
      .filter { !$0.isEmpty }
      .joined(separator: " • ")
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

      // Avoid network image loading inside the Live Activity extension.
      // Remote fetches here are a common cause of black cards (extension killed/crashed).
      InitialsView(name: name, isWhite: isWhite, size: size)
    }
    .frame(width: size, height: size)
  }
}

private struct LiveClockPill: View {
  let clock: ClockState?
  let isWhite: Bool
  var compact: Bool = false
  var isActiveTurn: Bool = false

  var body: some View {
    let fontSize: CGFloat = compact ? 9 : 11
    let verticalPadding: CGFloat = compact ? 2 : 4
    let horizontalPadding: CGFloat = compact ? 5 : 6

    return Group {
      if let clock {
        // Always use static text — Text(timerInterval:) crashes the widget extension.
        let displaySeconds = remainingSeconds(clock)
        let textColor = clockTextColor(seconds: displaySeconds)
        Text(formatSeconds(displaySeconds))
          .font(.system(size: fontSize, weight: .bold, design: .monospaced))
          .monospacedDigit()
          .foregroundStyle(textColor)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
          .allowsTightening(true)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: true, vertical: false)
      } else {
        Text("--:--")
          .font(.system(size: fontSize, weight: .medium, design: .monospaced))
          .monospacedDigit()
          .foregroundStyle(ChessDesign.textSecondary)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
          .allowsTightening(true)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: true, vertical: false)
      }
    }
    .padding(.vertical, verticalPadding)
    .padding(.horizontal, horizontalPadding)
    .background(
      Capsule()
        .fill(pillBackground)
    )
    .overlay(
      Capsule()
        .strokeBorder(pillBorder, lineWidth: isActiveTurn ? 1 : 0.5)
    )
  }

  private var pillBackground: Color {
    if isActiveTurn {
      if let clock {
        let secs = remainingSeconds(clock)
        if secs < 30 { return ChessDesign.timeCritical.opacity(0.2) }
        if secs < 60 { return ChessDesign.timePressure.opacity(0.15) }
      }
      return ChessDesign.accent.opacity(0.12)
    }
    return ChessDesign.surface
  }

  private var pillBorder: Color {
    if isActiveTurn {
      if let clock {
        let secs = remainingSeconds(clock)
        if secs < 30 { return ChessDesign.timeCritical.opacity(0.6) }
        if secs < 60 { return ChessDesign.timePressure.opacity(0.4) }
      }
      return ChessDesign.accent.opacity(0.4)
    }
    return isWhite ? ChessDesign.surfaceLight : ChessDesign.surface
  }

  private func clockTextColor(seconds: Int) -> Color {
    if isActiveTurn && seconds < 30 {
      return ChessDesign.timeCritical
    }
    if isActiveTurn && seconds < 60 {
      return ChessDesign.timePressure
    }
    return ChessDesign.white
  }

  private func remainingSeconds(_ clock: ClockState) -> Int {
    if let endDate = clock.endDate {
      // `clock.seconds` is the snapshot value; endDate lets us compute remaining time
      // at render time without a ticking timer (safer for Live Activities).
      let remaining = Int(endDate.timeIntervalSinceNow.rounded(.down))
      return max(0, remaining)
    }
    return max(0, clock.seconds)
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
      .lineLimit(1)
      .minimumScaleFactor(0.6)
      .allowsTightening(true)
      .frame(width: size * 0.9, height: size * 0.9, alignment: .center)
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
          let fileValue = fileChar.asciiValue,
          let aValue = Character("a").asciiValue else { return nil }
    let file = Int(fileValue) - Int(aValue)
    let rankValue = Int(String(chars[1])) ?? -1
    guard file >= 0, file < 8, rankValue >= 1, rankValue <= 8 else { return nil }
    let rank = 8 - rankValue
    return BoardSquare(file: file, rank: rank)
  }
}

private struct MiniBoard: View {
  let fen: String
  let highlightSquares: [BoardSquare]
  var isCheck: Bool = false
  let lightSquare: Color
  let darkSquare: Color
  let pieceSetDirectory: String

  var body: some View {
    let board = FenBoard(fen: fen)
    let fromSquare = highlightSquares.first
    let toSquare = highlightSquares.count > 1 ? highlightSquares[1] : nil
    let kingSquare = isCheck ? board.findKingSquare(isWhiteToMove: MiniBoard.parseSide(fen)) : nil

    // Pure SwiftUI rendering (no Canvas) to avoid widget render-path crashes.
    return GeometryReader { proxy in
      let side = min(proxy.size.width, proxy.size.height)
      let sq = side / 8.0

      VStack(spacing: 0) {
        ForEach(0..<8, id: \.self) { rank in
          HStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { file in
              let isLight = (rank + file) % 2 == 0
              let isFrom = (fromSquare?.file == file && fromSquare?.rank == rank)
              let isTo = (toSquare?.file == file && toSquare?.rank == rank)
              let isKingInCheck = (kingSquare?.file == file && kingSquare?.rank == rank)

              ZStack {
                Rectangle()
                  .fill(isLight ? lightSquare : darkSquare)

                if isKingInCheck {
                  // Radial red glow on the checked king's square
                  RadialGradient(
                    colors: [ChessDesign.checkRed.opacity(0.7), ChessDesign.checkRed.opacity(0.0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: sq * 0.7
                  )
                } else if isFrom {
                  Rectangle().fill(ChessDesign.highlightFrom)
                } else if isTo {
                  Rectangle().fill(ChessDesign.highlightTo)
                }

                if let piece = board.pieceAt(rank: rank, file: file) {
                  // Text fallback to prevent Watchdog termination from sync file I/O
                  Text(piece.displayLetter)
                    .font(.system(size: sq * 0.48, weight: .bold, design: .rounded))
                    .foregroundStyle(piece.isWhite ? ChessDesign.whitePiece : ChessDesign.blackPiece)
                }
              }
              .frame(width: sq, height: sq)
            }
          }
        }
      }
      .frame(width: side, height: side)
      .position(x: proxy.size.width / 2.0, y: proxy.size.height / 2.0)
    }
    .aspectRatio(1, contentMode: .fit)
  }

  private static func parseSide(_ fen: String) -> Bool {
    let parts = fen.split(separator: " ")
    return parts.count > 1 ? parts[1] == "w" : true
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

  /// Find the king square for the side to move (used for check highlighting)
  func findKingSquare(isWhiteToMove: Bool) -> BoardSquare? {
    let target: Character = isWhiteToMove ? "K" : "k"
    for rank in 0..<8 {
      for file in 0..<8 {
        if grid[rank][file]?.raw == target {
          return BoardSquare(file: file, rank: rank)
        }
      }
    }
    return nil
  }
}

private struct FenPiece {
  let raw: Character

  var isWhite: Bool {
    raw.isUppercase
  }

  var displayLetter: String {
    switch raw.lowercased() {
    case "k": return "K"
    case "q": return "Q"
    case "r": return "R"
    case "b": return "B"
    case "n": return "N"
    case "p": return "P"
    default: return "?"
    }
  }

  var assetName: String? {
    switch raw {
    case "K": return "wK"
    case "Q": return "wQ"
    case "R": return "wR"
    case "B": return "wB"
    case "N": return "wN"
    case "P": return "wP"
    case "k": return "bK"
    case "q": return "bQ"
    case "r": return "bR"
    case "b": return "bB"
    case "n": return "bN"
    case "p": return "bP"
    default: return nil
    }
  }
}

private enum PieceImageProvider {
  private static let cache: NSCache<NSString, UIImage> = {
    let cache = NSCache<NSString, UIImage>()
    cache.countLimit = 128
    return cache
  }()

  // Must match PieceSet.values order in chessground:
  // lib/src/piece_set.dart (kPieceSets in lib/utils/board_customization_utils.dart).
  private static let pieceSetDirectories: [String] = [
    "cburnett",
    "merida",
    "pirouetti",
    "chessnut",
    "chess7",
    "alpha",
    "reillycraig",
    "companion",
    "riohacha",
    "kosal",
    "leipzig",
    "fantasy",
    "spatial",
    "celtic",
    "california",
    "caliente",
    "pixel",
    "firi",
    "rhosgfx",
    "maestro",
    "fresca",
    "cardinal",
    "gioco",
    "tatiana",
    "staunty",
    "governor",
    "dubrovny",
    "icpieces",
    "mpchess",
    "monarchy",
    "cooke",
    "shapes",
    "kiwen-suwi",
    "horsey",
    "anarcandy",
    "xkcd",
    "letter",
    "disguised",
    "symmetric"
  ]

  static func directory(for index: Int) -> String {
    if index >= 0 && index < pieceSetDirectories.count {
      return pieceSetDirectories[index]
    }
    return pieceSetDirectories[0]
  }

  static func image(for piece: FenPiece, pieceSetDirectory: String) -> UIImage? {
    guard let name = piece.assetName else { return nil }
    let key = "\(pieceSetDirectory)/\(name)" as NSString
    if let cached = cache.object(forKey: key) { return cached }

    let primaryDir = "Pieces/\(pieceSetDirectory)"
    let fallbackDir = "Pieces/cburnett"
    guard let path =
      Bundle.main.path(forResource: name, ofType: "png", inDirectory: primaryDir) ??
      Bundle.main.path(forResource: name, ofType: "png", inDirectory: fallbackDir)
    else {
      return nil
    }
    guard let image = UIImage(contentsOfFile: path) else {
      return nil
    }
    cache.setObject(image, forKey: key)
    return image
  }
}
