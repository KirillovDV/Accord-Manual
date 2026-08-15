import CoreGraphics
import UIKit

struct ViewerLayout {
    let safeBounds: CGRect
    let topBarFrame: CGRect
    let artworkViewport: CGRect
    let fitFrame: CGRect
    let bottomBarFrame: CGRect
}

enum DiagramGeometry {
    /// Converts a source-coordinate canvas to points at which one source raster
    /// pixel occupies one physical display pixel. The importer keeps VML/link
    /// coordinates in the source canvas, which can differ from the original
    /// image's pixel dimensions.
    static func nativeRasterScale(
        sourceCanvas: CGSize,
        rasterPixels: CGSize,
        displayScale: CGFloat
    ) -> CGSize {
        let safeDisplayScale = max(displayScale, 1)
        return CGSize(
            width: max(rasterPixels.width, 1) / max(sourceCanvas.width, 1) / safeDisplayScale,
            height: max(rasterPixels.height, 1) / max(sourceCanvas.height, 1) / safeDisplayScale
        )
    }

    /// Splits a viewer into one artwork viewport and one control strip before
    /// scaling the artwork. Keeping this calculation in a single coordinate
    /// system prevents `safeAreaInset` from clipping an image after it was
    /// fitted to a larger, obsolete viewport.
    static func viewerLayout(
        canvas: CGSize,
        container: CGRect,
        safeAreaInsets: UIEdgeInsets,
        topBarHeight: CGFloat = 0,
        bottomBarHeight: CGFloat
    ) -> ViewerLayout {
        let safeBounds = container.inset(by: safeAreaInsets)
        let topHeight = min(max(topBarHeight, 0), max(safeBounds.height, 0))
        let controlHeight = min(max(bottomBarHeight, 44), max(safeBounds.height - topHeight, 0))
        let topBarFrame = CGRect(
            x: safeBounds.minX,
            y: safeBounds.minY,
            width: safeBounds.width,
            height: topHeight
        )
        let bottomBarFrame = CGRect(
            x: safeBounds.minX,
            y: safeBounds.maxY - controlHeight,
            width: safeBounds.width,
            height: controlHeight
        )
        let artworkViewport = CGRect(
            x: safeBounds.minX,
            y: topBarFrame.maxY,
            width: safeBounds.width,
            height: max(bottomBarFrame.minY - topBarFrame.maxY, 0)
        )
        return ViewerLayout(
            safeBounds: safeBounds,
            topBarFrame: topBarFrame,
            artworkViewport: artworkViewport,
            fitFrame: aspectFit(canvas: canvas, in: artworkViewport),
            bottomBarFrame: bottomBarFrame
        )
    }

    /// Returns the unmodified source-coordinate rectangle for an image-map
    /// link. Unlike annotationFrames this must never resolve collisions or
    /// clamp the rectangle: its coordinate system is the original Honda VML
    /// canvas and is transformed as one unit with the diagram.
    static func sourceLinkFrame(_ link: ImageAnnotationLink) -> CGRect {
        CGRect(x: link.x, y: link.y, width: max(link.width, 1), height: max(link.height, 1))
    }

    static func link(at sourcePoint: CGPoint, in links: [ImageAnnotationLink]) -> ImageAnnotationLink? {
        links.first { sourceLinkFrame($0).contains(sourcePoint) }
    }

    static func aspectFit(canvas: CGSize, in viewport: CGRect) -> CGRect {
        guard canvas.width > 0, canvas.height > 0, viewport.width > 0, viewport.height > 0 else {
            return CGRect(origin: viewport.origin, size: .zero)
        }
        let scale = min(viewport.width / canvas.width, viewport.height / canvas.height)
        let size = CGSize(width: canvas.width * scale, height: canvas.height * scale)
        return CGRect(
            x: viewport.midX - size.width / 2,
            y: viewport.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    static func contentSize(canvas: CGSize, viewport: CGSize, zoomScale: CGFloat) -> CGSize {
        guard canvas.width > 0, canvas.height > 0 else { return .zero }
        let fitScale = min(viewport.width / canvas.width, viewport.height / canvas.height)
        let effectiveScale = max(fitScale, zoomScale)
        return CGSize(width: canvas.width * effectiveScale, height: canvas.height * effectiveScale)
    }

    static func annotationFontSize(sourcePoints: CGFloat, renderScale: CGFloat) -> CGFloat {
        max(0, sourcePoints * 4 / 3 * renderScale)
    }

    static func annotationFrames(
        _ annotations: [ImageAnnotation],
        canvas: CGSize,
        fontScale: CGFloat = 4 / 3
    ) -> [CGRect] {
        let proposed = annotations.map { annotation in
            let fontSize = max(CGFloat(annotation.fontSize ?? 7), 1)
            let constrainedWidth = annotation.width.map { CGFloat($0) }
            let measured = (annotation.text as NSString).boundingRect(
                with: CGSize(width: constrainedWidth ?? .greatestFiniteMagnitude, height: .greatestFiniteMagnitude),
                options: constrainedWidth == nil ? [.usesFontLeading] : [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: UIFont.systemFont(ofSize: fontSize)],
                context: nil
            ).integral.size
            return CGRect(
                x: CGFloat(annotation.x),
                y: CGFloat(annotation.y),
                width: max(constrainedWidth ?? measured.width + 1, 1),
                height: max(annotation.height.map { CGFloat($0) } ?? 0, measured.height + 1, 1)
            )
        }
        return resolveCollisions(proposed, within: CGRect(origin: .zero, size: canvas), spacing: 2)
    }

    static func resolveCollisions(_ proposed: [CGRect], within bounds: CGRect, spacing: CGFloat) -> [CGRect] {
        guard bounds.width > 0, bounds.height > 0 else { return proposed }
        var placed: [CGRect] = []
        for original in proposed {
            let size = CGSize(width: min(original.width, bounds.width), height: min(original.height, bounds.height))
            let base = clamp(CGRect(origin: original.origin, size: size), to: bounds)
            if !intersects(base, placed: placed, spacing: spacing) {
                placed.append(base)
                continue
            }

            let verticalStep = max(size.height + spacing, 2)
            let horizontalStep = max(min(size.width / 2, 44) + spacing, 2)
            var resolved: CGRect?
            for ring in 1...80 where resolved == nil {
                let offsets = [
                    CGPoint(x: 0, y: -CGFloat(ring) * verticalStep),
                    CGPoint(x: 0, y: CGFloat(ring) * verticalStep),
                    CGPoint(x: -CGFloat(ring) * horizontalStep, y: 0),
                    CGPoint(x: CGFloat(ring) * horizontalStep, y: 0),
                    CGPoint(x: -CGFloat(ring) * horizontalStep, y: -CGFloat(ring) * verticalStep),
                    CGPoint(x: CGFloat(ring) * horizontalStep, y: CGFloat(ring) * verticalStep)
                ]
                for offset in offsets {
                    let candidate = clamp(base.offsetBy(dx: offset.x, dy: offset.y), to: bounds)
                    if !intersects(candidate, placed: placed, spacing: spacing) {
                        resolved = candidate
                        break
                    }
                }
            }
            placed.append(resolved ?? base)
        }
        return placed
    }

    static func boundedOffset(_ offset: CGSize, contentSize: CGSize, viewport: CGSize) -> CGSize {
        let horizontal = max((contentSize.width - viewport.width) / 2, 0)
        let vertical = max((contentSize.height - viewport.height) / 2, 0)
        return CGSize(
            width: min(max(offset.width, -horizontal), horizontal),
            height: min(max(offset.height, -vertical), vertical)
        )
    }

    /// Uses the drag's predicted end point and clamps it to the source image.
    /// Animating to this result gives the viewer inertial settling without
    /// ever exposing an empty edge around a zoomed diagram.
    static func projectedOffset(
        start: CGSize,
        translation: CGSize,
        predictedTranslation: CGSize,
        contentSize: CGSize,
        viewport: CGSize
    ) -> CGSize {
        let projected = CGSize(
            width: start.width + predictedTranslation.width,
            height: start.height + predictedTranslation.height
        )
        let current = CGSize(
            width: start.width + translation.width,
            height: start.height + translation.height
        )
        let target = CGSize(
            width: abs(predictedTranslation.width) >= abs(translation.width) ? projected.width : current.width,
            height: abs(predictedTranslation.height) >= abs(translation.height) ? projected.height : current.height
        )
        return boundedOffset(target, contentSize: contentSize, viewport: viewport)
    }

    private static func clamp(_ frame: CGRect, to bounds: CGRect) -> CGRect {
        CGRect(
            x: min(max(frame.minX, bounds.minX), max(bounds.minX, bounds.maxX - frame.width)),
            y: min(max(frame.minY, bounds.minY), max(bounds.minY, bounds.maxY - frame.height)),
            width: frame.width,
            height: frame.height
        )
    }

    private static func intersects(_ frame: CGRect, placed: [CGRect], spacing: CGFloat) -> Bool {
        placed.contains { $0.insetBy(dx: -spacing, dy: -spacing).intersects(frame) }
    }
}

enum TooltipPlacement {
    static func frame(
        anchor: CGRect,
        tooltipSize: CGSize,
        viewport: CGRect,
        margin: CGFloat = 12,
        gap: CGFloat = 8
    ) -> CGRect {
        let available = viewport.insetBy(dx: margin, dy: margin)
        let size = CGSize(
            width: min(tooltipSize.width, max(available.width, 0)),
            height: min(tooltipSize.height, max(available.height, 0))
        )
        let centeredX = anchor.midX - size.width / 2
        let candidates = [
            CGPoint(x: centeredX, y: anchor.minY - gap - size.height),
            CGPoint(x: centeredX, y: anchor.maxY + gap),
            CGPoint(x: anchor.minX - gap - size.width, y: anchor.midY - size.height / 2),
            CGPoint(x: anchor.maxX + gap, y: anchor.midY - size.height / 2)
        ]
        let fitting = candidates.first { origin in
            available.contains(CGRect(origin: origin, size: size))
        }
        let origin = fitting ?? candidates[1]
        return CGRect(
            x: min(max(origin.x, available.minX), max(available.minX, available.maxX - size.width)),
            y: min(max(origin.y, available.minY), max(available.minY, available.maxY - size.height)),
            width: size.width,
            height: size.height
        )
    }
}
