import WidgetKit
import SwiftUI
import UIKit

// MARK: - Réglage : adresse du site

enum WidgetConfig {
    /// ⚠️ À MODIFIER : la même adresse que dans SiteConfig.swift, avec le "/" final.
    static let siteAddress = "https://chacounette07.github.io/Groupe-Chacounette/"
}

// MARK: - Photos (même ordre que dans donnees.js : la photo du jour est la même que sur le site)

struct DailyPhoto {
    let file: String
    let caption: String
}

enum DailyPhotos {
    static let all: [DailyPhoto] = [
        DailyPhoto(file: "IMG_0229.jpeg", caption: "Assise. Elle vous a vue."),
        DailyPhoto(file: "IMG_0410.jpeg", caption: "Tête posée. Ne pas bouger."),
        DailyPhoto(file: "IMG_0358.jpeg", caption: "Yeux fermés. Ne pas déranger."),
        DailyPhoto(file: "IMG_0019.jpeg", caption: "En observation."),
        DailyPhoto(file: "IMG_0109.jpeg", caption: "Expression neutre. Jugement en cours."),
        DailyPhoto(file: "IMG_0415.jpeg", caption: "Toujours sur le même genou."),
        DailyPhoto(file: "IMG_0421.jpeg", caption: "Le regard vert."),
        DailyPhoto(file: "IMG_0413.jpeg", caption: "Gros plan sur le museau.")
    ]

    /// Même calcul que le site : numéro du jour (date locale) modulo le nombre de photos.
    static func photo(for date: Date) -> DailyPhoto {
        let local = Calendar.current.dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let midnightUTC = utc.date(from: local) ?? date
        let day = Int(floor(midnightUTC.timeIntervalSince1970 / 86400))
        let count = all.count
        return all[((day % count) + count) % count]
    }
}

// MARK: - Données du widget

struct PhotoEntry: TimelineEntry {
    let date: Date
    let caption: String
    let image: UIImage?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> PhotoEntry {
        PhotoEntry(date: Date(), caption: "Chacounette", image: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (PhotoEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        let photo = DailyPhotos.photo(for: Date())
        fetchImage(file: photo.file) { image in
            completion(PhotoEntry(date: Date(), caption: photo.caption, image: image))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PhotoEntry>) -> Void) {
        let now = Date()
        let photo = DailyPhotos.photo(for: now)
        fetchImage(file: photo.file) { image in
            let entry = PhotoEntry(date: now, caption: photo.caption, image: image)
            // Nouvelle photo après minuit ; en cas d'échec (pas de réseau), nouvel essai dans 1 heure.
            let nextMidnight = Calendar.current.nextDate(after: now,
                                                         matching: DateComponents(hour: 0, minute: 5),
                                                         matchingPolicy: .nextTime)
                ?? now.addingTimeInterval(6 * 3600)
            let refresh = image == nil ? now.addingTimeInterval(3600) : nextMidnight
            completion(Timeline(entries: [entry], policy: .after(refresh)))
        }
    }

    /// Télécharge la photo depuis le site, puis la réduit (les widgets ont une mémoire limitée).
    private func fetchImage(file: String, completion: @escaping (UIImage?) -> Void) {
        guard let base = URL(string: WidgetConfig.siteAddress),
              let url = URL(string: file, relativeTo: base) else {
            completion(nil)
            return
        }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data, let image = UIImage(data: data) else {
                completion(nil)
                return
            }
            completion(image.downsampled(maxSide: 900))
        }.resume()
    }
}

extension UIImage {
    func downsampled(maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return self }
        let ratio = maxSide / longest
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - Affichage

struct ChacounetteWidgetView: View {
    let entry: PhotoEntry
    @Environment(\.widgetFamily) private var family

    private var background: some View {
        ZStack {
            if let image = entry.image {
                Color.clear
                    .overlay(alignment: .top) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                    .clipped()
            } else {
                Color(.systemGray5)
            }
            LinearGradient(colors: [Color.black.opacity(0.0), Color.black.opacity(0.7)],
                           startPoint: .center,
                           endPoint: .bottom)
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 2) {
            Spacer(minLength: 0)
            Text("Chacounette")
                .font(.system(size: family == .systemSmall ? 15 : 18, weight: .semibold))
            Text(entry.caption)
                .font(.system(size: family == .systemSmall ? 11 : 14))
                .lineLimit(2)
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    var body: some View {
        if #available(iOS 17.0, *) {
            label.containerBackground(for: .widget) { background }
        } else {
            ZStack {
                background
                label.padding(14)
            }
        }
    }
}

// MARK: - Widget

@main
struct ChacounetteWidget: Widget {
    let kind = "ChacounetteWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            ChacounetteWidgetView(entry: entry)
        }
        .configurationDisplayName("Photo du jour")
        .description("Une photo de Chacounette, différente chaque jour.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
