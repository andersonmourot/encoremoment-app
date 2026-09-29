import SwiftUI
import UIKit

struct AvatarCropView: View {
    let image: UIImage
    var onSave: (Data) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var previewSize: CGFloat = 300
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer(minLength: 12)

                GeometryReader { proxy in
                    let size = min(proxy.size.width - 48, 320)
                    avatarPreview(size: size)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onAppear { previewSize = size }
                        .onChange(of: size) { newSize in
                            previewSize = newSize
                        }
                }
                .frame(height: 340)

                VStack(spacing: 8) {
                    Text("Move and pinch to position your profile picture.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Reset") {
                        scale = 1
                        lastScale = 1
                        offset = .zero
                        lastOffset = .zero
                    }
                    .font(.subheadline.weight(.semibold))
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Adjust Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Use Photo")
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private func avatarPreview(size: CGFloat) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .scaleEffect(scale)
            .offset(offset)
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(model.accentColor, lineWidth: 3))
            .shadow(radius: 12)
            .gesture(dragGesture)
            .simultaneousGesture(magnificationGesture)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(max(lastScale * value, 1), 5)
            }
            .onEnded { _ in
                lastScale = scale
            }
    }

    private func save() {
        guard let data = renderAvatarJPEG() else { return }
        isSaving = true
        Task {
            let saved = await onSave(data)
            isSaving = false
            if saved { dismiss() }
        }
    }

    private func renderAvatarJPEG(outputSize: CGFloat = 384) -> Data? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: outputSize, height: outputSize))
        let imageSize = image.size
        let baseScale = max(previewSize / imageSize.width, previewSize / imageSize.height)
        let outputScale = outputSize / previewSize
        let drawScale = baseScale * scale * outputScale
        let drawSize = CGSize(width: imageSize.width * drawScale, height: imageSize.height * drawScale)
        let drawOrigin = CGPoint(
            x: (outputSize - drawSize.width) / 2 + offset.width * outputScale,
            y: (outputSize - drawSize.height) / 2 + offset.height * outputScale
        )

        let rendered = renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: outputSize, height: outputSize))
            image.draw(in: CGRect(origin: drawOrigin, size: drawSize))
        }
        return rendered.jpegData(compressionQuality: 0.78)
    }
}
