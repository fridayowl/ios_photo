import SwiftUI
import MapKit
import Photos

// MARK: - Global image cache (prevents reloading on scroll)
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private var cache = NSCache<NSString, UIImage>()
    private init() { cache.countLimit = 300 }

    func get(_ id: String) -> UIImage? { cache.object(forKey: id as NSString) }
    func set(_ id: String, _ img: UIImage) { cache.setObject(img, forKey: id as NSString) }
}

@MainActor
final class CellImageLoader: ObservableObject {
    @Published var image: UIImage?
    private var requestID: PHImageRequestID?
    private var fetchTask: Task<Void, Never>?

    func load(identifier: String, size: CGFloat = 200) {
        if let cached = ThumbnailCache.shared.get(identifier) { image = cached; return }
        
        fetchTask?.cancel()
        
        if let cachedAsset = PhotoAnalyzer.shared?.getPHAsset(for: identifier) {
            requestImage(for: cachedAsset, size: size, identifier: identifier)
        } else {
            fetchTask = Task {
                let asset = await Task.detached(priority: .userInitiated) { () -> PHAsset? in
                    guard !Task.isCancelled else { return nil }
                    let results = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
                    return results.firstObject
                }.value
                
                guard !Task.isCancelled, let asset = asset else { return }
                requestImage(for: asset, size: size, identifier: identifier)
            }
        }
    }

    private func requestImage(for asset: PHAsset, size: CGFloat, identifier: String) {
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .opportunistic
        opts.isNetworkAccessAllowed = false
        opts.isSynchronous = false
        opts.resizeMode = .fast
        let target = CGSize(width: size, height: size)
        
        requestID = PHImageManager.default().requestImage(
            for: asset, targetSize: target, contentMode: .aspectFill, options: opts
        ) { [weak self] img, _ in
            guard let self, let img else { return }
            ThumbnailCache.shared.set(identifier, img)
            self.image = img
        }
    }

    func cancel() {
        fetchTask?.cancel()
        fetchTask = nil
        if let id = requestID { PHImageManager.default().cancelImageRequest(id); requestID = nil }
    }
}

// MARK: - Cached Formatters
private let monthFormatter: DateFormatter = {
    let f = DateFormatter(); f.dateFormat = "MMM yyyy"; return f
}()
private let yearFormatter: DateFormatter = {
    let f = DateFormatter(); f.dateFormat = "yyyy"; return f
}()
private let dayFormatter: DateFormatter = {
    let f = DateFormatter(); f.dateStyle = .medium; return f
}()

// MARK: - Helpers
private func fmtMonth(_ d: Date) -> String {
    monthFormatter.string(from: d)
}
private func fmtYear(_ d: Date) -> String {
    yearFormatter.string(from: d)
}
private func fmtDay(_ d: Date) -> String {
    dayFormatter.string(from: d)
}

// MARK: - Main TravelVlogView
struct TravelVlogView: View {
    @EnvironmentObject var analyzer: PhotoAnalyzer

    // Filters
    @State private var selectedYear: Int? = nil
    @State private var selectedMonth: Int? = nil   // 1-12
    @State private var isMapExpanded = false
    @State private var appeared = false
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 30, longitude: 15),
        span: MKCoordinateSpan(latitudeDelta: 100, longitudeDelta: 120)
    )

    // Asynchronous processed display data (avoids main-thread blocking)
    @State private var displayedGroups: [(String, [LocationGroup])] = []
    @State private var displayedCitiesCount = 0
    @State private var displayedMarkers: [LocationMarker] = []
    @State private var selectedCity: LocationGroup? = nil
    @State private var showMap = false
    @State private var isProcessing = true

    private var availableYears: [Int] {
        let cal = Calendar.current
        let years = Set(analyzer.locationsBreakdown.compactMap { $0.assets.first?.creationDate }.map { cal.component(.year, from: $0) })
        return years.sorted(by: >)
    }

    private var availableMonths: [Int] {
        guard let year = selectedYear else { return [] }
        let cal = Calendar.current
        let months = Set(analyzer.locationsBreakdown.compactMap { city -> Int? in
            guard let d = city.assets.first?.creationDate,
                  cal.component(.year, from: d) == year else { return nil }
            return cal.component(.month, from: d)
        })
        return months.sorted(by: >)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {

                    // ── MAP ──────────────────────────────────────────────
                    if isProcessing {
                        SkeletonRect(height: 210, cornerRadius: 20)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                    } else {
                        if showMap {
                            mapCard
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : -12)
                                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: appeared)
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        } else {
                            showMapPlaceholder
                        }
                    }

                    if isProcessing {
                        TravelVlogSkeletonView()
                            .padding(.top, 14)
                    } else {
                        // ── STATS ────────────────────────────────────────────
                        statsRow
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                            .opacity(appeared ? 1 : 0)
                            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.08), value: appeared)

                        // ── YEAR PICKER ──────────────────────────────────────
                        yearPicker
                            .padding(.top, 18)
                            .opacity(appeared ? 1 : 0)
                            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.14), value: appeared)

                        // ── MONTH CHIPS (only when year selected) ───────────
                        if selectedYear != nil {
                            monthChips
                                .padding(.top, 10)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        // ── JOURNEY HEADER ───────────────────────────────────
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.purple)
                                .frame(width: 4, height: 20)
                            Text(selectedYear == nil ? "All Journeys" : (selectedMonth == nil ? "Year \(selectedYear!)" : monthName(selectedMonth!)))
                                .font(.system(.title3, design: .rounded, weight: .bold))
                                .foregroundColor(.primary)
                            Spacer()
                            if displayedCitiesCount > 0 {
                                Text("\(displayedCitiesCount) places")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 22)
                        .padding(.bottom, 6)
                        .opacity(appeared ? 1 : 0)
                        .animation(.easeOut.delay(0.2), value: appeared)

                        // ── TIMELINE ─────────────────────────────────────────
                        if displayedGroups.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "mappin.slash")
                                    .font(.system(size: 40))
                                    .foregroundColor(.secondary.opacity(0.35))
                                Text("No trips for this period")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                        } else {
                            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                                ForEach(displayedGroups, id: \.0) { monthLabel, cities in
                                    Section {
                                        ForEach(Array(cities.enumerated()), id: \.element.id) { idx, city in
                                            TripCard(
                                                city: city,
                                                isLast: idx == cities.count - 1,
                                                appeared: appeared
                                            )
                                            .padding(.horizontal, 18)
                                            .opacity(appeared ? 1 : 0)
                                            .offset(x: appeared ? 0 : 24)
                                            .animation(
                                                .spring(response: 0.55, dampingFraction: 0.78)
                                                    .delay(0.22 + Double(idx) * 0.06),
                                                value: appeared
                                            )
                                        }
                                    } header: {
                                        MonthSectionHeader(label: monthLabel)
                                    }
                                }
                            }
                            .padding(.bottom, 32)
                        }
                    }
                }
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Travel Vlog")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { isMapExpanded = true } label: {
                        Image(systemName: "map.fill")
                            .foregroundColor(.purple)
                    }
                }
            }
            .navigationDestination(for: LocationGroup.self) { city in
                CityDetailView(city: city).environmentObject(analyzer)
            }
            .navigationDestination(isPresented: Binding(
                get: { selectedCity != nil },
                set: { if !$0 { selectedCity = nil } }
            )) {
                if let city = selectedCity {
                    CityDetailView(city: city).environmentObject(analyzer)
                }
            }
            .sheet(isPresented: $isMapExpanded) {
                FullScreenMapView().environmentObject(analyzer)
            }
            .onAppear {
                withAnimation { appeared = true }
                if selectedYear == nil {
                    let cal = Calendar.current
                    let latestDate = analyzer.locationsBreakdown
                        .compactMap { $0.assets.first?.creationDate }
                        .sorted(by: >)
                        .first
                    
                    if let latest = latestDate {
                        selectedYear = cal.component(.year, from: latest)
                        selectedMonth = cal.component(.month, from: latest)
                    }
                }
            }
            .task(id: selectedYear) {
                await performProcessing()
            }
            .task(id: selectedMonth) {
                await performProcessing()
            }
            .task(id: analyzer.locationsBreakdown) {
                await performProcessing()
            }
        }
    }

    // MARK: - Map Card
    private var mapCard: some View {
        ZStack(alignment: .bottomTrailing) {
            Map(coordinateRegion: $mapRegion, annotationItems: displayedMarkers) { marker in
                MapAnnotation(coordinate: marker.coordinate) {
                    Button(action: {
                        selectedCity = analyzer.locationsBreakdown.first(where: { $0.name == marker.name })
                    }) {
                        CompactMapPin(name: marker.name, count: marker.count)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: 210)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 12, y: 6)

            // Expand button
            Button { isMapExpanded = true } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
            .padding(10)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var showMapPlaceholder: some View {
        Button {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                showMap = true
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "map.fill")
                    .font(.title2)
                    .foregroundColor(.purple)
                    .frame(width: 48, height: 48)
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(12)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Show Interactive Map")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("Load \(displayedMarkers.count) travel locations on the map")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 8, y: 4)
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Stats row
    private var statsRow: some View {
        HStack(spacing: 10) {
            MiniStat(icon: "mappin.circle.fill", value: "\(displayedCitiesCount)", label: "Places")
            MiniStat(icon: "photo.fill", value: "\(displayedGroups.reduce(0) { $0 + $1.1.reduce(0) { $0 + $1.count } })", label: "Photos")
            if let oldest = analyzer.locationsBreakdown.last?.assets.first?.creationDate {
                MiniStat(icon: "calendar", value: fmtYear(oldest), label: "Since")
            }
            if let newest = displayedGroups.first?.1.first?.assets.first?.creationDate {
                MiniStat(icon: "clock.fill", value: fmtMonth(newest), label: "Latest")
            }
        }
    }

    // MARK: - Year Picker
    private var yearPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("YEAR")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 18)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // "All" chip
                    FilterChip(
                        label: "All",
                        isSelected: selectedYear == nil,
                        action: { withAnimation(.spring(response: 0.3)) { selectedYear = nil; selectedMonth = nil } }
                    )
                    ForEach(availableYears, id: \.self) { year in
                        FilterChip(
                            label: "\(year)",
                            isSelected: selectedYear == year,
                            action: {
                                withAnimation(.spring(response: 0.3)) {
                                    selectedYear = selectedYear == year ? nil : year
                                    selectedMonth = nil
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }

    // MARK: - Month Chips
    private var monthChips: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MONTH")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 18)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(
                        label: "All months",
                        isSelected: selectedMonth == nil,
                        action: { withAnimation(.spring(response: 0.3)) { selectedMonth = nil } }
                    )
                    ForEach(availableMonths, id: \.self) { month in
                        FilterChip(
                            label: monthName(month),
                            isSelected: selectedMonth == month,
                            action: {
                                withAnimation(.spring(response: 0.3)) {
                                    selectedMonth = selectedMonth == month ? nil : month
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }

    // MARK: - Helpers
    private func monthName(_ m: Int) -> String {
        monthFormatter.standaloneMonthSymbols[m - 1]
    }

    private func performProcessing() async {
        isProcessing = true
        let year = selectedYear
        let month = selectedMonth
        let cities = analyzer.locationsBreakdown

        let result = await Task.detached(priority: .userInitiated) { () -> (groups: [(String, [LocationGroup])], count: Int, markers: [LocationMarker]) in
            let cal = Calendar.current

            // 1. Sort all cities
            let sortedCities = cities.sorted {
                ($0.assets.first?.creationDate ?? .distantPast) > ($1.assets.first?.creationDate ?? .distantPast)
            }

            // 2. Filter cities by selected year/month
            let filtered = sortedCities.filter { city in
                guard let d = city.assets.first?.creationDate else { return false }
                let y = cal.component(.year, from: d)
                let m = cal.component(.month, from: d)
                if let sy = year, sy != y { return false }
                if let sm = month, sm != m { return false }
                return true
            }

            // 3. Group by month
            var groups: [String: [LocationGroup]] = [:]
            var orderMap: [String: Date] = [:]

            let monthFormatter = DateFormatter()
            monthFormatter.dateFormat = "MMM yyyy"

            for city in filtered {
                guard let d = city.assets.first?.creationDate else { continue }
                let key = monthFormatter.string(from: d)
                groups[key, default: []].append(city)
                if orderMap[key] == nil { orderMap[key] = d }
            }

            let sortedGroups = groups.sorted {
                (orderMap[$0.key] ?? .distantPast) > (orderMap[$1.key] ?? .distantPast)
            }

            // 4. Compute location markers for this filtered set
            let markers = filtered.compactMap { group -> LocationMarker? in
                guard let asset = group.assets.first(where: { $0.latitude != nil && $0.longitude != nil }),
                      let lat = asset.latitude, let lon = asset.longitude else { return nil }
                return LocationMarker(
                    name: group.name,
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    count: group.count,
                    firstAssetIdentifier: asset.localIdentifier
                )
            }

            return (sortedGroups, filtered.count, markers)
        }.value

        self.displayedGroups = result.groups
        self.displayedCitiesCount = result.count
        self.displayedMarkers = result.markers
        self.isProcessing = false

        self.fitMapToAllPins()
    }

    private func fitMapToAllPins() {
        let markers = displayedMarkers
        guard !markers.isEmpty else { return }
        if markers.count == 1 {
            mapRegion = MKCoordinateRegion(center: markers[0].coordinate,
                                           span: MKCoordinateSpan(latitudeDelta: 5, longitudeDelta: 5))
            return
        }
        let lats = markers.map(\.coordinate.latitude)
        let lons = markers.map(\.coordinate.longitude)
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLon = lons.min()!, maxLon = lons.max()!
        let center = CLLocationCoordinate2D(latitude: (minLat+maxLat)/2, longitude: (minLon+maxLon)/2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.5, 5),
            longitudeDelta: max((maxLon - minLon) * 1.5, 5)
        )
        withAnimation(.easeInOut(duration: 0.8)) { mapRegion = MKCoordinateRegion(center: center, span: span) }
    }
}

// MARK: - Skeleton Helpers
struct SkeletonRect: View {
    @State private var isAnimating = false
    let width: CGFloat?
    let height: CGFloat
    let cornerRadius: CGFloat

    init(width: CGFloat? = nil, height: CGFloat, cornerRadius: CGFloat = 8) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(UIColor.secondarySystemFill))
            .frame(width: width, height: height)
            .opacity(isAnimating ? 0.45 : 0.85)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
    }
}

struct TravelVlogSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Stats skeleton
            HStack(spacing: 10) {
                ForEach(0..<4) { _ in
                    SkeletonRect(height: 50, cornerRadius: 12)
                }
            }
            .padding(.horizontal, 16)

            // Chips row skeleton
            HStack(spacing: 8) {
                SkeletonRect(width: 50, height: 32, cornerRadius: 16)
                SkeletonRect(width: 70, height: 32, cornerRadius: 16)
                SkeletonRect(width: 70, height: 32, cornerRadius: 16)
                SkeletonRect(width: 70, height: 32, cornerRadius: 16)
            }
            .padding(.horizontal, 18)

            // Header skeleton
            HStack(spacing: 8) {
                SkeletonRect(width: 4, height: 20, cornerRadius: 2)
                SkeletonRect(width: 140, height: 20, cornerRadius: 4)
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)

            // Cards skeleton
            VStack(spacing: 16) {
                ForEach(0..<3) { _ in
                    HStack(alignment: .top, spacing: 0) {
                        // Spine circle
                        VStack(spacing: 0) {
                            SkeletonRect(width: 10, height: 10, cornerRadius: 5)
                                .padding(.top, 20)
                            Rectangle()
                                .fill(Color(UIColor.tertiarySystemFill))
                                .frame(width: 2)
                                .frame(maxHeight: .infinity)
                        }
                        .frame(width: 24)

                        // Main card body
                        VStack(alignment: .leading, spacing: 12) {
                            SkeletonRect(height: 108, cornerRadius: 14)
                            VStack(alignment: .leading, spacing: 6) {
                                SkeletonRect(width: 160, height: 14)
                                SkeletonRect(width: 100, height: 10)
                            }
                            .padding(.horizontal, 12)
                            .padding(.bottom, 12)
                        }
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(14)
                        .padding(.leading, 12)
                    }
                    .frame(height: 170)
                    .padding(.horizontal, 18)
                }
            }
        }
    }
}

// MARK: - Month Section Header
struct MonthSectionHeader: View {
    let label: String
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(Color(UIColor.systemGroupedBackground))
    }
}

// MARK: - Filter Chip
struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    isSelected
                    ? Color.purple
                    : Color(UIColor.secondarySystemGroupedBackground)
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(isSelected ? Color.clear : Color.black.opacity(0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Mini Stat
struct MiniStat: View {
    let icon: String
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.purple)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Compact Map Pin
struct CompactMapPin: View {
    let name: String
    let count: Int
    @State private var isPressed = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 30, height: 30)
                    .shadow(color: .purple.opacity(0.4), radius: 4, y: 2)
                Image(systemName: "camera.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
            }

            // Arrow tip
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 6, y: 7))
                path.addLine(to: CGPoint(x: 12, y: 0))
                path.closeSubpath()
            }
            .fill(Color.indigo)
            .frame(width: 12, height: 7)
            .offset(y: -1)

            Text(name.components(separatedBy: ",").first ?? name)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.55))
                .clipShape(Capsule())
        }
        .scaleEffect(isPressed ? 1.15 : 1.0)
        .animation(.spring(response: 0.2), value: isPressed)
    }
}

// MARK: - Trip Card
struct TripCard: View {
    let city: LocationGroup
    let isLast: Bool
    let appeared: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Spine
            VStack(spacing: 0) {
                Circle()
                    .fill(Color.purple)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .shadow(color: .purple.opacity(0.3), radius: 3)
                    .padding(.top, 20)
                if !isLast {
                    Rectangle()
                        .fill(LinearGradient(colors: [Color.purple.opacity(0.3), Color.purple.opacity(0.05)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 24)

            // Card
            NavigationLink(value: city) {
                VStack(alignment: .leading, spacing: 0) {
                    // Photo strip — 4 cells max
                    PhotoStrip(assets: Array(city.assets.prefix(4)), overflow: max(0, city.assets.count - 4))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(alignment: .topLeading) {
                            if let d = city.assets.first?.creationDate {
                                Text(fmtDay(d))
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(.ultraThinMaterial.opacity(0.85))
                                    .clipShape(Capsule())
                                    .padding(7)
                            }
                        }

                    // Text info
                    HStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(city.name)
                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            HStack(spacing: 8) {
                                Label("\(city.count)", systemImage: "photo")
                                    .font(.system(size: 11))
                                    .foregroundColor(.purple)
                                let f = ByteCountFormatter()
                                Text(f.string(fromByteCount: city.size))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.4))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.04), radius: 6, y: 3)
            }
            .buttonStyle(.plain)
            .padding(.leading, 12)
            .padding(.bottom, isLast ? 0 : 14)
        }
    }
}

// MARK: - Photo Strip (replaces TripPhotoCell + GeometryReader)
struct PhotoStrip: View {
    let assets: [AnalyzedAsset]
    let overflow: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(assets.enumerated()), id: \.element.localIdentifier) { i, asset in
                if i == assets.count - 1 && overflow > 0 {
                    OverflowCell(identifier: asset.localIdentifier, overflow: overflow)
                } else {
                    FastThumb(identifier: asset.localIdentifier, flex: i == 0 ? 1.7 : 1.0)
                }
            }
        }
        .frame(height: 108)
    }
}

// MARK: - Fast Thumb (no GeometryReader, fixed size)
struct FastThumb: View {
    let identifier: String
    let flex: Double
    @StateObject private var loader = CellImageLoader()

    var body: some View {
        Group {
            if let img = loader.image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color(UIColor.tertiarySystemFill))
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.secondary.opacity(0.3))
                            .font(.system(size: 14))
                    )
            }
        }
        .aspectRatio(flex, contentMode: .fill)
        .clipped()
        .onAppear { loader.load(identifier: identifier) }
        .onDisappear { loader.cancel() }
    }
}

// MARK: - Overflow Cell (last cell with +N badge)
struct OverflowCell: View {
    let identifier: String
    let overflow: Int
    @StateObject private var loader = CellImageLoader()

    var body: some View {
        ZStack {
            Group {
                if let img = loader.image {
                    Image(uiImage: img).resizable().scaledToFill().clipped()
                } else {
                    Rectangle().fill(Color(UIColor.tertiarySystemFill))
                }
            }
            Color.black.opacity(0.42)
            Text("+\(overflow)")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundColor(.white)
        }
        .aspectRatio(1, contentMode: .fill)
        .clipped()
        .onAppear { loader.load(identifier: identifier) }
        .onDisappear { loader.cancel() }
    }
}

// MARK: - City Detail View
struct CityDetailView: View {
    @EnvironmentObject var analyzer: PhotoAnalyzer
    let city: LocationGroup
    @State private var selectedAsset: AnalyzedAsset? = nil

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    Label("\(city.count) photos", systemImage: "photo.fill")
                        .font(.caption).foregroundColor(.purple)
                    Label(ByteCountFormatter().string(fromByteCount: city.size), systemImage: "internaldrive.fill")
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                    if let d = city.assets.first?.creationDate {
                        Text(fmtMonth(d)).font(.caption).foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)

                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(city.assets) { asset in
                        FastThumb(identifier: asset.localIdentifier, flex: 1.0)
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
