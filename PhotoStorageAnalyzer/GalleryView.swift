import SwiftUI
import Photos
import MapKit

// Container for sharing items sheet
struct ShareItemContainer: Identifiable {
    let id = UUID()
    let items: [Any]
}

// SwiftUI wrap of UIActivityViewController for AirDrop/Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct GalleryView: View {
    @EnvironmentObject var analyzer: PhotoAnalyzer
    
    @State private var gallerySegment = 0 // 0: Timeline, 1: Calendar, 2: Locations, 3: Albums
    @State private var columnsCount = 3
    @State private var fitToAspectRatio = false
    @State private var selectedAsset: AnalyzedAsset? = nil
    
    @State private var showingAddAlbumAlert = false
    @State private var newAlbumName = ""
    
    // Sharing states
    @State private var sharingItems: [Any]? = nil
    @State private var isPreparingShare = false
    @State private var isMapExpanded = false
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 30.0, longitude: 0.0),
        span: MKCoordinateSpan(latitudeDelta: 160.0, longitudeDelta: 160.0)
    )
    @State private var selectedCalendarDate: Date? = nil
    @State private var calendarDisplayMonth: Date = Date()
    
    @Namespace private var tabAnimation
    
    // Zoom control grid layout
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 4), count: columnsCount)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Premium Custom Capsule Picker
                HStack(spacing: 0) {
                    ForEach(0..<4) { index in
                        let titles = ["Timeline", "Calendar", "Locations", "Albums"]
                        let icons = ["clock.fill", "calendar", "map.fill", "folder.fill"]
                        Button(action: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                gallerySegment = index
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: icons[index])
                                    .font(.system(size: 11))
                                Text(titles[index])
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(gallerySegment == index ? .white : .secondary)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(
                                ZStack {
                                    if gallerySegment == index {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(
                                                LinearGradient(
                                                    gradient: Gradient(colors: [Color.purple, Color(red: 0.5, green: 0.2, blue: 0.85)]),
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .matchedGeometryEffect(id: "activeTab", in: tabAnimation)
                                            .shadow(color: Color.purple.opacity(0.3), radius: 4, x: 0, y: 2)
                                    }
                                }
                            )
                        }
                    }
                }
                .padding(4)
                .background(Color.darkCapsuleBg)
                .cornerRadius(10)
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)
                
                // Segment Contents
                Group {
                    switch gallerySegment {
                    case 0:
                        timelineGrid
                    case 1:
                        calendarTimeline
                    case 2:
                        locationsViewer
                    case 3:
                        albumsManager
                    default:
                        EmptyView()
                    }
                }
            }
            .navigationTitle("Photo Gallery")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color.mainBg)
            .sheet(isPresented: Binding(
                get: { selectedAsset != nil },
                set: { if !$0 { selectedAsset = nil } }
            )) {
                if let asset = selectedAsset {
                    PhotoDetailView(analyzedAsset: asset)
                }
            }
            .sheet(item: Binding(
                get: { sharingItems == nil ? nil : ShareItemContainer(items: sharingItems!) },
                set: { sharingItems = $0?.items }
            )) { container in
                ShareSheet(activityItems: container.items)
            }
            .overlay {
                if isPreparingShare {
                    ZStack {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                        
                        VStack(spacing: 16) {
                            ProgressView()
                                .tint(.purple)
                                .scaleEffect(1.4)
                            Text("Preparing photos for sharing...")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundColor(.primary)
                                .fontWeight(.semibold)
                        }
                        .padding(28)
                        .background(Color.cardBg)
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.borderLight, lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.05), radius: 10, y: 4)
                    }
                }
            }
        }
    }
    
    // Format helpers
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
    
    private func formatDateDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    // Share Background Loader
    private func fetchImage(for phAsset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let manager = PHImageManager.default()
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.isSynchronous = true
            
            manager.requestImage(
                for: phAsset,
                targetSize: CGSize(width: 800, height: 800),
                contentMode: .aspectFit,
                options: options
            ) { result, _ in
                continuation.resume(returning: result)
            }
        }
    }
    
    // Share Background Loader
    private func shareAssets(_ assets: [AnalyzedAsset]) {
        isPreparingShare = true
        
        Task {
            var imagesToShare: [UIImage] = []
            
            for asset in assets {
                if let phAsset = analyzer.getPHAsset(for: asset.localIdentifier) {
                    if let image = await fetchImage(for: phAsset) {
                        imagesToShare.append(image)
                    }
                }
            }
            
            await MainActor.run {
                isPreparingShare = false
                if !imagesToShare.isEmpty {
                    sharingItems = imagesToShare
                }
            }
        }
    }
}

// MARK: - TIMELINE VIEW
extension GalleryView {
    private var timelineGrid: some View {
        VStack(spacing: 0) {
            // Floating Pro Control Panel
            HStack(spacing: 12) {
                // Zoom Slider
                HStack {
                    Image(systemName: "minus.magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 11))
                    
                    Slider(value: Binding(
                        get: { Double(columnsCount) },
                        set: { columnsCount = Int($0.rounded()) }
                    ), in: 2...5, step: 1)
                    .tint(.purple)
                    
                    Image(systemName: "plus.magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 11))
                }
                
                Divider()
                    .frame(height: 18)
                    .background(Color.borderLight)
                
                // Crop Aspect Toggle Button
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        fitToAspectRatio.toggle()
                    }
                }) {
                    Image(systemName: fitToAspectRatio ? "square.dashed" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(fitToAspectRatio ? .white : .primary)
                        .padding(8)
                        .background(fitToAspectRatio ? Color.purple : Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                        .shadow(color: fitToAspectRatio ? Color.purple.opacity(0.35) : Color.clear, radius: 4)
                }
                
                Text("\(columnsCount) cols")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 45)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.cardBg)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.borderLight, lineWidth: 1)
            )
            .padding(.horizontal)
            .padding(.bottom, 8)
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
                    let grouped = groupAssetsByDay(analyzer.analyzedAssets)
                    ForEach(grouped, id: \.0) { date, items in
                        Section(header: SectionHeader(title: formatDateDay(date))) {
                            LazyVGrid(columns: columns, spacing: 4) {
                                ForEach(items) { item in
                                    ThumbnailCell(asset: item, columnsCount: columnsCount, fitToAspectRatio: fitToAspectRatio)
                                        .onTapGesture {
                                            selectedAsset = item
                                        }
                                        .contextMenu {
                                            gridCellContextMenu(for: item)
                                        }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func groupAssetsByDay(_ assets: [AnalyzedAsset]) -> [(Date, [AnalyzedAsset])] {
        let calendar = Calendar.current
        var groups: [Date: [AnalyzedAsset]] = [:]
        for asset in assets {
            guard let date = asset.creationDate else { continue }
            let dayStart = calendar.startOfDay(for: date)
            groups[dayStart, default: []].append(asset)
        }
        return groups.sorted(by: { $0.key > $1.key })
    }
}

// MARK: - CALENDAR VIEW (Collapsible monthly grids)
extension GalleryView {
    struct CollapsibleMonthSection: View {
        let monthName: String
        let assets: [AnalyzedAsset]
        let columns: [GridItem]
        let columnsCount: Int
        let fitToAspectRatio: Bool
        @Binding var selectedAsset: AnalyzedAsset?
        let contextMenuProvider: (AnalyzedAsset) -> AnyView
        
        @State private var isExpanded = true
        
        var body: some View {
            VStack(spacing: 0) {
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                }) {
                    HStack {
                        Image(systemName: "calendar")
                            .foregroundColor(.purple)
                        Text(monthName)
                            .font(.system(.headline, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        Spacer()
                        Text("\(assets.count) items")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.cardBg)
                }
                
                if isExpanded {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(assets) { asset in
                            ThumbnailCell(asset: asset, columnsCount: columnsCount, fitToAspectRatio: fitToAspectRatio)
                                .onTapGesture {
                                    selectedAsset = asset
                                }
                                .contextMenu {
                                    contextMenuProvider(asset)
                                }
                        }
                    }
                    .padding(4)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.borderLight, lineWidth: 1)
            )
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
    }
    
    private var calendarTimeline: some View {
        ScrollView {
            VStack(spacing: 0) {
                // MARK: Calendar Picker
                VStack(spacing: 0) {
                    // Month navigation header
                    HStack {
                        Button(action: { shiftMonth(-1) }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.purple)
                                .padding(8)
                                .background(Color.purple.opacity(0.08))
                                .clipShape(Circle())
                        }
                        
                        Spacer()
                        
                        Text(monthYearString(calendarDisplayMonth))
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Button(action: { shiftMonth(1) }) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.purple)
                                .padding(8)
                                .background(Color.purple.opacity(0.08))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    
                    // Weekday labels
                    HStack(spacing: 0) {
                        ForEach(["S","M","T","W","T","F","S"], id: \.self) { d in
                            Text(d)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
                    
                    // Day grid
                    let days = calendarDays(for: calendarDisplayMonth)
                    let photoDates = photoDatesInMonth(calendarDisplayMonth)
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                        ForEach(days, id: \.self) { day in
                            if let day = day {
                                let hasPhotos = photoDates.contains(day)
                                let isSelected = selectedCalendarDate.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false
                                let isToday = Calendar.current.isDateInToday(day)
                                
                                Button(action: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        selectedCalendarDate = isSelected ? nil : day
                                    }
                                }) {
                                    VStack(spacing: 2) {
                                        Text(dayNumber(day))
                                            .font(.system(size: 14, weight: isToday || isSelected ? .bold : .regular))
                                            .foregroundColor(
                                                isSelected ? .white :
                                                isToday ? .purple :
                                                hasPhotos ? .primary : .secondary.opacity(0.45)
                                            )
                                            .frame(width: 32, height: 32)
                                            .background(
                                                Group {
                                                    if isSelected {
                                                        Circle().fill(Color.purple)
                                                    } else if isToday {
                                                        Circle().fill(Color.purple.opacity(0.12))
                                                    } else {
                                                        Circle().fill(Color.clear)
                                                    }
                                                }
                                            )
                                        
                                        // Dot if photos exist on this day
                                        Circle()
                                            .fill(hasPhotos ? (isSelected ? Color.white.opacity(0.7) : Color.purple) : Color.clear)
                                            .frame(width: 4, height: 4)
                                    }
                                }
                                .buttonStyle(.plain)
                            } else {
                                Color.clear.frame(height: 44)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                }
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.top, 12)
                
                // MARK: Photos for selected day OR month list
                if let selectedDate = selectedCalendarDate {
                    // Show photos for selected day
                    let dayAssets = assetsForDate(selectedDate)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(fullDayString(selectedDate))
                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(dayAssets.count) photos")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        
                        if dayAssets.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "photo.slash")
                                    .font(.system(size: 36))
                                    .foregroundColor(.secondary.opacity(0.4))
                                Text("No photos on this day")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            LazyVGrid(columns: columns, spacing: 4) {
                                ForEach(dayAssets) { asset in
                                    ThumbnailCell(asset: asset, columnsCount: columnsCount, fitToAspectRatio: fitToAspectRatio)
                                        .onTapGesture { selectedAsset = asset }
                                        .contextMenu { gridCellContextMenu(for: asset) }
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                } else {
                    // Show all months
                    LazyVStack(spacing: 6) {
                        let grouped = groupAssetsByMonth(analyzer.analyzedAssets)
                        ForEach(grouped, id: \.0) { monthName, items in
                            CollapsibleMonthSection(
                                monthName: monthName,
                                assets: items,
                                columns: columns,
                                columnsCount: columnsCount,
                                fitToAspectRatio: fitToAspectRatio,
                                selectedAsset: $selectedAsset,
                                contextMenuProvider: { AnyView(gridCellContextMenu(for: $0)) }
                            )
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
    }
    
    // MARK: Calendar helpers
    private func shiftMonth(_ delta: Int) {
        withAnimation(.easeInOut(duration: 0.25)) {
            calendarDisplayMonth = Calendar.current.date(byAdding: .month, value: delta, to: calendarDisplayMonth) ?? calendarDisplayMonth
            selectedCalendarDate = nil
        }
    }
    
    private func monthYearString(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f.string(from: date)
    }
    
    private func fullDayString(_ date: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .long; return f.string(from: date)
    }
    
    private func dayNumber(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "d"; return f.string(from: date)
    }
    
    private func calendarDays(for month: Date) -> [Date?] {
        let cal = Calendar.current
        guard let range = cal.range(of: .day, in: .month, for: month),
              let firstDay = cal.date(from: cal.dateComponents([.year, .month], from: month)) else { return [] }
        let weekdayOffset = (cal.component(.weekday, from: firstDay) - cal.firstWeekday + 7) % 7
        var days: [Date?] = Array(repeating: nil, count: weekdayOffset)
        for day in range {
            days.append(cal.date(byAdding: .day, value: day - 1, to: firstDay))
        }
        // Pad to complete final row
        while days.count % 7 != 0 { days.append(nil) }
        return days
    }
    
    private func photoDatesInMonth(_ month: Date) -> Set<Date> {
        let cal = Calendar.current
        var result: Set<Date> = []
        for asset in analyzer.analyzedAssets {
            guard let d = asset.creationDate,
                  cal.isDate(d, equalTo: month, toGranularity: .month) else { continue }
            if let normalized = cal.date(from: cal.dateComponents([.year, .month, .day], from: d)) {
                result.insert(normalized)
            }
        }
        return result
    }
    
    private func assetsForDate(_ date: Date) -> [AnalyzedAsset] {
        let cal = Calendar.current
        return analyzer.analyzedAssets.filter { asset in
            guard let d = asset.creationDate else { return false }
            return cal.isDate(d, inSameDayAs: date)
        }
    }
    
    private func groupAssetsByMonth(_ assets: [AnalyzedAsset]) -> [(String, [AnalyzedAsset])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        var groups: [String: [AnalyzedAsset]] = [:]
        var order: [String: Date] = [:]
        for asset in assets {
            guard let date = asset.creationDate else { continue }
            let key = formatter.string(from: date)
            groups[key, default: []].append(asset)
            if order[key] == nil { order[key] = date }
        }
        return groups.sorted(by: { (order[$0.key] ?? Date()) > (order[$1.key] ?? Date()) })
    }
}

// MARK: - LOCATIONS VIEW
struct LocationMarker: Identifiable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
    let count: Int
    let firstAssetIdentifier: String
}

struct CityMapPin: View {
    @EnvironmentObject var analyzer: PhotoAnalyzer
    let assetIdentifier: String
    let count: Int
    
    @State private var image: UIImage? = nil
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let image = image {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Color.purple.opacity(0.12)
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundColor(.purple)
                            )
                    }
                }
                .frame(width: 46, height: 46)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                
                // Count badge overlay
                Text("\(count)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.purple)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.white, lineWidth: 1)
                    )
                    .offset(x: 4, y: 4)
            }
        }
        .onAppear {
            loadPinThumbnail()
        }
    }
    
    private func loadPinThumbnail() {
        guard let asset = analyzer.getPHAsset(for: assetIdentifier) else {
            return
        }
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.isSynchronous = false
        manager.requestImage(
            for: asset,
            targetSize: CGSize(width: 100, height: 100),
            contentMode: .aspectFill,
            options: options
        ) { result, _ in
            if let result = result {
                self.image = result
            }
        }
    }
}

extension GalleryView {
    private var locationMarkers: [LocationMarker] {
        var markers: [LocationMarker] = []
        for group in analyzer.locationsBreakdown {
            if let firstAsset = group.assets.first(where: { $0.latitude != nil && $0.longitude != nil }) {
                markers.append(LocationMarker(
                    name: group.name,
                    coordinate: CLLocationCoordinate2D(latitude: firstAsset.latitude!, longitude: firstAsset.longitude!),
                    count: group.count,
                    firstAssetIdentifier: firstAsset.localIdentifier
                ))
            }
        }
        return markers
    }

    private func formatMonthYear(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: date)
    }

    private var locationsViewer: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Interactive Custom Pin Map View
                ZStack(alignment: .topTrailing) {
                    Map(coordinateRegion: $mapRegion, annotationItems: locationMarkers) { marker in
                        MapAnnotation(coordinate: marker.coordinate) {
                            NavigationLink {
                                if let cityGroup = analyzer.locationsBreakdown.first(where: { $0.name == marker.name }) {
                                    cityGalleryView(cityName: cityGroup.name, assets: cityGroup.assets)
                                }
                            } label: {
                                CityMapPin(assetIdentifier: marker.firstAssetIdentifier, count: marker.count)
                            }
                        }
                    }
                    .frame(height: 200)
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.borderLight, lineWidth: 1)
                    )
                    .onAppear {
                        if let first = locationMarkers.first {
                            mapRegion = MKCoordinateRegion(
                                center: first.coordinate,
                                span: MKCoordinateSpan(latitudeDelta: 30.0, longitudeDelta: 30.0)
                            )
                        }
                    }
                    
                    // Expand Map Button
                    Button(action: {
                        isMapExpanded = true
                    }) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right.circle.fill")
                            .font(.title)
                            .foregroundColor(.purple)
                            .background(Circle().fill(Color.white))
                            .shadow(color: .black.opacity(0.15), radius: 4)
                    }
                    .padding(12)
                }
                .padding(.horizontal)
                .padding(.top, 10)
                
                // 1. City Explorer Horizontal Carousel
                Text("City Explorer")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .padding(.horizontal)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(analyzer.locationsBreakdown) { city in
                            NavigationLink {
                                cityGalleryView(cityName: city.name, assets: city.assets)
                            } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Image(systemName: "mappin.circle.fill")
                                            .foregroundColor(.purple)
                                            .font(.title3)
                                        Spacer()
                                        Text("\(city.count) items")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Text(city.name)
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    
                                    HStack {
                                        Text(formatBytes(city.size))
                                            .font(.system(.caption, design: .rounded))
                                            .fontWeight(.bold)
                                            .foregroundColor(.purple)
                                        Spacer()
                                        
                                        let cloudCount = city.assets.filter { $0.syncStatus == .syncedLocal || $0.syncStatus == .offloaded }.count
                                        let healthRatio = city.count > 0 ? Double(cloudCount) / Double(city.count) : 0.0
                                        Text("\(Int(healthRatio * 100))% Synced")
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundColor(.green)
                                    }
                                }
                                .padding(14)
                                .frame(width: 160, height: 110)
                                .background(Color.cardBg)
                                .cornerRadius(14)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.borderLight, lineWidth: 1)
                                )
                                .shadow(color: Color.black.opacity(0.01), radius: 4, y: 2)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                // "Open Travel Vlog" prompt card
                NavigationLink {
                    TravelVlogView().environmentObject(analyzer)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "map.fill")
                            .font(.title3)
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(
                                LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Travel Vlog")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                            Text("View your full journey timeline")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(14)
                    .background(Color.cardBg)
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.borderLight, lineWidth: 1)
                    )
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $isMapExpanded) {
            FullScreenMapView().environmentObject(analyzer)
        }
    }
    
    private func getTravelEmoji(for index: Int) -> String {
        let emojis = ["✈️", "🌴", "🗺️", "🏝️", "🏖️", "🏔️", "🗼", "🚗", "⛵"]
        return emojis[index % emojis.count]
    }
    
    private func cityGalleryView(cityName: String, assets: [AnalyzedAsset]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Share Location Photos Button
                HStack {
                    Spacer()
                    if !assets.isEmpty {
                        Button(action: {
                            shareAssets(assets)
                        }) {
                            Label("Share Location Photos", systemImage: "square.and.arrow.up")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.purple)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.purple.opacity(0.12))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                                )
                        }
                    }
                }
                .padding(.horizontal)
                
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(assets) { asset in
                        ThumbnailCell(asset: asset, columnsCount: columnsCount, fitToAspectRatio: fitToAspectRatio)
                            .onTapGesture {
                                selectedAsset = asset
                            }
                            .contextMenu {
                                gridCellContextMenu(for: asset)
                            }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(cityName)
        .background(Color.mainBg)
    }
}

// MARK: - ALBUMS & FAVORITES VIEW
extension GalleryView {
    private var albumsManager: some View {
        VStack(spacing: 0) {
            // Add Album Button
            Button(action: {
                showingAddAlbumAlert = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("Create New Album")
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.purple, Color(red: 0.5, green: 0.2, blue: 0.85)]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
                .shadow(color: Color.purple.opacity(0.25), radius: 8, x: 0, y: 4)
            }
            .padding()
            
            // Stacked Folder Card Albums List
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20)], spacing: 20) {
                    ForEach(analyzer.customAlbums) { album in
                        NavigationLink {
                            albumGalleryView(album: album)
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                // Stacked multi-layer folder deck
                                ZStack {
                                    // Layer 3 (Back)
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.secondary.opacity(0.1))
                                        .offset(x: 6, y: -6)
                                        .opacity(0.5)
                                    
                                    // Layer 2 (Middle)
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.secondary.opacity(0.15))
                                        .offset(x: 3, y: -3)
                                        .opacity(0.8)
                                    
                                    // Layer 1 (Front Preview)
                                    ZStack {
                                        Color.secondary.opacity(0.2)
                                            .cornerRadius(12)
                                        
                                        if let firstId = album.assetIdentifiers.first,
                                           let asset = analyzer.analyzedAssets.first(where: { $0.id == firstId }) {
                                            ThumbnailCell(asset: asset, columnsCount: 4, fitToAspectRatio: false)
                                                .cornerRadius(12)
                                        } else {
                                            Image(systemName: "photo.on.rectangle.angled")
                                                .foregroundColor(.secondary)
                                                .font(.system(size: 24))
                                        }
                                    }
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.borderLight, lineWidth: 1)
                                    )
                                }
                                .aspectRatio(1.0, contentMode: .fit)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(album.name)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.primary)
                                    Text("\(album.assetIdentifiers.count) items")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.leading, 4)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .alert("New Album", isPresented: $showingAddAlbumAlert) {
            TextField("Album Name", text: $newAlbumName)
            Button("Create") {
                if !newAlbumName.isEmpty {
                    analyzer.createAlbum(name: newAlbumName)
                    newAlbumName = ""
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a name for this custom album.")
        }
    }
    
    private func albumGalleryView(album: CustomAlbum) -> some View {
        let assets = analyzer.analyzedAssets.filter { album.assetIdentifiers.contains($0.id) }
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    // Share Album Button
                    if !assets.isEmpty {
                        Button(action: {
                            shareAssets(assets)
                        }) {
                            Label("Share Album", systemImage: "square.and.arrow.up")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.purple)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.purple.opacity(0.12))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                                )
                        }
                    }
                    
                    Spacer()
                    
                    Button(role: .destructive) {
                        analyzer.deleteAlbum(id: album.id)
                    } label: {
                        Label("Delete Album", systemImage: "trash")
                            .font(.caption)
                    }
                    .foregroundColor(.red)
                }
                .padding(.horizontal)
                
                if assets.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.stack")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No items in this album yet")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Go to the gallery list and tap any image to add it here.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(assets) { asset in
                            ThumbnailCell(asset: asset, columnsCount: columnsCount, fitToAspectRatio: fitToAspectRatio)
                                .onTapGesture {
                                    selectedAsset = asset
                                }
                                .contextMenu {
                                    gridCellContextMenu(for: asset)
                                }
                        }
                    }
                }
            }
            .padding(.top)
        }
        .navigationTitle(album.name)
        .background(Color.mainBg)
    }
}

// MARK: - QUICK CONTEXT MENU BUILDER
extension GalleryView {
    @ViewBuilder
    private func gridCellContextMenu(for asset: AnalyzedAsset) -> some View {
        Button(action: {
            if let favAlbum = analyzer.customAlbums.first(where: { $0.name == "Favorites" }) {
                if favAlbum.assetIdentifiers.contains(asset.id) {
                    analyzer.removeAsset(asset.id, fromAlbum: favAlbum.id)
                } else {
                    analyzer.addAsset(asset.id, toAlbum: favAlbum.id)
                }
            }
        }) {
            let isFav = analyzer.customAlbums.first(where: { $0.name == "Favorites" })?.assetIdentifiers.contains(asset.id) ?? false
            Label(isFav ? "Remove from Favorites" : "Add to Favorites", systemImage: isFav ? "heart.fill" : "heart")
        }
        
        Button(action: {
            selectedAsset = asset
        }) {
            Label("Show Details", systemImage: "info.circle")
        }
        
        Button(role: .destructive, action: {
            Task {
                _ = await analyzer.deleteAssets([asset])
            }
        }) {
            Label("Delete Photo", systemImage: "trash")
        }
    }
}

// MARK: - STICKY FROSTED GLASS SECTION HEADER
struct SectionHeader: View {
    let title: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
            Spacer()
        }
        .background(.ultraThinMaterial)
    }
}

// MARK: - ASSET GRID THUMBNAIL (Adaptive Grid Card)
struct ThumbnailCell: View {
    @EnvironmentObject var analyzer: PhotoAnalyzer
    
    let asset: AnalyzedAsset
    let columnsCount: Int
    let fitToAspectRatio: Bool
    
    @State private var image: UIImage? = nil
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    Color.cardBg
                    
                    if let uiImage = image {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: fitToAspectRatio ? .fit : .fill)
                            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                            .clipped()
                    } else {
                        Image(systemName: asset.mediaType == .video ? "video" : "photo")
                            .foregroundColor(.secondary.opacity(0.3))
                    }
                }
                .aspectRatio(1.0, contentMode: .fit)
                
                // Type badge (Video duration / Live photo / Sync badges)
                HStack(spacing: 3) {
                    if asset.mediaType == .video {
                        Image(systemName: "play.fill")
                            .font(.system(size: 6))
                            .foregroundColor(.white)
                    }
                    
                    switch asset.syncStatus {
                    case .offloaded:
                        Image(systemName: "icloud.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.purple)
                    case .syncedLocal:
                        Image(systemName: "checkmark.icloud.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.blue)
                    case .deviceOnly:
                        Image(systemName: "icloud.slash.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.orange)
                    }
                }
                .padding(4)
                .background(Color.black.opacity(0.6))
                .cornerRadius(4)
                .padding(4)
            }
            .cornerRadius(columnsCount <= 2 ? 12 : 4)
            .overlay(
                RoundedRectangle(cornerRadius: columnsCount <= 2 ? 12 : 4)
                    .stroke(Color.borderLight, lineWidth: 1)
            )
            
            // Detailed Info Cards (if column count is 2 or less)
            if columnsCount <= 2 {
                VStack(alignment: .leading, spacing: 2) {
                    Text(asset.fileName)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    HStack {
                        Text(formatBytes(asset.fileSize))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.purple)
                        
                        if let loc = asset.locationName {
                            Text("• \(loc)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 6)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: columnsCount <= 2 ? 12 : 4)
                .fill(Color.cardBg)
        )
        .shadow(color: Color.black.opacity(0.02), radius: 4, x: 0, y: 2)
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        guard let phAsset = analyzer.getPHAsset(for: asset.localIdentifier) else {
            // Load mock icons in simulator
            image = UIImage(systemName: asset.mediaType == .video ? "video" : "photo")
            return
        }
        
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .fastFormat
        
        manager.requestImage(
            for: phAsset,
            targetSize: CGSize(width: 200, height: 200),
            contentMode: .aspectFill,
            options: options
        ) { result, _ in
            if let result = result {
                self.image = result
            }
        }
    }
}

// MARK: - TIMELINE THUMBNAIL (For Vlog Timeline Cards)
struct TimelineThumbnailView: View {
    @EnvironmentObject var analyzer: PhotoAnalyzer
    let assetIdentifier: String
    
    @State private var image: UIImage? = nil
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.purple.opacity(0.12)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.caption2)
                            .foregroundColor(.purple)
                    )
            }
        }
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        guard let phAsset = analyzer.getPHAsset(for: assetIdentifier) else {
            return
        }
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.isSynchronous = false
        
        manager.requestImage(
            for: phAsset,
            targetSize: CGSize(width: 100, height: 100),
            contentMode: .aspectFill,
            options: options
        ) { result, _ in
            if let result = result {
                self.image = result
            }
        }
    }
}

// MARK: - FULL SCREEN TRAVEL EXPLORER MAP
struct FullScreenMapView: View {
    @EnvironmentObject var analyzer: PhotoAnalyzer
    @Environment(\.dismiss) var dismiss
    
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 30.0, longitude: 0.0),
        span: MKCoordinateSpan(latitudeDelta: 160.0, longitudeDelta: 160.0)
    )
    
    @State private var sharingImage: UIImage? = nil
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Expanded Map
                Map(coordinateRegion: $region, annotationItems: locationMarkers) { marker in
                    MapAnnotation(coordinate: marker.coordinate) {
                        NavigationLink {
                            if let cityGroup = analyzer.locationsBreakdown.first(where: { $0.name == marker.name }) {
                                cityGalleryView(cityName: cityGroup.name, assets: cityGroup.assets)
                            }
                        } label: {
                            CityMapPin(assetIdentifier: marker.firstAssetIdentifier, count: marker.count)
                        }
                    }
                }
                .ignoresSafeArea(edges: .bottom)
                
                // Floating Actions
                HStack(spacing: 16) {
                    Button(action: {
                        shareMapScreenshot()
                    }) {
                        Label("Share Travel Map", systemImage: "square.and.arrow.up")
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                            .background(Color.purple)
                            .cornerRadius(14)
                            .shadow(color: .purple.opacity(0.3), radius: 8, y: 4)
                    }
                }
                .padding(.bottom, 36)
            }
            .navigationTitle("Travel Footprints Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(.purple)
                }
            }
            .sheet(item: Binding(
                get: { sharingImage == nil ? nil : ShareItemContainer(items: [sharingImage!]) },
                set: { sharingImage = $0?.items.first as? UIImage }
            )) { container in
                ShareSheet(activityItems: container.items)
            }
        }
    }
    
    private var locationMarkers: [LocationMarker] {
        var markers: [LocationMarker] = []
        for group in analyzer.locationsBreakdown {
            if let firstAsset = group.assets.first(where: { $0.latitude != nil && $0.longitude != nil }) {
                markers.append(LocationMarker(
                    name: group.name,
                    coordinate: CLLocationCoordinate2D(latitude: firstAsset.latitude!, longitude: firstAsset.longitude!),
                    count: group.count,
                    firstAssetIdentifier: firstAsset.localIdentifier
                ))
            }
        }
        return markers
    }
    
    private func shareMapScreenshot() {
        let renderView = VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("🗺️ My Travel Footprints")
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("\(analyzer.locationsBreakdown.count) Cities • \(analyzer.stats.totalCount) Photos Analyzed")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 24)
            
            // Map capture
            Map(coordinateRegion: .constant(region), annotationItems: locationMarkers) { marker in
                MapAnnotation(coordinate: marker.coordinate) {
                    CityMapPin(assetIdentifier: marker.firstAssetIdentifier, count: marker.count)
                }
            }
            .frame(width: 330, height: 330)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.borderLight, lineWidth: 1)
            )
            .padding(.horizontal, 20)
            
            VStack(spacing: 8) {
                Text("Cities Visited:")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                let names = analyzer.locationsBreakdown.map { $0.name.components(separatedBy: ",").first ?? $0.name }.joined(separator: " • ")
                Text(names)
                    .font(.caption2)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(width: 370)
        .background(Color.mainBg)
        .preferredColorScheme(.light)
        
        let renderer = ImageRenderer(content: renderView)
        renderer.scale = 3.0
        if let image = renderer.uiImage {
            self.sharingImage = image
        }
    }
    
    private func cityGalleryView(cityName: String, assets: [AnalyzedAsset]) -> some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                ForEach(assets) { asset in
                    ZStack {
                        Color.cardBg
                        Image(systemName: asset.mediaType == .video ? "video" : "photo")
                            .foregroundColor(.secondary.opacity(0.3))
                    }
                    .aspectRatio(1.0, contentMode: .fit)
                }
            }
            .padding()
        }
        .navigationTitle(cityName)
        .background(Color.mainBg)
    }
}
