import SwiftUI

struct StorageInsightsSheet: View {
    @EnvironmentObject var analyzer: PhotoAnalyzer
    @Environment(\.dismiss) var dismiss
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
    
    // Group files dynamically by extension
    private struct FormatGroup: Identifiable {
        let id: String
        let ext: String
        let count: Int
        let size: Int64
    }
    
    private var formatBreakdown: [FormatGroup] {
        var groups: [String: (count: Int, size: Int64)] = [:]
        for asset in analyzer.analyzedAssets {
            let ext = (asset.fileName as NSString).pathExtension.uppercased()
            let key = ext.isEmpty ? "UNKNOWN" : ext
            let current = groups[key] ?? (0, 0)
            groups[key] = (current.count + 1, current.size + asset.fileSize)
        }
        return groups.map { FormatGroup(id: $0.key, ext: $0.key, count: $0.value.count, size: $0.value.size) }
            .sorted(by: { $0.size > $1.size })
    }
    
    // Space reclamation math
    private var duplicateSavings: Int64 {
        analyzer.similarPhotosGroups.reduce(0) { sum, group in
            sum + (group.totalSize - (group.assets.first?.fileSize ?? 0))
        }
    }
    
    private var screenshotSize: Int64 {
        analyzer.analyzedAssets.filter { $0.isScreenshot }.reduce(0) { $0 + $1.fileSize }
    }
    
    private var totalSavings: Int64 {
        duplicateSavings + screenshotSize
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // 1. iCloud Sync Coverage Card
                    syncCoverageCard
                    
                    // 2. Format Distribution Card
                    formatDistributionCard
                    
                    // 3. Space Reclamation Card
                    reclaimableCard
                }
                .padding()
            }
            .navigationTitle("Storage Insights")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color.mainBg)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.purple)
                    .fontWeight(.bold)
                }
            }
        }
        .preferredColorScheme(.light)
    }
    
    // iCloud Sync coverage section
    private var syncCoverageCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("iCloud Backup Health")
                .font(.headline)
                .foregroundColor(.primary)
            
            let total = analyzer.stats.totalCount
            let synced = analyzer.stats.iCloudPhotosCount
            let percent = total > 0 ? Double(synced) / Double(total) : 0.0
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(Int(percent * 100))% Synced")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.purple)
                    Spacer()
                    Text("\(synced) of \(total) items")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.1))
                            .frame(height: 8)
                        
                        Capsule()
                            .fill(LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * CGFloat(percent), height: 8)
                    }
                }
                .frame(height: 8)
            }
            
            Divider().background(Color.borderLight)
            
            VStack(spacing: 12) {
                syncRow(title: "iCloud Only (Offloaded)", count: analyzer.stats.cloudCount, size: analyzer.stats.cloudSize, icon: "cloud.fill", color: .purple)
                syncRow(title: "iCloud Synced (Local copy)", count: analyzer.stats.localSyncedCount, size: analyzer.stats.localSyncedSize, icon: "checkmark.icloud.fill", color: .blue)
                syncRow(title: "Device Only (Not Synced)", count: analyzer.stats.deviceOnlyCount, size: analyzer.stats.deviceOnlySize, icon: "icloud.slash.fill", color: .orange)
            }
        }
        .padding(20)
        .background(Color.cardBg)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.borderLight, lineWidth: 1)
        )
    }
    
    private func syncRow(title: String, count: Int, size: Int64, icon: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.subheadline)
                .frame(width: 24, alignment: .leading)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.primary)
                Text("\(count) items")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(formatBytes(size))
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
        }
    }
    
    // File format breakdown list
    private var formatDistributionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("File Format Distribution")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(spacing: 12) {
                ForEach(formatBreakdown) { group in
                    HStack {
                        Text(group.ext)
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.purple)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.purple.opacity(0.08))
                            .cornerRadius(6)
                        
                        Text("\(group.count) files")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(formatBytes(group.size))
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                    }
                    
                    if group.id != formatBreakdown.last?.id {
                        Divider().background(Color.borderLight)
                    }
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
    }
    
    // Space saving estimations
    private var reclaimableCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Potential Reclaimable Space")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(alignment: .center, spacing: 8) {
                Text(formatBytes(totalSavings))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.green)
                Text("Total Space Saving Estimate")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            
            Divider().background(Color.borderLight)
            
            VStack(spacing: 12) {
                HStack {
                    Label("Duplicates & Bursts", systemImage: "photo.stack")
                        .font(.caption)
                        .foregroundColor(.primary)
                    Spacer()
                    Text(formatBytes(duplicateSavings))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Label("Screenshots Cleanup", systemImage: "iphone.smartcard")
                        .font(.caption)
                        .foregroundColor(.primary)
                    Spacer()
                    Text(formatBytes(screenshotSize))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
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
    }
}
