import SwiftUI
import Photos
import MapKit

struct PhotoDetailView: View {
    @EnvironmentObject var analyzer: PhotoAnalyzer
    @Environment(\.dismiss) var dismiss
    let analyzedAsset: AnalyzedAsset
    
    @State private var fullResolutionImage: UIImage? = nil
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0.0
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
    
    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Preview Container
                    previewContainer
                        .frame(maxHeight: 350)
                        .cornerRadius(16)
                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                        .padding(.horizontal)
                        .padding(.top, 10)
                    
                    // Metadata list card
                    metadataCard
                        .padding(.horizontal)
                    
                    // Map view for location metadata (if coordinates are present)
                    if let lat = analyzedAsset.latitude, let lon = analyzedAsset.longitude {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Location Metadata")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Map(coordinateRegion: .constant(MKCoordinateRegion(
                                center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                            )), annotationItems: [analyzedAsset]) { item in
                                MapMarker(coordinate: CLLocationCoordinate2D(latitude: item.latitude!, longitude: item.longitude!), tint: .purple)
                            }
                            .frame(height: 180)
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.borderLight, lineWidth: 1)
                            )
                        }
                        .padding(.horizontal)
                    }
                    
                    // Custom Album Membership Card
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Add to Albums")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .padding(.bottom, 2)
                        
                        ForEach(analyzer.customAlbums) { album in
                            let isInAlbum = album.assetIdentifiers.contains(analyzedAsset.id)
                            Button(action: {
                                if isInAlbum {
                                    analyzer.removeAsset(analyzedAsset.id, fromAlbum: album.id)
                                } else {
                                    analyzer.addAsset(analyzedAsset.id, toAlbum: album.id)
                                }
                            }) {
                                HStack {
                                    Image(systemName: album.name == "Favorites" ? "heart.fill" : "folder.fill")
                                        .foregroundColor(album.name == "Favorites" ? .red : .purple)
                                    Text(album.name)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: isInAlbum ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(isInAlbum ? .purple : .gray)
                                }
                                .padding(.vertical, 8)
                                Divider().background(Color.borderLight)
                            }
                        }
                    }
                    .padding(20)
                    .background(Color.cardBg)
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.borderLight, lineWidth: 1)
                    )
                    .padding(.horizontal)
                    
                    // Delete Button
                    Button(action: {
                        deleteAsset()
                    }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Photo")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .cornerRadius(14)
                        .shadow(color: .red.opacity(0.2), radius: 6, y: 3)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                }
            }
            .navigationTitle("Asset Inspector")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color.mainBg)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(.purple)
                }
            }
            .onAppear {
                loadFullImage()
            }
        }
        .preferredColorScheme(.light)
    }
    
    // Preview image / video container
    private var previewContainer: some View {
        ZStack {
            Color.black
            
            if let uiImage = fullResolutionImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if isDownloading {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                    Text("Downloading from iCloud...")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
    }
    
    // Metadata Details
    private var metadataCard: some View {
        VStack(spacing: 16) {
            infoRow(title: "Filename", value: analyzedAsset.fileName)
            infoRow(title: "Size", value: formatBytes(analyzedAsset.fileSize))
            
            let dimensions: String = {
                if let asset = analyzer.getPHAsset(for: analyzedAsset.localIdentifier) {
                    return "\(asset.pixelWidth) × \(asset.pixelHeight)"
                } else {
                    return "1920 × 1080"
                }
            }()
            infoRow(title: "Dimensions", value: dimensions)
            
            infoRow(title: "Created On", value: formatDate(analyzedAsset.creationDate))
            infoRow(
                title: "Location State",
                value: analyzedAsset.isLocallyAvailable ? "On Device" : "iCloud Only (Offloaded)",
                valueColor: analyzedAsset.isLocallyAvailable ? .green : .cyan
            )
            
            if analyzedAsset.mediaType == .video {
                infoRow(title: "Duration", value: formatDuration(analyzedAsset.duration))
            }
            
            infoRow(
                title: "Media Subtype",
                value: analyzedAsset.isScreenshot ? "Screenshot" : (analyzedAsset.isLivePhoto ? "Live Photo" : "Standard")
            )
        }
        .padding(20)
        .background(Color.cardBg)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.borderLight, lineWidth: 1)
        )
    }
    
    private func infoRow(title: String, value: String, valueColor: Color = .primary) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(valueColor)
                .multilineTextAlignment(.trailing)
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func loadFullImage() {
        guard let asset = analyzer.getPHAsset(for: analyzedAsset.localIdentifier) else {
            isDownloading = true
            Task {
                try? await Task.sleep(nanoseconds: 800_000_000)
                DispatchQueue.main.async {
                    self.isDownloading = false
                    self.fullResolutionImage = UIImage(systemName: analyzedAsset.mediaType == .video ? "video" : "photo")
                }
            }
            return
        }
        
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true // Trigger iCloud download if necessary
        options.deliveryMode = .highQualityFormat
        
        isDownloading = true
        
        options.progressHandler = { progress, _, _, _ in
            DispatchQueue.main.async {
                self.downloadProgress = progress
            }
        }
        
        manager.requestImage(
            for: asset,
            targetSize: CGSize(width: 800, height: 800),
            contentMode: .aspectFit,
            options: options
        ) { result, _ in
            DispatchQueue.main.async {
                self.isDownloading = false
                if let result = result {
                    self.fullResolutionImage = result
                }
            }
        }
    }
    
    private func deleteAsset() {
        Task {
            let success = await analyzer.deleteAssets([analyzedAsset])
            if success {
                dismiss()
            }
        }
    }
}
