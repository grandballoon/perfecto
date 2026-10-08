import UIKit

/// Draws a layer tree into a graphics context as shapes and text.
///
/// `CALayer.render(in:)` draws the bitmap each layer was last shown with, so
/// a PDF made with it has pictures of the text. This walks the tree itself
/// and has every layer that draws its own content draw it again, into the
/// context (`CALayer.draw(in:)`): SwiftUI's text and symbols come out as
/// glyphs and paths, and its fills and strokes, which are plain layers with
/// a colour, a corner radius or a border, as the shapes they are.
///
/// What a drawing cannot hold (shadows, filters, masks) is left out and
/// noted in `omissions`, and a layer that only has a bitmap is drawn as one
/// and counted in `bitmaps`.
@MainActor
struct LayerDrawing {
    enum Omission: String, Comparable, CaseIterable {
        case shadow, filter, mask, perspective

        static func < (a: Omission, b: Omission) -> Bool { a.rawValue < b.rawValue }
    }

    private(set) var omissions: Set<Omission> = []
    private(set) var bitmaps = 0

    /// Draws `layer` and everything in it, placed as it is in its superlayer.
    mutating func draw(_ layer: CALayer, in context: CGContext) {
        guard !layer.isHidden, layer.opacity > 0 else { return }
        noteOmissions(of: layer)

        context.saveGState()
        defer { context.restoreGState() }

        // Into the layer's own coordinates, the ones its bounds and its
        // sublayers are in.
        let bounds = layer.bounds
        context.translateBy(x: layer.position.x, y: layer.position.y)
        context.concatenate(layer.affineTransform())
        context.translateBy(x: -layer.anchorPoint.x * bounds.width - bounds.minX,
                            y: -layer.anchorPoint.y * bounds.height - bounds.minY)

        // A see-through layer fades as one piece, not part by part.
        let isSeeThrough = layer.opacity < 1
        if isSeeThrough {
            context.setAlpha(CGFloat(layer.opacity))
            context.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        defer { if isSeeThrough { context.endTransparencyLayer() } }

        let outline = Self.outline(of: layer)
        if layer.masksToBounds {
            context.addPath(outline)
            context.clip()
        }
        if let fill = layer.backgroundColor, fill.alpha > 0 {
            context.addPath(outline)
            context.setFillColor(fill)
            context.fillPath()
        }
        drawContents(of: layer, in: context)

        let sublayers = (layer.sublayers ?? []).enumerated().sorted {
            ($0.element.zPosition, $0.offset) < ($1.element.zPosition, $1.offset)
        }
        for (_, sublayer) in sublayers { draw(sublayer, in: context) }

        // The border lies over the sublayers, inside the layer's edge.
        if layer.borderWidth > 0, let stroke = layer.borderColor, stroke.alpha > 0 {
            context.addPath(Self.outline(of: layer, inset: layer.borderWidth / 2))
            context.setStrokeColor(stroke)
            context.setLineWidth(layer.borderWidth)
            context.strokePath()
        }
    }

    // MARK: – Contents

    private mutating func drawContents(of layer: CALayer, in context: CGContext) {
        if let shape = layer as? CAShapeLayer {
            draw(shape, in: context)
        } else if let contents = layer.contents, CFGetTypeID(contents as CFTypeRef) == CGImage.typeID {
            // The layer was handed a picture; there is nothing to draw again.
            // The context's y runs down and a picture's runs up.
            bitmaps += 1
            context.saveGState()
            context.translateBy(x: layer.bounds.minX, y: layer.bounds.maxY)
            context.scaleBy(x: 1, y: -1)
            context.draw(contents as! CGImage, in: CGRect(origin: .zero, size: layer.bounds.size))
            context.restoreGState()
        } else if layer.contents != nil || type(of: layer) != CALayer.self {
            // It drew what it shows (or, not shown yet, would): again, here.
            layer.draw(in: context)
        }
    }

    private func draw(_ shape: CAShapeLayer, in context: CGContext) {
        guard let path = shape.path else { return }
        if let fill = shape.fillColor, fill.alpha > 0 {
            context.addPath(path)
            context.setFillColor(fill)
            context.fillPath(using: shape.fillRule == .evenOdd ? .evenOdd : .winding)
        }
        if shape.lineWidth > 0, let stroke = shape.strokeColor, stroke.alpha > 0 {
            context.addPath(path)
            context.setStrokeColor(stroke)
            context.setLineWidth(shape.lineWidth)
            context.setLineCap(Self.caps[shape.lineCap] ?? .butt)
            context.setLineJoin(Self.joins[shape.lineJoin] ?? .miter)
            context.setMiterLimit(shape.miterLimit)
            if let dashes = shape.lineDashPattern {
                context.setLineDash(phase: shape.lineDashPhase, lengths: dashes.map { CGFloat(truncating: $0) })
            }
            context.strokePath()
        }
    }

    private static let caps: [CAShapeLayerLineCap: CGLineCap] = [.butt: .butt, .round: .round, .square: .square]
    private static let joins: [CAShapeLayerLineJoin: CGLineJoin] = [.miter: .miter, .round: .round, .bevel: .bevel]

    // MARK: – Shape

    /// The layer's edge, `inset` inside it, with its corners.
    private static func outline(of layer: CALayer, inset: CGFloat = 0) -> CGPath {
        let rect = layer.bounds.insetBy(dx: inset, dy: inset)
        guard rect.width > 0, rect.height > 0 else { return CGPath(rect: .zero, transform: nil) }
        let widest = min(rect.width, rect.height) / 2
        // The system's own controls round their corners another way and
        // report no radius at all; their thumbs and knobs are capsules.
        let radius = layer.cornerRadius.isFinite ? min(layer.cornerRadius - inset, widest) : widest
        guard radius > 0 else { return CGPath(rect: rect, transform: nil) }

        let corners = Self.corners(layer.maskedCorners)
        // A corner as wide as it can be is an arc whatever its curve, and
        // UIBezierPath's smoothed corner is not one.
        if corners == .allCorners, layer.cornerCurve == .circular || radius >= widest {
            return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        }
        return UIBezierPath(roundedRect: rect, byRoundingCorners: corners,
                            cornerRadii: CGSize(width: radius, height: radius)).cgPath
    }

    private static func corners(_ mask: CACornerMask) -> UIRectCorner {
        var corners: UIRectCorner = []
        if mask.contains(.layerMinXMinYCorner) { corners.insert(.topLeft) }
        if mask.contains(.layerMaxXMinYCorner) { corners.insert(.topRight) }
        if mask.contains(.layerMinXMaxYCorner) { corners.insert(.bottomLeft) }
        if mask.contains(.layerMaxXMaxYCorner) { corners.insert(.bottomRight) }
        return corners
    }

    // MARK: – Omissions

    private mutating func noteOmissions(of layer: CALayer) {
        if layer.shadowOpacity > 0, layer.shadowColor != nil { omissions.insert(.shadow) }
        if layer.mask != nil { omissions.insert(.mask) }
        if !(layer.filters ?? []).isEmpty || !(layer.backgroundFilters ?? []).isEmpty
            || layer.compositingFilter != nil {
            omissions.insert(.filter)
        }
        if !CATransform3DIsAffine(layer.transform) || !CATransform3DIsIdentity(layer.sublayerTransform) {
            omissions.insert(.perspective)
        }
    }
}
