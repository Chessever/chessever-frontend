import AVFoundation
import AVKit
import Flutter
import UIKit

final class ChessPipController: NSObject {
  static let shared = ChessPipController()

  private var channel: FlutterMethodChannel?
  private var payload: [String: Any]?
  private var displayLayer: AVSampleBufferDisplayLayer?
  private var pipController: AVPictureInPictureController?
  private var timebase: CMTimebase?
  private var frameIndex: Int64 = 0

  private override init() {
    super.init()
  }

  func configure(binaryMessenger: FlutterBinaryMessenger) {
    let methodChannel = FlutterMethodChannel(
      name: "com.chessever/pip",
      binaryMessenger: binaryMessenger
    )
    channel = methodChannel
    methodChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(false)
        return
      }
      switch call.method {
      case "setActiveGame", "updatePosition":
        guard
          let args = call.arguments as? [String: Any],
          args["eligible"] as? Bool == true
        else {
          self.clear()
          result(nil)
          return
        }
        self.payload = args
        self.prepareIfNeeded()
        self.enqueueFrame()
        result(nil)
      case "enterIfEligible":
        result(self.enterIfEligible())
      case "clearActiveGame":
        self.clear()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func prepareIfNeeded() {
    guard #available(iOS 15.0, *) else { return }
    guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
    if pipController != nil { return }

    let layer = AVSampleBufferDisplayLayer()
    layer.videoGravity = .resizeAspect
    layer.backgroundColor = UIColor.black.cgColor

    var tb: CMTimebase?
    CMTimebaseCreateWithSourceClock(
      allocator: kCFAllocatorDefault,
      sourceClock: CMClockGetHostTimeClock(),
      timebaseOut: &tb
    )
    if let tb {
      CMTimebaseSetRate(tb, rate: 1.0)
      layer.controlTimebase = tb
      timebase = tb
    }

    let source = AVPictureInPictureController.ContentSource(
      sampleBufferDisplayLayer: layer,
      playbackDelegate: self
    )
    let controller = AVPictureInPictureController(contentSource: source)
    controller.delegate = self
    controller.canStartPictureInPictureAutomaticallyFromInline = true

    displayLayer = layer
    pipController = controller
  }

  private func enterIfEligible() -> Bool {
    guard payload?["eligible"] as? Bool == true else { return false }
    configureAudioSession()
    prepareIfNeeded()
    enqueueFrame()
    guard let pipController else { return false }
    if pipController.isPictureInPictureActive { return true }
    guard pipController.isPictureInPicturePossible else { return false }
    pipController.startPictureInPicture()
    return true
  }

  private func clear() {
    payload = nil
    if pipController?.isPictureInPictureActive == true {
      pipController?.stopPictureInPicture()
    }
  }

  private func configureAudioSession() {
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
      try session.setActive(true)
    } catch {
      print("[PiP] Failed to configure audio session: \(error)")
    }
  }

  private func enqueueFrame() {
    guard let displayLayer, let payload else { return }
    if displayLayer.status == .failed {
      displayLayer.flush()
    }
    guard let image = ChessPipRenderer.render(payload: payload, size: CGSize(width: 720, height: 720)) else {
      return
    }
    guard let sampleBuffer = makeSampleBuffer(image: image) else { return }
    displayLayer.enqueue(sampleBuffer)
  }

  private func makeSampleBuffer(image: CGImage) -> CMSampleBuffer? {
    let width = image.width
    let height = image.height
    var pixelBuffer: CVPixelBuffer?
    let attrs: [String: Any] = [
      kCVPixelBufferCGImageCompatibilityKey as String: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
    ]
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      kCVPixelFormatType_32BGRA,
      attrs as CFDictionary,
      &pixelBuffer
    )
    guard status == kCVReturnSuccess, let pixelBuffer else { return nil }

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

    guard
      let context = CGContext(
        data: CVPixelBufferGetBaseAddress(pixelBuffer),
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
      )
    else { return nil }

    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    var formatDescription: CMVideoFormatDescription?
    CMVideoFormatDescriptionCreateForImageBuffer(
      allocator: kCFAllocatorDefault,
      imageBuffer: pixelBuffer,
      formatDescriptionOut: &formatDescription
    )
    guard let formatDescription else { return nil }

    let pts = CMTime(value: frameIndex, timescale: 2)
    frameIndex += 1
    var timing = CMSampleTimingInfo(
      duration: CMTime(value: 1, timescale: 2),
      presentationTimeStamp: pts,
      decodeTimeStamp: .invalid
    )
    var sampleBuffer: CMSampleBuffer?
    CMSampleBufferCreateReadyWithImageBuffer(
      allocator: kCFAllocatorDefault,
      imageBuffer: pixelBuffer,
      formatDescription: formatDescription,
      sampleTiming: &timing,
      sampleBufferOut: &sampleBuffer
    )
    return sampleBuffer
  }
}

extension ChessPipController: AVPictureInPictureControllerDelegate {
  func pictureInPictureControllerDidStartPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    channel?.invokeMethod("onPipModeChanged", arguments: ["isInPip": true])
  }

  func pictureInPictureControllerDidStopPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    channel?.invokeMethod("onPipModeChanged", arguments: ["isInPip": false])
  }
}

@available(iOS 15.0, *)
extension ChessPipController: AVPictureInPictureSampleBufferPlaybackDelegate {
  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    setPlaying playing: Bool
  ) {}

  func pictureInPictureControllerTimeRangeForPlayback(
    _ pictureInPictureController: AVPictureInPictureController
  ) -> CMTimeRange {
    CMTimeRange(start: .zero, duration: .positiveInfinity)
  }

  func pictureInPictureControllerIsPlaybackPaused(
    _ pictureInPictureController: AVPictureInPictureController
  ) -> Bool {
    false
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    didTransitionToRenderSize newRenderSize: CMVideoDimensions
  ) {}

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    skipByInterval skipInterval: CMTime,
    completion completionHandler: @escaping () -> Void
  ) {
    completionHandler()
  }
}

private enum ChessPipRenderer {
  static func render(payload: [String: Any], size: CGSize) -> CGImage? {
    let renderer = UIGraphicsImageRenderer(size: size)
    let image = renderer.image { context in
      UIColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1).setFill()
      context.cgContext.fill(CGRect(origin: .zero, size: size))

      let side = min(size.width, size.height)
      let left = (size.width - side) / 2
      let top = (size.height - side) / 2
      let headerH = side * 0.07
      let footerH = side * 0.07
      let evalW = side * 0.05
      let boardSize = side - headerH - footerH - side * 0.04
      let boardRect = CGRect(x: left + evalW, y: top + headerH, width: boardSize, height: boardSize)

      drawPlayerRow(payload: payload, isWhite: false, rect: CGRect(x: boardRect.minX, y: top, width: boardRect.width, height: headerH))
      drawEvalBar(payload: payload, rect: CGRect(x: left + side * 0.01, y: boardRect.minY, width: evalW * 0.55, height: boardRect.height))
      drawBoard(payload: payload, rect: boardRect)
      drawPlayerRow(payload: payload, isWhite: true, rect: CGRect(x: boardRect.minX, y: boardRect.maxY, width: boardRect.width, height: footerH))
    }
    return image.cgImage
  }

  private static func drawPlayerRow(payload: [String: Any], isWhite: Bool, rect: CGRect) {
    let prefix = isWhite ? "white" : "black"
    let title = payload["\(prefix)Title"] as? String ?? ""
    let name = payload["\(prefix)Name"] as? String ?? ""
    let ratingValue = payload["\(prefix)Rating"] as? Int ?? 0
    let rating = ratingValue > 0 ? "\(ratingValue)" : ""
    let fed = (payload["\(prefix)Fed"] as? String ?? "").uppercased()
    let clock = payload["\(prefix)Clock"] as? String ?? ""
    let label = [title, name, rating].filter { !$0.isEmpty }.joined(separator: " ")

    if !fed.isEmpty {
      let flagRect = CGRect(x: rect.minX, y: rect.minY + rect.height * 0.22, width: rect.height * 0.7, height: rect.height * 0.56)
      UIColor(red: 0.13, green: 0.66, blue: 0.82, alpha: 1).setFill()
      UIBezierPath(roundedRect: flagRect, cornerRadius: 4).fill()
      drawText(fed.prefix(3).description, in: flagRect, size: rect.height * 0.22, color: .white, alignment: .center)
    }

    let clockW = clock.isEmpty ? 0 : rect.height * 1.9
    if !clock.isEmpty {
      let clockRect = CGRect(x: rect.maxX - clockW, y: rect.minY, width: clockW, height: rect.height)
      if !isWhite {
        UIColor(red: 0.13, green: 0.66, blue: 0.82, alpha: 1).setFill()
        UIRectFill(clockRect)
      }
      drawText(clock, in: clockRect, size: rect.height * 0.5, color: .white, alignment: .center)
    }

    let nameX = rect.minX + (fed.isEmpty ? 0 : rect.height * 0.86)
    let textRect = CGRect(
      x: nameX,
      y: rect.minY,
      width: rect.maxX - nameX - clockW - rect.height * 0.1,
      height: rect.height
    )
    drawText(label, in: textRect, size: rect.height * 0.48, color: .white, alignment: .left)
  }

  private static func drawBoard(payload: [String: Any], rect: CGRect) {
    let fen = payload["fen"] as? String ?? ""
    let board = parseFen(fen)
    let square = rect.width / 8
    let lastMove = payload["lastMoveUci"] as? String
    let highlights = parseUci(lastMove)

    for rank in 0..<8 {
      for file in 0..<8 {
        let squareRect = CGRect(
          x: rect.minX + CGFloat(file) * square,
          y: rect.minY + CGFloat(rank) * square,
          width: square,
          height: square
        )
        ((rank + file).isMultiple(of: 2)
          ? UIColor(red: 0.82, green: 0.82, blue: 0.82, alpha: 1)
          : UIColor(red: 0.58, green: 0.58, blue: 0.58, alpha: 1)
        ).setFill()
        UIRectFill(squareRect)
        let from = highlights.first
        let to = highlights.dropFirst().first
        if from?.0 == file && from?.1 == rank {
          UIColor(red: 1, green: 0.78, blue: 0.1, alpha: 0.45).setFill()
          UIRectFill(squareRect)
        } else if to?.0 == file && to?.1 == rank {
          UIColor(red: 0.28, green: 0.5, blue: 0.95, alpha: 0.42).setFill()
          UIRectFill(squareRect)
        }
        let piece = board[rank][file]
        if piece != "\0" {
          drawText(piece.uppercased(), in: squareRect.insetBy(dx: square * 0.08, dy: square * 0.08), size: square * 0.56, color: piece == piece.uppercased() ? .white : .black, alignment: .center)
        }
      }
    }
  }

  private static func drawEvalBar(payload: [String: Any], rect: CGRect) {
    UIColor.black.setFill()
    UIRectFill(rect)
    let evalCp = payload["evalCp"] as? Int
    let mate = payload["mate"] as? Int
    let eval = mate == nil || mate == 0 ? Double(evalCp ?? 0) / 100.0 : (mate! > 0 ? 10.0 : -10.0)
    let ratio = CGFloat((min(10.0, max(-10.0, eval)) + 10.0) / 20.0)
    let whiteRect = CGRect(x: rect.minX, y: rect.maxY - rect.height * ratio, width: rect.width, height: rect.height * ratio)
    UIColor.white.setFill()
    UIRectFill(whiteRect)

    let label = mate != nil && mate != 0 ? "M\(abs(mate!))" : String(format: "%+.1f", Double(evalCp ?? 0) / 100.0)
    let labelRect = CGRect(x: rect.minX - rect.width * 0.25, y: whiteRect.minY - rect.width * 0.68, width: rect.width * 1.5, height: rect.width * 1.36)
    UIColor(red: 0.13, green: 0.66, blue: 0.82, alpha: 1).setFill()
    UIRectFill(labelRect)
    drawText(label, in: labelRect, size: rect.width * 0.72, color: .white, alignment: .center)
  }

  private static func drawText(
    _ text: String,
    in rect: CGRect,
    size: CGFloat,
    color: UIColor,
    alignment: NSTextAlignment
  ) {
    guard rect.width > 0, rect.height > 0, !text.isEmpty else { return }
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byClipping
    let attributes: [NSAttributedString.Key: Any] = [
      .font: UIFont.boldSystemFont(ofSize: size),
      .foregroundColor: color,
      .paragraphStyle: paragraph,
    ]
    let string = NSString(string: text)
    string.draw(
      with: rect.insetBy(dx: 2, dy: max(0, (rect.height - size) / 2 - 2)),
      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
      attributes: attributes,
      context: nil
    )
  }

  private static func parseFen(_ fen: String) -> [[String]] {
    let ranks = fen.split(separator: " ").first?.split(separator: "/") ?? []
    guard ranks.count == 8 else { return defaultBoard() }
    var board = Array(repeating: Array(repeating: "\0", count: 8), count: 8)
    for (rankIndex, rank) in ranks.enumerated() {
      var file = 0
      for ch in rank {
        if let empty = ch.wholeNumberValue {
          file += empty
        } else if file < 8 {
          board[rankIndex][file] = String(ch)
          file += 1
        }
      }
    }
    return board
  }

  private static func defaultBoard() -> [[String]] {
    [
      ["r", "n", "b", "q", "k", "b", "n", "r"],
      ["p", "p", "p", "p", "p", "p", "p", "p"],
      Array(repeating: "\0", count: 8),
      Array(repeating: "\0", count: 8),
      Array(repeating: "\0", count: 8),
      Array(repeating: "\0", count: 8),
      ["P", "P", "P", "P", "P", "P", "P", "P"],
      ["R", "N", "B", "Q", "K", "B", "N", "R"],
    ]
  }

  private static func parseUci(_ uci: String?) -> [(Int, Int)] {
    guard let uci, uci.count >= 4 else { return [] }
    return [square(String(uci.prefix(2))), square(String(uci.dropFirst(2).prefix(2)))].compactMap { $0 }
  }

  private static func square(_ value: String) -> (Int, Int)? {
    guard value.count >= 2 else { return nil }
    let chars = Array(value.lowercased())
    guard let fileScalar = chars[0].unicodeScalars.first, let rank = chars[1].wholeNumberValue else {
      return nil
    }
    let aValue = "a".unicodeScalars.first?.value ?? 97
    let file = Int(fileScalar.value) - Int(aValue)
    guard (0...7).contains(file), (1...8).contains(rank) else { return nil }
    return (file, 8 - rank)
  }
}
