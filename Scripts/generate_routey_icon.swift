#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let iconSize = 1024
let canvas = CGRect(x: 0, y: 0, width: iconSize, height: iconSize)
let outputPath = URL(fileURLWithPath: "app/Routey/Routey/Assets.xcassets/AppIcon.appiconset/RouteyAppIcon.png")

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
  CGColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func drawLinearGradient(
  in context: CGContext,
  rect: CGRect,
  colors: [CGColor],
  start: CGPoint,
  end: CGPoint
) {
  let colorSpace = CGColorSpaceCreateDeviceRGB()
  guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: nil) else {
    fatalError("Unable to create linear gradient")
  }
  context.drawLinearGradient(gradient, start: start, end: end, options: [])
}

func drawRadialGlow(in context: CGContext, center: CGPoint, radius: CGFloat, color: CGColor) {
  guard
    let transparent = color.copy(alpha: 0),
    let glow = color.copy(alpha: 0.30)
  else {
    fatalError("Unable to create radial glow colors")
  }
  let colorSpace = CGColorSpaceCreateDeviceRGB()
  guard let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [glow, transparent] as CFArray,
    locations: [0, 1]
  ) else {
    fatalError("Unable to create radial gradient")
  }
  context.drawRadialGradient(
    gradient,
    startCenter: center,
    startRadius: 0,
    endCenter: center,
    endRadius: radius,
    options: [.drawsAfterEndLocation]
  )
}

func drawCircle(in context: CGContext, center: CGPoint, radius: CGFloat, fill: CGColor, stroke: CGColor? = nil, strokeWidth: CGFloat = 0) {
  let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
  context.setFillColor(fill)
  context.fillEllipse(in: rect)

  if let stroke {
    context.setStrokeColor(stroke)
    context.setLineWidth(strokeWidth)
    context.strokeEllipse(in: rect.insetBy(dx: strokeWidth / 2, dy: strokeWidth / 2))
  }
}

func drawRouteLine(in context: CGContext) {
  let path = CGMutablePath()
  path.move(to: CGPoint(x: 264, y: 704))
  path.addCurve(to: CGPoint(x: 395, y: 585), control1: CGPoint(x: 285, y: 620), control2: CGPoint(x: 330, y: 582))
  path.addCurve(to: CGPoint(x: 542, y: 465), control1: CGPoint(x: 475, y: 588), control2: CGPoint(x: 500, y: 510))
  path.addCurve(to: CGPoint(x: 744, y: 326), control1: CGPoint(x: 605, y: 398), control2: CGPoint(x: 673, y: 382))

  context.setLineCap(.round)
  context.setLineJoin(.round)

  context.setStrokeColor(color(0, 0, 0, 0.18))
  context.setLineWidth(92)
  context.addPath(path)
  context.strokePath()

  context.setStrokeColor(color(228, 255, 246))
  context.setLineWidth(62)
  context.addPath(path)
  context.strokePath()

  context.setStrokeColor(color(61, 203, 148))
  context.setLineWidth(34)
  context.addPath(path)
  context.strokePath()
}

func drawPin(in context: CGContext, center: CGPoint, radius: CGFloat, fill: CGColor) {
  let shadowOffset = CGSize(width: 0, height: 12)
  context.saveGState()
  context.setShadow(offset: shadowOffset, blur: 22, color: color(0, 0, 0, 0.24))
  drawCircle(in: context, center: center, radius: radius, fill: fill)
  context.restoreGState()

  drawCircle(in: context, center: center, radius: radius, fill: fill, stroke: color(255, 255, 255, 0.74), strokeWidth: 16)
  drawCircle(in: context, center: center, radius: radius * 0.38, fill: color(255, 255, 255))
}

let colorSpace = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue | CGImageByteOrderInfo.order32Big.rawValue

guard let context = CGContext(
  data: nil,
  width: iconSize,
  height: iconSize,
  bitsPerComponent: 8,
  bytesPerRow: iconSize * 4,
  space: colorSpace,
  bitmapInfo: bitmapInfo
) else {
  fatalError("Unable to create drawing context")
}

context.interpolationQuality = .high
context.translateBy(x: 0, y: CGFloat(iconSize))
context.scaleBy(x: 1, y: -1)
context.setFillColor(color(12, 30, 42))
context.fill(canvas)

drawLinearGradient(
  in: context,
  rect: canvas,
  colors: [
    color(27, 117, 119),
    color(18, 49, 73),
    color(9, 25, 38)
  ],
  start: CGPoint(x: 160, y: 120),
  end: CGPoint(x: 900, y: 960)
)

drawRadialGlow(in: context, center: CGPoint(x: 410, y: 355), radius: 560, color: color(96, 226, 178))
drawRadialGlow(in: context, center: CGPoint(x: 790, y: 760), radius: 460, color: color(65, 144, 244))

drawRouteLine(in: context)
drawPin(in: context, center: CGPoint(x: 264, y: 704), radius: 70, fill: color(255, 190, 76))
drawPin(in: context, center: CGPoint(x: 542, y: 465), radius: 88, fill: color(60, 207, 147))
drawPin(in: context, center: CGPoint(x: 744, y: 326), radius: 70, fill: color(91, 176, 255))

let highlightPath = CGMutablePath()
highlightPath.addEllipse(in: CGRect(x: 168, y: 120, width: 688, height: 340))
context.saveGState()
context.addPath(highlightPath)
context.clip()
drawLinearGradient(
  in: context,
  rect: canvas,
  colors: [color(255, 255, 255, 0.20), color(255, 255, 255, 0)],
  start: CGPoint(x: 512, y: 120),
  end: CGPoint(x: 512, y: 480)
)
context.restoreGState()

guard let image = context.makeImage() else {
  fatalError("Unable to create image")
}

try FileManager.default.createDirectory(at: outputPath.deletingLastPathComponent(), withIntermediateDirectories: true)

guard let destination = CGImageDestinationCreateWithURL(outputPath as CFURL, UTType.png.identifier as CFString, 1, nil) else {
  fatalError("Unable to create image destination")
}

CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
  fatalError("Unable to write PNG")
}

print("Wrote \(outputPath.path)")
