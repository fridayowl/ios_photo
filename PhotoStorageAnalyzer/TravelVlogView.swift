import SwiftUI
import MapKit
import Photos

// MARK: - Premium Travel Vlog View
struct TravelVlogView: View {
    @EnvironmentObject var analyzer: PhotoAnalyzer
    @State private var isMapExpanded = false
    @State private var appeared = false
    @State private var selectedAsset: AnalyzedAsset? = nil
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 30.0, longitude: 0.0),
        span: MKCoordinateSpan(latitudeDelta: 120.0, longitudeDelta: 120.0)
    )

    private var sortedCities: [LocationGroup] {
        analyzer.locationsBreakdown.sorted {
            ($0.assets.first?.creationDate ?? .distantPast) > ($1.assets.first?.creationDate ?? .distantPast)
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // HERO MAP
                heroMapSection
                    .offset(y: appeared ? 0 : -20)
                    .opacity(appeared ? 1 : 0)

                // STATS ROW
                statsRow
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .offset(y: appeared ? 0 : 15)
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(response: 0.55, dampingFraction: 0.75).delay(0.1), value: appeared)

                // SECTION TITLE
                HStack {
                    Rectangle()
                        .fill(Color.purple)
                        .frame(width: 3, height: 18)
                        .cornerRadius(2)
                    Text("Your Journey")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .padding(.bottom, 4)
                .offset(y: appeared ? 0 : 15)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.55, dampingFraction: 0.75).delay(0.2), value: appeared)

                // TIMELINE CARDS
                VStack(spacing: 0) {
                    ForEach(Array(sortedCities.enumerated()), id: \.element.id) { index, city in
                        TripCard(city: city, index: index, isLast: index == sortedCities.count - 1, appeared: appeared)
                            .animation(
                                .spring(response: 0.6, dampingFraction: 0.78).delay(0.18 + Double(index) * 0.07),
                                value: appeared
                            )
                            .onTapGesture {
                                selectedAsset = city.assets.first
                            }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
        .navigationTitle("Travel Vlog")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    isMapExpanded = true
                } label: {
                    Label("Full Map", systemImage: "map")
                        .font(.subheadline)
                        .foregroundColor(.purple)
                }
            }
        }
        .sheet(isPresented: $isMapExpanded) {
            FullScreenMapView().environmentObject(analyzer)
        }
        .navigationDestination(for: LocationGroup.self) { city in
            CityDetailView(city: city).environmentObject(analyzer)
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) {
                appeared = true
            }
            if let first = sortedCities.first,
               let asset = first.assets.first(where: { $0.latitude != nil }),
               let lat = asset.latitude, let lon = asset.longitude {
                withAnimation(.easeInOut(duration: 1.2)) {
                    mapRegion = MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                        span: MKCoordinateSpan(latitudeDelta: 40.0, longitudeDelta: 40.0)
                    )
                }
            }
        }
    }

    // MARK: - Hero Map
    private var heroMapSection: some View {
        ZStack(alignment: .bottom) {
            Map(coordinateRegion: $mapRegion, annotationItems: locationMarkers) { marker in
                MapAnnotation(coordinate: marker.coordinate) {
                    NavigationLink(value: analyzer.locationsBreakdown.first(where: { $0.name == marker.name })) {
                        VlogMapPin(count: marker.count, name: marker.name)
                    }
                }
            }
            .frame(height: 240)
            .ignoresSafeArea(edges: .top)

            // Fade gradient at bottom of map
            LinearGradient(
                colors: [Color.clear, Color(UIColor.systemGroupedBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 60)
        }
    }

    // MARK: - Stats Row
    private var statsRow: some View {
        HStack(spacing: 12) {
            StatPill(icon: "mappin.circle.fill", value: "\(sortedCities.count)", label: "Places")
            StatPill(icon: "photo.fill", value: "\(sortedCities.reduce(0) { $0 + $1.count })", label: "Memories")
            if let oldest = sortedCities.last?.assets.first?.creationDate {
                StatPill(icon: "calendar", value: yearString(oldest), label: "Since")
            }
        }
    }

    private func yearString(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy"; return f.string(from: date)
    }

    // MARK: - Location Markers
    private var locationMarkers: [LocationMarker] {
        sortedCities.compactMap { group in
            guard let asset = group.assets.first(where: { $0.latitude != nil && $0.longitude != nil }),
                  let lat = asset.latitude, let lon = asset.longitude else { return nil }
            return LocationMarker(
                name: group.name,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                count: group.count,
                firstAssetIdentifier: asset.localIdentifier
            )
        }
    }
}

// MARK: - Trip Card
struct TripCard: View {
    let city: LocationGroup
    let index: Int
    let isLast: Bool
    let appeared: Bool

    private var date: Date? { city.assets.first?.creationDate }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Timeline spine
            VStack(spacing: 0) {
                Circle()
                    .fill(index == 0 ? Color.purple : Color.purple.opacity(0.4))
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle().stroke(Color.white, lineWidth: 2)
                            .shadow(color: .purple.opacity(0.3), radius: 3)
                    )
                    .padding(.top, 22)

                if !isLast {
                    Rectangle()
                        .fill(Color.purple.opacity(0.18))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 28)

            // Card body
            NavigationLink(value: city) {
                VStack(alignment: .leading, spacing: 0) {
                    // Photo strip
                    if !city.assets.isEmpty {
                        photoStrip
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                // date badge top-left
                                dateBadge
                                    .padding(8),
                                alignment: .topLeading
                            )
                    }

                    // Text content
                    VStack(alignment: .leading, spacing: 6) {
                        Text(city.name)
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        HStack(spacing: 10) {
                            Label("\(city.count)", systemImage: "photo.fill")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.purple)

                            Label(formatSize(city.size), systemImage: "internaldrive.fill")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.plain)
            .padding(.leading, 12)
            .padding(.bottom, isLast ? 0 : 16)
            .offset(x: appeared ? 0 : 30)
            .opacity(appeared ? 1 : 0)
        }
    }

    private var photoStrip: some View {
        let assets = Array(city.assets.prefix(3))
        return HStack(spacing: 2) {
            ForEach(Array(assets.enumerated()), id: \.element.localIdentifier) { i, asset in
                TripPhotoCell(identifier: asset.localIdentifier, flex: i == 0 ? 1.6 : 1.0)
            }
            if city.assets.count > 3 {
                ZStack {
                    TripPhotoCell(identifier: city.assets[3].localIdentifier, flex: 1.0)
                    Color.black.opacity(0.45)
                    Text("+\(city.assets.count - 3)")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .frame(height: 110)
    }

    private var dateBadge: some View {
        Group {
            if let d = date {
                Text(monthYear(d))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.45))
                    .clipShape(Capsule())
            }
        }
    }

    private func monthYear(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM yyyy"; return f.string(from: d)
    }

    private func formatSize(_ bytes: Int64) -> String {
        let f = ByteCountFormatter(); f.countStyle = .binary; return f.string(fromByteCount: bytes)
    }
}

// MARK: - Trip Photo Cell (single cell in strip)
struct TripPhotoCell: View {
    let identifier: String
    let flex: Double
    @State private var image: UIImage? = nil

    var body: some View {
        GeometryReader { geo in
            Group {
                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color(UIColor.tertiarySystemFill))
                        .overlay(Image(systemName: "photo").foregroundColor(.secondary.opacity(0.4)))
                }
            }
        }
        .aspectRatio(flex, contentMode: .fit)
        .onAppear { load() }
    }

    private func load() {
        guard image == nil else { return }
        let results = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = results.firstObject else { return }
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .opportunistic
        opts.isNetworkAccessAllowed = false
        opts.isSynchronous = false
        PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 200, height: 200), contentMode: .aspectFill, options: opts) { img, _ in
            if let img { DispatchQueue.main.async { self.image = img } }
        }
    }
}

// MARK: - Vlog Map Pin (cleaner than default)
struct VlogMapPin: View {
    let count: Int
    let name: String

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(Color.purple)
                    .frame(width: 32, height: 32)
                    .shadow(color: .purple.opacity(0.35), radius: 6, y: 3)
                Image(systemName: "camera.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
            }
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 6))
                .foregroundColor(.purple)
                .offset(y: -3)

            Text(name.components(separatedBy: ",").first ?? name)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.5))
                .clipShape(Capsule())
        }
    }
}

// MARK: - Stat Pill
struct StatPill: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.purple)
            Text(value)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundColor(.primary)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - City Detail View (when tapping a trip card)
struct CityDetailView: View {
    @EnvironmentObject var analyzer: PhotoAnalyzer
    let city: LocationGroup
    @State private var selectedAsset: AnalyzedAsset? = nil

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header stats
                HStack(spacing: 16) {
                    Label("\(city.count) photos", systemImage: "photo.fill")
                        .font(.caption)
                        .foregroundColor(.purple)
                    let f = ByteCountFormatter()
                    let sizeStr = f.string(fromByteCount: city.size)
                    Label(sizeStr, systemImage: "internaldrive.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    if let date = city.assets.first?.creationDate {
                        let df = DateFormatter()
                        let _ = { df.dateFormat = "MMM yyyy" }()
                        Text(df.string(from: date))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)

                // Grid
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(city.assets) { asset in
                        TripPhotoCell(identifier: asset.localIdentifier, flex: 1.0)
                            .aspectRatio(1, contentMode: .fit)
                            .onTapGesture { selectedAsset = asset }
                    }
                }
            }
            .padding(.top, 12)
        }
        .navigationTitle(city.name)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(UIColor.systemGroupedBackground))
        .sheet(item: $selectedAsset) { asset in
            PhotoDetailView(analyzedAsset: asset).environmentObject(analyzer)
        }
    }
}


