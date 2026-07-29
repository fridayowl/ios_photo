import SwiftUI
import Photos

struct PhotoListView: View {
    @EnvironmentObject var analyzer: PhotoAnalyzer
    @Binding var selectedFilter: AppFilter
    @State private var isSelectionMode = false
    @State private var selectedAssetIDs: Set<String> = []
    @State private var selectedAssetForDetail: AnalyzedAsset? = nil
    @State private var searchText = ""
    
    private var filteredAssets: [AnalyzedAsset] {
        let baseList: [AnalyzedAsset] = {
            switch selectedFilter {
            case .all:
                return analyzer.analyzedAssets
            case .giant:
                return analyzer.analyzedAssets.filter { $0.fileSize >= 100 * 1024 * 1024 }
            case .large:
                return analyzer.analyzedAssets.filter { $0.fileSize >= 10 * 1024 * 1024 && $0.fileSize < 100 * 1024 * 1024 }
            case .cloud:
                return analyzer.analyzedAssets.filter { $0.syncStatus == .syncedLocal || $0.syncStatus == .offloaded }
            case .screenshots:
                return analyzer.analyzedAssets.filter { $0.isScreenshot }
            case .similar:
                return []
            }
        }()
        
        if searchText.isEmpty {
            return baseList
        } else {
            return baseList.filter {
                $0.fileName.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    private var filteredSimilarGroups: [SimilarPhotoGroup] {
        if searchText.isEmpty {
            return analyzer.similarPhotosGroups
        } else {
            return analyzer.similarPhotosGroups.map { group in
                let matchingAssets = group.assets.filter {
                    $0.fileName.localizedCaseInsensitiveContains(searchText)
                }
                return SimilarPhotoGroup(keyAsset: group.keyAsset, assets: matchingAssets)
            }.filter { !$0.assets.isEmpty }
        }
    }
    
    private var allFilteredAssetIDs: Set<String> {
        if selectedFilter == .similar {
            return Set(filteredSimilarGroups.flatMap { $0.assets.map { $0.localIdentifier } })
        } else {
            return Set(filteredAssets.map { $0.localIdentifier })
        }
    }
    
    private var selectedAssetsSize: Int64 {
        analyzer.analyzedAssets
            .filter { selectedAssetIDs.contains($0.localIdentifier) }
            .reduce(0) { $0 + $1.fileSize }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter selector
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(AppFilter.allCases) { filter in
                            Button(action: {
                                selectedFilter = filter
                                selectedAssetIDs.removeAll()
                            }) {
                                Text(filter.rawValue)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(selectedFilter == filter ? Color.purple : Color.secondary.opacity(0.1))
                                    .foregroundColor(selectedFilter == filter ? .white : .secondary)
                                    .cornerRadius(20)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }
                .background(Color.cardBg)
                .overlay(
                    VStack {
                        Spacer()
                        Divider().background(Color.borderLight)
                    }
                )
                
                // List of files
                if selectedFilter == .similar {
                    if filteredSimilarGroups.isEmpty {
                        emptyStateView
                    } else {
                        List {
                            ForEach(filteredSimilarGroups) { group in
                                Section {
                                    ForEach(group.assets) { item in
                                        assetRow(for: item)
                                    }
                                } header: {
                                    HStack {
                                        Text("Duplicate Burst Group")
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundColor(.purple)
                                        Spacer()
                                        Text("Reclaim \(formatBytes(group.totalSize - (group.assets.first?.fileSize ?? 0))) if keeping one")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 4)
                                }
                                .listRowBackground(Color.cardBg)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                .listRowSeparatorTint(Color.borderLight)
                            }
                        }
                        .listStyle(.insetGrouped)
                        .scrollContentBackground(.hidden)
                        .background(Color.mainBg)
                    }
                } else {
                    if filteredAssets.isEmpty {
                        emptyStateView
                    } else {
                        List(filteredAssets) { analyzedAsset in
                            assetRow(for: analyzedAsset)
                                .listRowBackground(Color.cardBg)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                .listRowSeparatorTint(Color.borderLight)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .background(Color.mainBg)
                    }
                }
                
                // Bottom multi-select bar
                if isSelectionMode {
                    reclaimBar
                }
            }
            .navigationTitle("Library Cleanup")
            .searchable(text: $searchText, prompt: "Search filename or extension...")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isSelectionMode ? "Cancel" : "Select") {
                        isSelectionMode.toggle()
                        selectedAssetIDs.removeAll()
                    }
                    .foregroundColor(.purple)
                    .fontWeight(.semibold)
                }
                
                if isSelectionMode && !allFilteredAssetIDs.isEmpty {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(selectedAssetIDs.count == allFilteredAssetIDs.count ? "Deselect All" : "Select All") {
                            if selectedAssetIDs.count == allFilteredAssetIDs.count {
                                selectedAssetIDs.removeAll()
                            } else {
                                selectedAssetIDs = allFilteredAssetIDs
                            }
                        }
                        .foregroundColor(.purple)
                    }
                }
            }
            .sheet(item: $selectedAssetForDetail) { detailAsset in
                PhotoDetailView(analyzedAsset: detailAsset)
            }
        }
        .preferredColorScheme(.light)
    }
    
    // Empty state view when filters yield no files
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .foregroundColor(.secondary.opacity(0.3))
            
            Text("No Assets Found")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Text("No photos or videos match this cleanup filter category.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.mainBg)
    }
    
    // Rows representing assets
    private func assetRow(for item: AnalyzedAsset) -> some View {
        HStack(spacing: 12) {
            if isSelectionMode {
                Image(systemName: selectedAssetIDs.contains(item.localIdentifier) ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(selectedAssetIDs.contains(item.localIdentifier) ? .purple : .secondary)
                    .font(.title3)
                    .padding(.trailing, 4)
                    .transition(.move(edge: .leading))
            }
            
            // Async Thumbnail View
            PHAssetThumbnailView(assetIdentifier: item.localIdentifier)
                .frame(width: 60, height: 60)
                .cornerRadius(8)
                .clipped()
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.fileName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text(formatBytes(item.fileSize))
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.purple)
                    
                    switch item.syncStatus {
                    case .offloaded:
                        Image(systemName: "icloud.fill")
                            .font(.caption2)
                            .foregroundColor(.purple)
                    case .syncedLocal:
                        Image(systemName: "checkmark.icloud.fill")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    case .deviceOnly:
                        Image(systemName: "icloud.slash.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    
                    if item.isScreenshot {
                        Text("Screenshot")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.12))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }
                    
                    if item.mediaType == .video {
                        Text(formatDuration(item.duration))
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.12))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
                    }
                }
            }
            
            Spacer()
            
            if !isSelectionMode {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.4))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelectionMode {
                if selectedAssetIDs.contains(item.localIdentifier) {
                    selectedAssetIDs.remove(item.localIdentifier)
                } else {
                    selectedAssetIDs.insert(item.localIdentifier)
                }
            } else {
                selectedAssetForDetail = item
            }
        }
    }
    
    // Formatting video duration
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // Bottom selection details overlay
    private var reclaimBar: some View {
        VStack(spacing: 12) {
            Divider().background(Color.borderLight)
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(selectedAssetIDs.count) items selected")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Reclaim \(formatBytes(selectedAssetsSize))")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                Button(action: {
                    deleteSelectedAssets()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash.fill")
                        Text("Delete Selected")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(selectedAssetIDs.isEmpty ? Color.secondary.opacity(0.2) : Color.red)
                    .cornerRadius(12)
                    .shadow(color: selectedAssetIDs.isEmpty ? Color.clear : Color.red.opacity(0.2), radius: 6, y: 3)
                }
                .disabled(selectedAssetIDs.isEmpty)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .background(Color.cardBg)
        .transition(.move(edge: .bottom))
    }
    
    // Perform bulk deletion request
    private func deleteSelectedAssets() {
        let assetsToDelete = analyzer.analyzedAssets
            .filter { selectedAssetIDs.contains($0.localIdentifier) }
        
        Task {
            let success = await analyzer.deleteAssets(assetsToDelete)
            if success {
                selectedAssetIDs.removeAll()
                isSelectionMode = false
            }
        }
    }
}

// MARK: - PHAssetThumbnailView (Asynchronous, looking up cache map)
struct PHAssetThumbnailView: View {
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
                Color.secondary.opacity(0.1)
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.5)
                    )
            }
        }
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        guard let asset = analyzer.getPHAsset(for: assetIdentifier) else {
            // Simulated thumbnail
            self.image = UIImage(systemName: "photo")
            return
        }
        
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.isSynchronous = false
        options.isNetworkAccessAllowed = true
        
        manager.requestImage(
            for: asset,
            targetSize: CGSize(width: 120, height: 120),
            contentMode: .aspectFill,
            options: options
        ) { result, _ in
            if let result = result {
                self.image = result
            }
        }
    }
}
