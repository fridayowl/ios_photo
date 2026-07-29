import SwiftUI
import Photos

struct DashboardView: View {
    @EnvironmentObject var analyzer: PhotoAnalyzer
    @Binding var selectedTab: Int
    @Binding var selectedFilter: AppFilter
    
    @State private var showingInsights = false
    
    // Helpers to format sizes
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
    
    // Find counts and sizes for recommendations
    private var giantFilesCount: Int {
        analyzer.analyzedAssets.filter { $0.fileSize >= 100 * 1024 * 1024 }.count
    }
    private var giantFilesSize: Int64 {
        analyzer.analyzedAssets.filter { $0.fileSize >= 100 * 1024 * 1024 }.reduce(0) { $0 + $1.fileSize }
    }
    
    private var largeFilesCount: Int {
        analyzer.analyzedAssets.filter { $0.fileSize >= 10 * 1024 * 1024 && $0.fileSize < 100 * 1024 * 1024 }.count
    }
    private var largeFilesSize: Int64 {
        analyzer.analyzedAssets.filter { $0.fileSize >= 10 * 1024 * 1024 && $0.fileSize < 100 * 1024 * 1024 }.reduce(0) { $0 + $1.fileSize }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header card with circular space summary
                    storageSummaryCard
                    
                    // Detailed insights button
                    Button(action: { showingInsights = true }) {
                        HStack {
                            Label("Detailed Storage Insights", systemImage: "chart.bar.doc.horizontal")
                                .font(.subheadline)
                                .fontWeight(.bold)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                        }
                        .foregroundColor(.purple)
                        .padding()
                        .background(Color.purple.opacity(0.08))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                        )
                    }
                    
                    // iCloud Status Card
                    iCloudStatusCard
                    
                    // Recommendations for cleanup
                    cleanupRecommendationsCard
                    
                    // Grid for media breakdowns
                    mediaBreakdownGrid
                    
                    // Monthly Breakdown
                    monthlyBreakdownCard
                    
                    // Additional info / Re-scan button
                    Button(action: {
                        Task {
                            await analyzer.startScan()
                        }
                    }) {
                        Label("Re-scan Library", systemImage: "arrow.clockwise")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .padding(.top, 10)
                }
                .padding()
            }
            .navigationTitle("Analytics")
            .background(Color.mainBg)
            .sheet(isPresented: $showingInsights) {
                StorageInsightsSheet()
            }
        }
    }
    
    // 1. Core storage summary view (Hero visualizer)
    private var storageSummaryCard: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TOTAL GALLERY SIZE")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                    Text(formatBytes(analyzer.stats.totalSize))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }
                Spacer()
                
                Image(systemName: "chart.pie.fill")
                    .font(.title)
                    .foregroundStyle(.linearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            
            // Sub-info
            HStack {
                Text("\(analyzer.stats.totalCount) items total • \(analyzer.stats.imageCount) Photos • \(analyzer.stats.videoCount) Videos")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text("Images & Videos")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.purple.opacity(0.12))
                    .cornerRadius(6)
                    .foregroundColor(.purple)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.cardBg)
                .shadow(color: .black.opacity(0.03), radius: 10, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.borderLight, lineWidth: 1)
        )
    }
    
    // 2. Local vs iCloud distribution bar chart
    private var iCloudStatusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("iCloud Sync Status")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("\(analyzer.stats.iCloudPhotosCount) items in iCloud (\(formatBytes(analyzer.stats.iCloudPhotosSize)))")
                        .font(.caption2)
                        .foregroundColor(.purple)
                }
                Spacer()
            }
            
            // Bar graph
            let localSize = analyzer.stats.localSize
            let cloudSize = analyzer.stats.cloudSize
            let total = localSize + cloudSize
            
            let localRatio = total > 0 ? CGFloat(localSize) / CGFloat(total) : 0.5
            let cloudRatio = total > 0 ? CGFloat(cloudSize) / CGFloat(total) : 0.5
            
            GeometryReader { geo in
                HStack(spacing: 0) {
                    if localSize > 0 {
                        Rectangle()
                            .fill(LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * localRatio)
                    }
                    if cloudSize > 0 {
                        Rectangle()
                            .fill(LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * cloudRatio)
                    }
                }
            }
            .frame(height: 8)
            .cornerRadius(4)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(4)
            
            // Legend
            HStack {
                VStack(alignment: .leading) {
                    HStack(spacing: 4) {
                        Circle().fill(Color.blue).frame(width: 8, height: 8)
                        Text("On Device (Local)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Text(formatBytes(localSize))
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    Text("\(analyzer.stats.localCount) files")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    HStack(spacing: 4) {
                        Text("iCloud Only (Offloaded)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Circle().fill(Color.purple).frame(width: 8, height: 8)
                    }
                    Text(formatBytes(cloudSize))
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    Text("\(analyzer.stats.cloudCount) files")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.cardBg)
                .shadow(color: .black.opacity(0.03), radius: 10, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.borderLight, lineWidth: 1)
        )
    }
    
    // 3. Storage Optimizations list
    private var cleanupRecommendationsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Storage Optimizations")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(spacing: 12) {
                // Duplicates Recommendation
                let dupCount = analyzer.similarPhotosGroups.count
                let dupSize = analyzer.similarPhotosGroups.reduce(0) { $0 + $1.totalSize }
                
                RecommendationRow(
                    icon: "doc.on.doc.fill",
                    iconColor: .purple,
                    title: "Delete Near-Duplicates",
                    description: dupCount > 0
                        ? "You have \(dupCount) burst groups taking \(formatBytes(dupSize))."
                        : "No duplicates found.",
                    actionTitle: "Review",
                    action: {
                        selectedFilter = .similar
                        selectedTab = 2
                    }
                )
                
                Divider().background(Color.borderLight)
                
                // Giant Files Recommendation
                RecommendationRow(
                    icon: "exclamationmark.triangle.fill",
                    iconColor: .orange,
                    title: "Delete Giant Files (>100MB)",
                    description: giantFilesCount > 0
                        ? "You have \(giantFilesCount) giant files."
                        : "No giant files found.",
                    actionTitle: "Clean Up",
                    action: {
                        selectedFilter = .giant
                        selectedTab = 2
                    }
                )
                
                Divider().background(Color.borderLight)
                
                // Large Files Recommendation
                RecommendationRow(
                    icon: "folder.badge.minus",
                    iconColor: .blue,
                    title: "Review Large Files (10-100MB)",
                    description: largeFilesCount > 0
                        ? "You have \(largeFilesCount) large files."
                        : "No large files found.",
                    actionTitle: "Review",
                    action: {
                        selectedFilter = .large
                        selectedTab = 2
                    }
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.cardBg)
                .shadow(color: .black.opacity(0.03), radius: 10, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.borderLight, lineWidth: 1)
        )
    }
    
    // 4. Breakdown metrics
    private var mediaBreakdownGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            QuickActionButton(
                title: "Photos",
                value: "\(analyzer.stats.imageCount)",
                size: formatBytes(analyzer.stats.imageSize),
                icon: "photo.fill",
                gradientColors: [.red, .orange],
                action: {
                    selectedFilter = .all
                    selectedTab = 2
                }
            )
            
            QuickActionButton(
                title: "Screenshots",
                value: "\(analyzer.stats.screenshotCount)",
                size: formatBytes(analyzer.stats.screenshotSize),
                icon: "camera.viewfinder",
                gradientColors: [.blue, .purple],
                action: {
                    selectedFilter = .screenshots
                    selectedTab = 2
                }
            )
            
            QuickActionButton(
                title: "Videos",
                value: "\(analyzer.stats.videoCount)",
                size: formatBytes(analyzer.stats.videoSize),
                icon: "video.fill",
                gradientColors: [.cyan, .blue],
                action: {
                    selectedFilter = .all
                    selectedTab = 2
                }
            )
            
            QuickActionButton(
                title: "Live Photos",
                value: "\(analyzer.stats.livePhotoCount)",
                size: formatBytes(analyzer.stats.livePhotoSize),
                icon: "livephoto",
                gradientColors: [.green, Color(red: 0.05, green: 0.6, blue: 0.4)],
                action: {
                    selectedFilter = .all
                    selectedTab = 2
                }
            )
        }
    }
    
    // 5. Monthly breakdowns
    private var monthlyBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Monthly Storage Profile")
                .font(.headline)
                .foregroundColor(.primary)
            
            if analyzer.monthlyBreakdown.isEmpty {
                Text("No breakdown data available. Scan your library first.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 12) {
                    ForEach(analyzer.monthlyBreakdown) { month in
                        HStack {
                            Text(month.name)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(month.count) items")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(formatBytes(month.size))
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.purple)
                        }
                        .padding(.vertical, 6)
                        Divider().background(Color.borderLight)
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.cardBg)
                .shadow(color: .black.opacity(0.03), radius: 10, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.borderLight, lineWidth: 1)
        )
    }
}

// MARK: - RECOMMENDATIONS ROW SUBCOMPONENT
struct RecommendationRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let actionTitle: String
    let action: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(iconColor)
                .frame(width: 32, height: 32)
                .background(iconColor.opacity(0.1))
                .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            Button(action: action) {
                Text(actionTitle)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.purple)
                    .cornerRadius(8)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - QUICK ACTION BUTTON SUBCOMPONENT
struct QuickActionButton: View {
    let title: String
    let value: String
    let size: String
    let icon: String
    let gradientColors: [Color]
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    Spacer()
                    Text(value)
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    Text(size)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.purple)
                }
            }
            .padding(16)
            .background(Color.cardBg)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.borderLight, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.02), radius: 6, y: 3)
        }
    }
}

// MARK: - DASHBOARD TIMELINE THUMBNAIL (For Vlog Banner Card)
struct DashboardTimelineThumbnailView: View {
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
                Color.purple.opacity(0.1)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.purple)
                    )
            }
        }
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        guard let asset = analyzer.getPHAsset(for: assetIdentifier) else { return }
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.isSynchronous = false
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

extension DashboardView {
    private func formatMonthYear(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: date)
    }

    var travelVlogSlideCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("🗺️ TRAVEL FOOTPRINTS")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.purple)
                Spacer()
                Text("Latest Vlog")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.purple.opacity(0.12))
                    .cornerRadius(6)
                    .foregroundColor(.purple)
            }
            
            if let latestCity = analyzer.locationsBreakdown.sorted(by: { ($0.assets.first?.creationDate ?? Date()) > ($1.assets.first?.creationDate ?? Date()) }).first {
                HStack(spacing: 12) {
                    if let firstAsset = latestCity.assets.first {
                        DashboardTimelineThumbnailView(assetIdentifier: firstAsset.localIdentifier)
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(latestCity.name)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        HStack {
                            Text("\(latestCity.count) memories")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if let date = latestCity.assets.first?.creationDate {
                                Text("•")
                                    .foregroundColor(.secondary)
                                Text(formatMonthYear(date))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    Spacer()
                }
            }
            
            Button(action: {
                selectedTab = 1 // Switch to Gallery
            }) {
                Text("Open Travel Vlog Timeline")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.purple)
                    .cornerRadius(12)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.cardBg)
                .shadow(color: .black.opacity(0.03), radius: 10, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.borderLight, lineWidth: 1)
        )
    }
}
