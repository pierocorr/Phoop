import SwiftUI
import PhotosUI
import UIKit

/// Foto de perfil guardada en el iPhone.
@MainActor
final class AvatarStore: ObservableObject {
    static let shared = AvatarStore()
    @Published private(set) var image: UIImage?

    private var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("avatar.jpg")
    }

    private init() {
        if let data = try? Data(contentsOf: url) { image = UIImage(data: data) }
    }

    func set(_ data: Data) {
        guard let img = UIImage(data: data) else { return }
        // Recortar al centro y reducir a 400×400.
        let side = min(img.size.width, img.size.height)
        let crop = CGRect(x: (img.size.width - side) / 2, y: (img.size.height - side) / 2, width: side, height: side)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400))
        let small = renderer.image { _ in
            img.draw(in: CGRect(x: -crop.minX * 400 / side, y: -crop.minY * 400 / side,
                                width: img.size.width * 400 / side, height: img.size.height * 400 / side))
        }
        try? small.jpegData(compressionQuality: 0.85)?.write(to: url)
        withAnimation { image = small }
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
        withAnimation { image = nil }
    }
}

/// Avatar circular; al tocarlo se elige una foto de la galería.
struct AvatarButton: View {
    var size: CGFloat = 36
    @StateObject private var store = AvatarStore.shared
    @AppStorage(Settings.nameKey) private var name = ""
    @State private var item: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $item, matching: .images) {
            AvatarImage(size: size)
        }
        .accessibilityLabel("Cambiar foto de perfil")
        .onChange(of: item) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) { store.set(data) }
                item = nil
            }
        }
    }
}

struct AvatarImage: View {
    var size: CGFloat = 36
    @StateObject private var store = AvatarStore.shared
    @AppStorage(Settings.nameKey) private var name = ""

    var body: some View {
        Group {
            if let img = store.image {
                Image(uiImage: img).resizable().scaledToFill()
            } else if let first = name.first {
                Text(String(first).uppercased()).font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(Theme.bg)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.recovery)
            } else {
                Image(systemName: "person.fill").font(.system(size: size * 0.45))
                    .foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.cardHi)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Theme.text.opacity(0.15), lineWidth: 1))
    }
}
