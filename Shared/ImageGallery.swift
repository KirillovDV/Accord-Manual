import SwiftUI
import UIKit

@Observable @MainActor final class FullScreenPresenter {
    static let shared = FullScreenPresenter()
    private var overlayWindow: UIWindow?

    func present<Content: View>(_ content: Content) {
        guard overlayWindow == nil, let scene = activeScene() else { return }
        let controller = UIHostingController(
            rootView: content.environment(self)
        )
        controller.view.backgroundColor = .black
        let window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        window.windowLevel = .alert - 1
        window.backgroundColor = .black
        window.rootViewController = controller
        window.isHidden = false
        window.makeKeyAndVisible()
        overlayWindow = window
    }

    func dismiss() {
        guard let overlayWindow else { return }
        overlayWindow.isHidden = true
        overlayWindow.rootViewController = nil
        self.overlayWindow = nil
    }

    private func activeScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { scene in scene.activationState == .foregroundActive }
    }
}

struct GalleryPresentation: View {
    @Environment(FullScreenPresenter.self) private var fullScreenPresenter
    let article: ManualArticle
    let initialIndex: Int
    let openLink: (String) -> Void
    let linkTitle: (String) -> String?
    @State private var isVisible = false

    var body: some View {
        ImageGallery(
            article: article,
            initialIndex: initialIndex,
            close: { dismiss() },
            openLink: { target in dismiss(afterDismiss: { openLink(target) }) },
            linkTitle: linkTitle
        )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1 : 0.985)
            .task {
                withAnimation(.easeOut(duration: 0.18)) {
                    isVisible = true
                }
            }
    }

    private func dismiss(afterDismiss: @escaping () -> Void = {}) {
        withAnimation(.easeIn(duration: 0.16)) {
            isVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.17) {
            fullScreenPresenter.dismiss()
            afterDismiss()
        }
    }
}

struct ImageGallery: View {
    let article: ManualArticle
    let close: () -> Void
    let openLink: (String) -> Void
    let linkTitle: (String) -> String?
    @State private var index: Int

    init(article: ManualArticle, initialIndex: Int = 0, close: @escaping () -> Void, openLink: @escaping (String) -> Void = { _ in }, linkTitle: @escaping (String) -> String? = { _ in nil }) {
        self.article = article
        self.close = close
        self.openLink = openLink
        self.linkTitle = linkTitle
        _index = State(initialValue: min(max(initialIndex, 0), max(article.images.count - 1, 0)))
    }

    var body: some View {
        Group {
            if article.images.indices.contains(index) {
                let metadata = article.images[index]
                ZoomableImage(
                    metadata: metadata,
                    label: metadata.caption ?? metadata.altText ?? "Рисунок \(index + 1)",
                    positionLabel: "Рисунок \(index + 1) из \(article.images.count)",
                    dismiss: close,
                    showPrevious: article.images.count > 1 ? { withAnimation(.easeInOut(duration: 0.18)) { index = max(index - 1, 0) } } : nil,
                    showNext: article.images.count > 1 ? { withAnimation(.easeInOut(duration: 0.18)) { index = min(index + 1, article.images.count - 1) } } : nil,
                    canShowPrevious: index > 0,
                    canShowNext: index < article.images.count - 1,
                    openLink: openLink,
                    linkTitle: linkTitle
                )
                .id(metadata.id)
            } else {
                ContentUnavailableView("Изображение недоступно", systemImage: "photo.badge.exclamationmark")
                    .foregroundStyle(.white)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

struct ZoomableImage: View {
    private struct SelectedLink: Identifiable {
        let link: ImageAnnotationLink
        let sourceFrame: CGRect
        let title: String?
        var id: String { link.id }
    }

    let metadata: ManualImage
    let label: String
    let positionLabel: String
    let dismiss: () -> Void
    let showPrevious: (() -> Void)?
    let showNext: (() -> Void)?
    let canShowPrevious: Bool
    let canShowNext: Bool
    let openLink: (String) -> Void
    let linkTitle: (String) -> String?
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var didFail = false
    @State private var scale: CGFloat?
    @State private var gestureStartScale: CGFloat?
    @State private var offset = CGSize.zero
    @State private var gestureStartOffset = CGSize.zero
    @State private var selectedLink: SelectedLink?

    var body: some View {
        GeometryReader { geometry in
            let canvas = canvasSize(for: image)
            let layout = DiagramGeometry.viewerLayout(
                canvas: canvas,
                container: CGRect(origin: .zero, size: geometry.size),
                // ImageGallery itself stays inside the hosting view's safe
                // area. Applying GeometryReader's insets here a second time
                // would push Photos-style chrome too far from the edges.
                safeAreaInsets: .zero,
                topBarHeight: 56,
                bottomBarHeight: 64
            )
            let viewport = layout.artworkViewport
            let fitScale = fitScale(canvas: canvas, viewport: viewport.size)
            let activeScale = scale ?? fitScale
            let nativeScale = nativeScale(canvas: canvas, image: image)
            let maximumScale = max(fitScale * 8, nativeScale * 8, 1)

            ZStack(alignment: .topLeading) {
                Color.black
                    .ignoresSafeArea()

                if let image {
                    ZStack {
                    AnnotatedDiagram(
                        image: image,
                        metadata: metadata,
                        annotationLinkSelected: { link, frame in
                            selectedLink = SelectedLink(link: link, sourceFrame: frame, title: linkTitle(link.target))
                        },
                        renderScale: activeScale
                    )
                    .frame(width: canvas.width * activeScale, height: canvas.height * activeScale)
                    .position(
                        x: viewport.size.width / 2 + offset.width,
                        y: viewport.size.height / 2 + offset.height
                    )
                    .contentShape(Rectangle())
                    .gesture(zoomGesture(fitScale: fitScale, maximumScale: maximumScale, viewport: viewport.size, canvas: canvas))
                    .simultaneousGesture(panGesture(fitScale: fitScale, activeScale: activeScale, viewport: viewport.size, canvas: canvas))
                    .simultaneousGesture(TapGesture(count: 2).onEnded {
                        toggleZoom(fitScale: fitScale, maximumScale: maximumScale, viewport: viewport.size, canvas: canvas)
                    })
                    .accessibilityLabel(label)
                    .accessibilityHint("Сведите или разведите пальцы для изменения масштаба. Двойное касание переключает масштаб.")
                    }
                    .frame(width: viewport.width, height: viewport.height)
                    .clipped()
                    .position(x: viewport.midX, y: viewport.midY)
                } else if didFail {
                    ContentUnavailableView(
                        "Изображение недоступно",
                        systemImage: "photo.badge.exclamationmark",
                        description: Text(label)
                    )
                    .position(x: viewport.midX, y: viewport.midY)
                } else {
                    ProgressView("Загрузка оригинала…")
                        .position(x: viewport.midX, y: viewport.midY)
                }

                if let selectedLink, image != nil {
                    DiagramLinkTooltip(
                        linkText: selectedLink.link.text,
                        destinationTitle: selectedLink.title,
                        anchor: transformed(
                            selectedLink.sourceFrame,
                            canvas: canvas,
                            scale: activeScale,
                            offset: offset,
                            viewport: viewport
                        ),
                        viewport: viewport,
                        close: { self.selectedLink = nil },
                        open: {
                            let target = selectedLink.link.target
                            self.selectedLink = nil
                            openLink(target)
                        }
                    )
                }

                PhotoViewerTopBar(
                    positionLabel: positionLabel,
                    dismiss: dismiss,
                    showPrevious: showPrevious,
                    showNext: showNext,
                    canShowPrevious: canShowPrevious,
                    canShowNext: canShowNext
                )
                .frame(width: layout.topBarFrame.width, height: layout.topBarFrame.height)
                .position(x: layout.topBarFrame.midX, y: layout.topBarFrame.midY)
                .accessibilityIdentifier("photo-style-image-viewer")

                PhotoViewerBottomBar(
                    label: label,
                    isOriginalScale: abs(activeScale - nativeScale) < 0.01,
                    links: metadata.annotations.flatMap(\.links),
                    selectLink: { link in
                        selectedLink = SelectedLink(link: link, sourceFrame: DiagramGeometry.sourceLinkFrame(link), title: linkTitle(link.target))
                    },
                    showFit: {
                        withAnimation(.snappy) {
                            scale = nil
                            offset = .zero
                            gestureStartOffset = .zero
                            selectedLink = nil
                        }
                    },
                    showOriginal: {
                        withAnimation(.snappy) {
                            scale = min(maximumScale, nativeScale)
                            let contentSize = CGSize(width: canvas.width * nativeScale, height: canvas.height * nativeScale)
                            offset = DiagramGeometry.boundedOffset(offset, contentSize: contentSize, viewport: viewport.size)
                            gestureStartOffset = offset
                            selectedLink = nil
                        }
                    }
                )
                .frame(width: layout.bottomBarFrame.width, height: layout.bottomBarFrame.height)
                .position(x: layout.bottomBarFrame.midX, y: layout.bottomBarFrame.midY)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .onChange(of: geometry.size) { _, _ in
                scale = nil
                gestureStartScale = nil
                offset = .zero
                gestureStartOffset = .zero
                selectedLink = nil
            }
            .accessibilityIdentifier("full-screen-image-viewer")
        }
        .task(id: metadata.localRelativePath) {
            image = await ManualImageCache.shared.image(path: metadata.localRelativePath)
            didFail = image == nil
        }
    }

    private func canvasSize(for image: UIImage?) -> CGSize {
        CGSize(
            width: max(metadata.canvasWidth ?? Double(image?.size.width ?? 1), 1),
            height: max(metadata.canvasHeight ?? Double(image?.size.height ?? 1), 1)
        )
    }

    private func nativeScale(canvas: CGSize, image: UIImage?) -> CGFloat {
        let raster = rasterSize(for: image)
        let scale = DiagramGeometry.nativeRasterScale(
            sourceCanvas: canvas,
            rasterPixels: raster,
            displayScale: displayScale
        )
        return max(min(scale.width, scale.height), 0.01)
    }

    private func rasterSize(for image: UIImage?) -> CGSize {
        guard let image else { return .init(width: 1, height: 1) }
        if let cgImage = image.cgImage {
            return CGSize(width: cgImage.width, height: cgImage.height)
        }
        return CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    }

    private func fitScale(canvas: CGSize, viewport: CGSize) -> CGFloat {
        min(viewport.width / canvas.width, viewport.height / canvas.height)
    }

    private func zoomGesture(fitScale: CGFloat, maximumScale: CGFloat, viewport: CGSize, canvas: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let initial = gestureStartScale ?? (scale ?? fitScale)
                if gestureStartScale == nil { gestureStartScale = initial }
                scale = min(max(initial * value, fitScale), maximumScale)
                selectedLink = nil
            }
            .onEnded { _ in
                let activeScale = scale ?? fitScale
                offset = bounded(offset, canvas: canvas, scale: activeScale, viewport: viewport)
                gestureStartOffset = offset
                gestureStartScale = nil
                if abs(activeScale - fitScale) < 0.01 {
                    scale = nil
                    offset = .zero
                    gestureStartOffset = .zero
                }
            }
    }

    private func panGesture(fitScale: CGFloat, activeScale: CGFloat, viewport: CGSize, canvas: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard activeScale > fitScale + 0.01 else { return }
                offset = bounded(
                    CGSize(
                        width: gestureStartOffset.width + value.translation.width,
                        height: gestureStartOffset.height + value.translation.height
                    ),
                    canvas: canvas,
                    scale: activeScale,
                    viewport: viewport
                )
                selectedLink = nil
            }
            .onEnded { value in
                if activeScale <= fitScale + 0.01,
                   value.translation.height > 120,
                   abs(value.translation.width) < 80 {
                    dismiss()
                } else {
                    let contentSize = CGSize(width: canvas.width * activeScale, height: canvas.height * activeScale)
                    withAnimation(.easeOut(duration: 0.28)) {
                        offset = DiagramGeometry.projectedOffset(
                            start: gestureStartOffset,
                            translation: value.translation,
                            predictedTranslation: value.predictedEndTranslation,
                            contentSize: contentSize,
                            viewport: viewport
                        )
                    }
                    gestureStartOffset = offset
                }
            }
    }

    private func toggleZoom(fitScale: CGFloat, maximumScale: CGFloat, viewport: CGSize, canvas: CGSize) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
            let activeScale = scale ?? fitScale
            if activeScale > fitScale + 0.01 {
                scale = nil
                offset = .zero
            } else {
                scale = min(maximumScale, max(1, fitScale * 2.5))
                offset = bounded(offset, canvas: canvas, scale: scale ?? fitScale, viewport: viewport)
            }
            gestureStartOffset = offset
            selectedLink = nil
        }
    }

    private func bounded(_ value: CGSize, canvas: CGSize, scale: CGFloat, viewport: CGSize) -> CGSize {
        DiagramGeometry.boundedOffset(
            value,
            contentSize: CGSize(width: canvas.width * scale, height: canvas.height * scale),
            viewport: viewport
        )
    }

    private func transformed(_ source: CGRect, canvas: CGSize, scale: CGFloat, offset: CGSize, viewport: CGRect) -> CGRect {
        CGRect(
            x: viewport.midX + offset.width + (source.minX - canvas.width / 2) * scale,
            y: viewport.midY + offset.height + (source.minY - canvas.height / 2) * scale,
            width: source.width * scale,
            height: source.height * scale
        )
    }
}

private struct PhotoViewerTopBar: View {
    let positionLabel: String
    let dismiss: () -> Void
    let showPrevious: (() -> Void)?
    let showNext: (() -> Void)?
    let canShowPrevious: Bool
    let canShowNext: Bool

    var body: some View {
        ZStack {
            Text(positionLabel)
                .font(.headline)
                .lineLimit(1)
                .foregroundStyle(.white)
                .accessibilityLabel(positionLabel)

            HStack(spacing: 8) {
                PhotoViewerIconButton("Закрыть", systemImage: "xmark", action: dismiss)
                    .accessibilityHint("Закрывает просмотр рисунка")
                Spacer()
                if let showPrevious {
                    PhotoViewerIconButton("Предыдущий рисунок", systemImage: "chevron.left", action: showPrevious)
                        .disabled(!canShowPrevious)
                }
                if let showNext {
                    PhotoViewerIconButton("Следующий рисунок", systemImage: "chevron.right", action: showNext)
                        .disabled(!canShowNext)
                }
            }
        }
        .padding(.horizontal, 12)
    }
}

private struct PhotoViewerBottomBar: View {
    let label: String
    let isOriginalScale: Bool
    let links: [ImageAnnotationLink]
    let selectLink: (ImageAnnotationLink) -> Void
    let showFit: () -> Void
    let showOriginal: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.white)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Подпись рисунка: \(label)")
            if !links.isEmpty {
                Menu("Ссылки на схеме", systemImage: "link") {
                    ForEach(links) { link in
                        Button(link.text) { selectLink(link) }
                    }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .frame(width: 48, height: 48)
                .accessibilityHint("Показывает все связанные статьи со схемы")
            }
            Button("Вписать", systemImage: "arrow.down.right.and.arrow.up.left") { showFit() }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .frame(width: 48, height: 48)
                .accessibilityHint("Центрирует схему целиком")
            Button("Масштаб один к одному", systemImage: "1.magnifyingglass") { showOriginal() }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .frame(width: 48, height: 48)
                .disabled(isOriginalScale)
                .accessibilityHint("Показывает схему в исходном масштабе с прокруткой")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(.black.opacity(0.56))
    }
}

private struct PhotoViewerIconButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    init(_ title: String, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .frame(width: 44, height: 44)
            .background(.ultraThinMaterial, in: Circle())
            .foregroundStyle(.white)
            .accessibilityLabel(title)
    }
}

private struct DiagramLinkTooltip: View {
    let linkText: String
    let destinationTitle: String?
    let anchor: CGRect
    let viewport: CGRect
    let close: () -> Void
    let open: () -> Void

    var body: some View {
        let maximumWidth = min(max(viewport.width - 32, 120), 360)
        let size = CGSize(width: maximumWidth, height: 128)
        let frame = TooltipPlacement.frame(anchor: anchor, tooltipSize: size, viewport: viewport)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(destinationTitle ?? linkText)
                    .font(.headline)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Закрыть подсказку", systemImage: "xmark.circle.fill", action: close)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
            }
            Text("Ссылка: \(linkText)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Button("Открыть статью", systemImage: "arrow.right.circle.fill", action: open)
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Закрывает просмотр схемы и открывает связанную статью")
        }
        .padding(12)
        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.35)) }
        .position(x: frame.midX, y: frame.midY)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Связанная статья: \(destinationTitle ?? linkText)")
        .accessibilityIdentifier("diagram-link-tooltip")
    }
}
