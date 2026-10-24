import SwiftUI
import UIKit

/// Downloads AI app logos once and keeps them in Caches, so Home shows real icons without refetching.
/// Only the parent's phone loads these; kids' devices never do.
actor AppIconLoader {
    static let shared = AppIconLoader()

    private var memory: [String: UIImage] = [:]
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appending(path: "AppIcons", directoryHint: .isDirectory)

    func image(for domain: String) async -> UIImage? {
        if let cached = memory[domain] { return cached }
        if let running = inFlight[domain] { return await running.value }
        let task = Task { await load(domain) }
        inFlight[domain] = task
        let image = await task.value
        inFlight[domain] = nil
        if let image { memory[domain] = image }
        return image
    }

    private func load(_ domain: String) async -> UIImage? {
        let file = folder.appending(path: "\(domain).png")
        if let data = try? Data(contentsOf: file), let image = UIImage(data: data) { return image }

        var components = URLComponents(string: "https://www.google.com/s2/favicons")!
        components.queryItems = [URLQueryItem(name: "domain", value: domain), URLQueryItem(name: "sz", value: "128")]
        guard let url = components.url,
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = UIImage(data: data),
              image.size.width >= 32 // Unknown sites get a tiny generic globe; use the letter tile instead.
        else { return nil }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: file)
        return image
    }
}

/// An app's logo, with a colored letter tile while it loads or when there is none.
struct AppIconView: View {
    let app: AIApp
    var size: CGFloat = 64
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.14)
                    .background(Color.white)
            } else {
                Text(String(app.name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(tileColor)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .accessibilityHidden(true)
        .task(id: app.primaryDomain) {
            image = await AppIconLoader.shared.image(for: app.primaryDomain)
        }
    }

    /// Stable per-app color, so a tile looks the same every time.
    private var tileColor: Color {
        let hue = Double(app.id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 360 }) / 360
        return Color(hue: hue, saturation: 0.55, brightness: 0.75)
    }
}
