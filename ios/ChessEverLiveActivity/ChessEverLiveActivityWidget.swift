import ActivityKit
import SwiftUI
import WidgetKit
import OneSignalLiveActivities

private struct LiveGameState {
  let whiteName: String
  let blackName: String
  let lastMove: String
  let fen: String
  let evalCp: Double?
  let evalMate: Int?
  let whitePhoto: String?
  let blackPhoto: String?

  init(context: ActivityViewContext<DefaultLiveActivityAttributes>) {
    let data = context.state.data
    whiteName = data.asString("player_white") ?? "White"
    blackName = data.asString("player_black") ?? "Black"
    lastMove = data.asString("last_move") ??
      data.asString("last_move_san") ??
      data.asString("last_move_numbered") ??
      "..."
    fen = data.asString("fen") ?? ""
    evalCp = data.asDouble("eval_cp")
    evalMate = data.asInt("eval_mate")
    whitePhoto = data.asString("white_photo")
    blackPhoto = data.asString("black_photo")
  }
}

@main
struct ChessEverLiveActivityBundle: WidgetBundle {
  var body: some Widget {
    ChessEverLiveActivityWidget()
  }
}

struct ChessEverLiveActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: DefaultLiveActivityAttributes.self) { context in
      let state = LiveGameState(context: context)
      LiveActivityLockScreen(state: state)
    } dynamicIsland: { context in
      let state = LiveGameState(context: context)
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          PlayerAvatarView(name: state.whiteName, photoUrl: state.whitePhoto)
        }
        DynamicIslandExpandedRegion(.trailing) {
          PlayerAvatarView(name: state.blackName, photoUrl: state.blackPhoto)
        }
        DynamicIslandExpandedRegion(.center) {
          VStack(spacing: 2) {
            Text("\(state.whiteName) vs \(state.blackName)")
              .font(.caption2)
              .lineLimit(1)
            Text(state.lastMove)
              .font(.caption)
              .fontWeight(.semibold)
          }
        }
        DynamicIslandExpandedRegion(.bottom) {
          EvalBarHorizontal(evalCp: state.evalCp, evalMate: state.evalMate)
        }
      } compactLeading: {
        PlayerAvatarView(name: state.whiteName, photoUrl: state.whitePhoto)
      } compactTrailing: {
        PlayerAvatarView(name: state.blackName, photoUrl: state.blackPhoto)
      } minimal: {
        Text(state.lastMove)
          .font(.caption2)
      }
    }
  }
}

private struct LiveActivityLockScreen: View {
  let state: LiveGameState

  var body: some View {
    HStack(spacing: 12) {
      EvalBarVertical(evalCp: state.evalCp, evalMate: state.evalMate)
        .frame(width: 8)

      ChessBoardView(fen: state.fen)
        .frame(width: 120, height: 120)

      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 6) {
          PlayerAvatarView(name: state.whiteName, photoUrl: state.whitePhoto)
          Text(state.whiteName)
            .font(.caption)
            .lineLimit(1)
        }
        HStack(spacing: 6) {
          PlayerAvatarView(name: state.blackName, photoUrl: state.blackPhoto)
          Text(state.blackName)
            .font(.caption)
            .lineLimit(1)
        }
        Text(state.lastMove)
          .font(.headline)
          .fontWeight(.semibold)
          .lineLimit(1)
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 8)
  }
}

private struct PlayerAvatarView: View {
  let name: String
  let photoUrl: String?

  var body: some View {
    ZStack {
      Circle()
        .fill(Color.white.opacity(0.2))
      if let urlString = photoUrl, let url = URL(string: urlString) {
        AsyncImage(url: url) { image in
          image.resizable().scaledToFill()
        } placeholder: {
          Text(initials)
            .font(.caption2)
            .foregroundStyle(.white)
        }
        .clipShape(Circle())
      } else {
        Text(initials)
          .font(.caption2)
          .foregroundStyle(.white)
      }
    }
    .frame(width: 24, height: 24)
  }

  private var initials: String {
    let comps = name.split(separator: " ")
    if let first = comps.first?.first {
      return String(first)
    }
    return "?"
  }
}

private struct EvalBarVertical: View {
  let evalCp: Double?
  let evalMate: Int?

  var body: some View {
    GeometryReader { proxy in
      let ratio = evalRatio
      VStack(spacing: 0) {
        Rectangle()
          .fill(Color.white)
          .frame(height: proxy.size.height * ratio)
        Rectangle()
          .fill(Color.black)
          .frame(height: proxy.size.height * (1 - ratio))
      }
      .clipShape(RoundedRectangle(cornerRadius: 4))
    }
  }

  private var evalRatio: Double {
    let eval = effectiveEval
    let clamped = max(-20.0, min(20.0, eval))
    return (clamped + 20.0) / 40.0
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
      ZStack(alignment: .leading) {
        RoundedRectangle(cornerRadius: 8)
          .fill(Color.black)
        RoundedRectangle(cornerRadius: 8)
          .fill(Color.white)
          .frame(width: proxy.size.width * ratio)
      }
    }
    .frame(height: 8)
  }

  private var evalRatio: Double {
    let eval = effectiveEval
    let clamped = max(-20.0, min(20.0, eval))
    return (clamped + 20.0) / 40.0
  }

  private var effectiveEval: Double {
    if let mate = evalMate, mate != 0 {
      return mate > 0 ? 10.0 : -10.0
    }
    return (evalCp ?? 0.0) / 100.0
  }
}

private struct ChessBoardView: View {
  let fen: String

  var body: some View {
    let board = FenBoard(fen: fen)
    VStack(spacing: 0) {
      ForEach(0..<8, id: \.self) { rank in
        HStack(spacing: 0) {
          ForEach(0..<8, id: \.self) { file in
            let isLight = (rank + file) % 2 == 0
            ZStack {
              Rectangle()
                .fill(isLight ? Color(white: 0.92) : Color(white: 0.2))
              if let piece = board.pieceAt(rank: rank, file: file) {
                Text(piece.unicode)
                  .font(.system(size: 14))
              }
            }
          }
        }
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 6))
  }
}

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

  var unicode: String {
    switch raw {
    case "K": return "♔"
    case "Q": return "♕"
    case "R": return "♖"
    case "B": return "♗"
    case "N": return "♘"
    case "P": return "♙"
    case "k": return "♚"
    case "q": return "♛"
    case "r": return "♜"
    case "b": return "♝"
    case "n": return "♞"
    case "p": return "♟︎"
    default: return ""
    }
  }
}
