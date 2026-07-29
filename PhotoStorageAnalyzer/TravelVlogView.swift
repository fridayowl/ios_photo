import SwiftUI
import MapKit
import Photos

// MARK: - TRAVEL VLOG VIEW
struct TravelVlogView: View {
    @EnvironmentObject var analyzer: PhotoAnalyzer
    
    @State private var isMapExpanded = false
    @State private var selectedAsset: AnalyzedAsset? = nil
    
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 30.0, longitude: 0.0),
        span: MKCoordinateSpan(latitudeDelta: 160.0, longitudeDelta: 160.0)
    )
    
    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
    
    private func formatMonthYear(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: date)
    }
    
    private func getTravelEmoji(for index: Int) -> String {
        let emojis = ["✈️", "🌴", "🗺️", "🏝️", "🏖️", "🏔️", "🗼", "🚗", "⛵"]
        return emojis[index % emojis.count]
    }
    
    var body: some View {
        NavigationStack {
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
                    
                    // 2. Travel Vlog Timeline (Vertical footprints diary style)
                    if !analyzer.locationsBreakdown.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("🗺️ Travel Vlog Timeline")
                                .font(.headline)
                                .foregroundColor(.primary)
                                .padding(.horizontal)
                            
                            VStack(spacing: 0) {
                                let timelineCities = analyzer.locationsBreakdown.sorted {
                                    ($0.assets.first?.creationDate ?? Date()) > ($1.assets.first?.creationDate ?? Date())
                                }
                                
                                ForEach(Array(timelineCities.enumerated()), id: \.element.name) { index, city in
                                    VStack(spacing: 0) {
                                        HStack(alignment: .center, spacing: 12) {
                                            // Vlog Photo Node
                                            ZStack {
                                                Circle()
                                                    .fill(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                                                    .frame(width: 52, height: 52)
                                                
                                                if let firstAsset = city.assets.first {
                                                    TimelineThumbnailView(assetIdentifier: firstAsset.localIdentifier)
                                                        .frame(width: 46, height: 46)
                                                        .clipShape(Circle())
                                                } else {
                                                    Image(systemName: "airplane")
                                                        .foregroundColor(.white)
                                                }
                                            }
                                            
                                            VStack(alignment: .leading, spacing: 4) {
                                                HStack(spacing: 4) {
                                                    Text(getTravelEmoji(for: index))
                                                    Text(city.name)
                                                        .font(.system(.subheadline, design: .rounded))
                                                        .fontWeight(.bold)
                                                        .foregroundColor(.primary)
                                                }
                                                
                                                HStack(spacing: 8) {
                                                    if let date = city.assets.first?.creationDate {
                                                        Label(formatMonthYear(date), systemImage: "calendar")
                                                            .font(.system(size: 9))
                                                            .foregroundColor(.secondary)
                                                    }
                                                    
                                                    Label("\(city.count) memories", systemImage: "photo")
                                                        .font(.system(size: 9))
                                                        .foregroundColor(.purple)
                                                }
                                            }
                                            
                                            Spacer()
                                            
                                            NavigationLink {
                                                cityGalleryView(cityName: city.name, assets: city.assets)
                                            } label: {
                                                Image(systemName: "chevron.right.circle.fill")
                                                    .font(.title2)
                                                    .foregroundColor(.purple)
                                                    .opacity(0.8)
                                            }
                                        }
                                        .padding()
                                        .background(Color.cardBg)
                                        .cornerRadius(16)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(Color.borderLight, lineWidth: 1)
                                        )
                                        .shadow(color: Color.black.opacity(0.01), radius: 6, y: 3)
                                        
                                        // Dash footprint connector line below card
                                        if index < timelineCities.count - 1 {
                                            VStack(spacing: 4) {
                                                ForEach(0..<3) { _ in
                                                    Circle()
                                                        .fill(Color.purple.opacity(0.35))
                                                        .frame(width: 4, height: 4)
                                                }
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.leading, 42)
                                            .padding(.vertical, 4)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    
                    // 3. Location Lists Row
                    Text("Locations List")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .padding(.horizontal)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(analyzer.locationsBreakdown) { city in
                            NavigationLink {
                                cityGalleryView(cityName: city.name, assets: city.assets)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(city.name)
                                            .font(.subheadline)
                                            .fontWeight(.bold)
                                            .foregroundColor(.primary)
                                        Text("\(city.count) items")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text(formatBytes(city.size))
                                        .font(.system(.subheadline, design: .rounded))
                                        .fontWeight(.bold)
                                        .foregroundColor(.purple)
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .background(Color.cardBg)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.borderLight, lineWidth: 1)
                                )
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Travel Vlog")
            .background(Color.mainBg)
            .sheet(isPresented: $isMapExpanded) {
                FullScreenMapView().environmentObject(analyzer)
            }
            .sheet(item: $selectedAsset) { asset in
                PhotoDetailView(analyzedAsset: asset)
                    .environmentObject(analyzer)
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
    
    private func cityGalleryView(cityName: String, assets: [AnalyzedAsset]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(assets) { asset in
                        ThumbnailCell(asset: asset, columnsCount: 3, fitToAspectRatio: false)
                            .onTapGesture {
                                selectedAsset = asset
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
