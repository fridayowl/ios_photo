import Foundation
import Photos
import SwiftUI
import Combine
import CoreLocation

public enum iCloudSyncStatus: String, Codable, CaseIterable, Identifiable {
    case deviceOnly = "Device Only"
    case syncedLocal = "iCloud Synced"
    case offloaded = "iCloud Only"
    
    public var id: String { self.rawValue }
}

public struct CustomAlbum: Identifiable, Codable, Hashable {
    public let id: UUID
    public var name: String
    public var assetIdentifiers: Set<String>
}

public struct AnalyzedAsset: Identifiable, Hashable, Codable {
    public var id: String { localIdentifier }
    public let localIdentifier: String
    public let fileName: String
    public let fileSize: Int64
    public let isLocallyAvailable: Bool
    public let mediaTypeRaw: Int
    public let isScreenshot: Bool
    public let isLivePhoto: Bool
    public let creationDate: Date?
    public let duration: TimeInterval
    public let syncStatus: iCloudSyncStatus
    public let locationName: String?
    public let latitude: Double?
    public let longitude: Double?
    
    public var mediaType: PHAssetMediaType {
        PHAssetMediaType(rawValue: mediaTypeRaw) ?? .unknown
    }
    
    public init(
        localIdentifier: String,
        fileName: String,
        fileSize: Int64,
        isLocallyAvailable: Bool,
        mediaType: PHAssetMediaType,
        isScreenshot: Bool,
        isLivePhoto: Bool,
        creationDate: Date?,
        duration: TimeInterval,
        syncStatus: iCloudSyncStatus,
        locationName: String?,
        latitude: Double?,
        longitude: Double?
    ) {
        self.localIdentifier = localIdentifier
        self.fileName = fileName
        self.fileSize = fileSize
        self.isLocallyAvailable = isLocallyAvailable
        self.mediaTypeRaw = mediaType.rawValue
        self.isScreenshot = isScreenshot
        self.isLivePhoto = isLivePhoto
        self.creationDate = creationDate
        self.duration = duration
        self.syncStatus = syncStatus
        self.locationName = locationName
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct DashboardStats {
    public var totalCount: Int = 0
    public var totalSize: Int64 = 0
    public var imageCount: Int = 0
    public var imageSize: Int64 = 0
    public var videoCount: Int = 0
    public var videoSize: Int64 = 0
    public var screenshotCount: Int = 0
    public var screenshotSize: Int64 = 0
    public var livePhotoCount: Int = 0
    public var livePhotoSize: Int64 = 0
    public var localCount: Int = 0
    public var localSize: Int64 = 0
    public var cloudCount: Int = 0
    public var cloudSize: Int64 = 0
    public var localSyncedCount: Int = 0
    public var localSyncedSize: Int64 = 0
    public var deviceOnlyCount: Int = 0
    public var deviceOnlySize: Int64 = 0
    public var iCloudPhotosCount: Int = 0
    public var iCloudPhotosSize: Int64 = 0
}

public struct MonthStats: Identifiable, Hashable {
    public var id: String { name }
    public let name: String
    public let count: Int
    public let size: Int64
    public let date: Date
}

public struct SimilarPhotoGroup: Identifiable, Hashable {
    public var id: String { keyAsset.localIdentifier }
    public let keyAsset: AnalyzedAsset
    public var assets: [AnalyzedAsset]
    public var totalSize: Int64 { assets.reduce(0) { $0 + $1.fileSize } }
}

public struct LocationGroup: Identifiable, Codable, Hashable {
    public let id: String
    public let name: String
    public let count: Int
    public let size: Int64
    public let assets: [AnalyzedAsset]
}

// MARK: - Fast geo-key (1 decimal = ~11km radius, groups nearby shots)
@inline(__always)
private func geoKey(_ lat: Double, _ lon: Double) -> String {
    String(format: "%.2f,%.2f", lat, lon)
}

// MARK: - Shared formatters (creating DateFormatter is expensive)
private let monthYearFormatter: DateFormatter = {
    let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f
}()

// MARK: - Background serialized encoder queue
private let cacheQueue = DispatchQueue(label: "com.photoscanner.cache", qos: .background)

@MainActor
public final class PhotoAnalyzer: NSObject, ObservableObject {
    public static var shared: PhotoAnalyzer? = nil
    
    @Published public var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published public var isScanning = false
    @Published public var scanProgress: Double = 0.0
    @Published public var totalScanned = 0
    @Published public var totalAssetsCount = 0
    @Published public var analyzedAssets: [AnalyzedAsset] = []
    @Published public var stats = DashboardStats()
    @Published public var isDemoMode = false
    @Published public var isFirstScanCompleted = false
    @Published public var monthlyBreakdown: [MonthStats] = []
    @Published public var similarPhotosGroups: [SimilarPhotoGroup] = []
    @Published public var customAlbums: [CustomAlbum] = []
    @Published public var locationsBreakdown: [LocationGroup] = []
    
    private var scanTask: Task<Void, Never>?
    private var locationCache: [String: String] = [:]          // geoKey → name
    private var assetCache: [String: PHAsset] = [:]           // id → PHAsset
    private var inFlightGeocodes: Set<String> = []
    private var geocodePendingKeys: [String] = []              // queue for rate-limited geocode
    private var geocodeTimer: Timer?
    private var statsDebounceTask: Task<Void, Never>?          // coalesces rapid stat recalcs
    
    // Fast lookup: geoKey → all asset indices that share it
    private var geoKeyToIndices: [String: [Int]] = [:]

    public override init() {
        super.init()
        PhotoAnalyzer.shared = self
        self.loadAlbums()
        self.loadLocationCache()
        self.loadCache()
        
        #if targetEnvironment(simulator)
        self.authorizationStatus = .authorized
        if self.analyzedAssets.isEmpty { self.startDemoMode() }
        #else
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        self.authorizationStatus = status
        PHPhotoLibrary.shared().register(self)
        #endif
    }
    
    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
        geocodeTimer?.invalidate()
    }
    
    public func getPHAsset(for identifier: String) -> PHAsset? {
        if let cached = assetCache[identifier] { return cached }
        #if !targetEnvironment(simulator)
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        if let first = result.firstObject {
            assetCache[identifier] = first
            return first
        }
        #endif
        return nil
    }
    
    public func requestPermission() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        self.authorizationStatus = status
        if status == .authorized || status == .limited { await startScan() }
    }
    
    // MARK: - Cache I/O (Asynchronous File-based Document Database)
    private func getCacheDirectory() -> URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let directory = paths[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
    
    private func getCacheFileURL() -> URL {
        getCacheDirectory().appendingPathComponent("analyzed_assets.json")
    }
    
    private func getLocationsCacheFileURL() -> URL {
        getCacheDirectory().appendingPathComponent("geocoded_locations.json")
    }
    
    private func getAlbumsFileURL() -> URL {
        getCacheDirectory().appendingPathComponent("custom_albums.json")
    }

    private func loadCache() {
        let fileURL = getCacheFileURL()
        cacheQueue.async { [weak self] in
            guard let self else { return }
            guard let data = try? Data(contentsOf: fileURL),
                  let decoded = try? JSONDecoder().decode([AnalyzedAsset].self, from: data) else { return }
            
            DispatchQueue.main.async {
                self.analyzedAssets = decoded
                self.totalScanned = decoded.count
                self.totalAssetsCount = decoded.count
                self.isFirstScanCompleted = true
                self.calculateStatsBackground()
            }
        }
    }
    
    private func saveCache() {
        let snapshot = self.analyzedAssets
        let fileURL = getCacheFileURL()
        cacheQueue.async {
            if let encoded = try? JSONEncoder().encode(snapshot) {
                try? encoded.write(to: fileURL, options: .atomic)
            }
        }
    }
    
    private func loadLocationCache() {
        let fileURL = getLocationsCacheFileURL()
        cacheQueue.async { [weak self] in
            guard let self else { return }
            guard let data = try? Data(contentsOf: fileURL),
                  let decoded = try? JSONDecoder().decode([String: String].self, from: data) else { return }
            
            let cleaned = decoded.filter { !$0.value.hasPrefix("Location (") }
            
            DispatchQueue.main.async {
                self.locationCache = cleaned
            }
        }
    }
    
    private func saveLocationCache() {
        let snapshot = self.locationCache
        let fileURL = getLocationsCacheFileURL()
        cacheQueue.async {
            if let encoded = try? JSONEncoder().encode(snapshot) {
                try? encoded.write(to: fileURL, options: .atomic)
            }
        }
    }
    
    // MARK: - Core Scan  ────────────────────────────────────────────────────
    public func startScan() async {
        if isScanning { return }
        isScanning = true
        scanProgress = 0.0
        isDemoMode = false
        
        scanTask = Task {
            // ── 1. Fetch all asset identifiers & metadata (fast, no I/O) ──
            let fetchOptions = PHFetchOptions()
            fetchOptions.includeAllBurstAssets = false  // skip burst duplicates
            fetchOptions.includeHiddenAssets = false
            let fetchResult = PHAsset.fetchAssets(with: fetchOptions)
            let count = fetchResult.count
            
            #if targetEnvironment(simulator)
            var hasLocationAssets = false
            fetchResult.enumerateObjects { asset, _, stop in
                if asset.location != nil {
                    hasLocationAssets = true
                    stop.pointee = true
                }
            }
            if count < 15 || !hasLocationAssets || self.authorizationStatus == .denied || self.authorizationStatus == .restricted {
                try? await Task.sleep(nanoseconds: 800_000_000)
                self.generateMockAssets()
                self.isScanning = false
                return
            }
            #endif
            
            if count == 0 {
                self.totalAssetsCount = 0
                self.analyzedAssets = []
                self.isScanning = false
                self.isFirstScanCompleted = true
                self.calculateStatsBackground()
                self.saveCache()
                return
            }
            
            // ── 2. Build PHAsset array off-main via nonisolated task ──────
            // PHFetchResult is not Sendable, so extract synchronously but fast
            var assetsArray: [PHAsset] = []
            assetsArray.reserveCapacity(count)
            fetchResult.enumerateObjects { asset, _, _ in
                assetsArray.append(asset)
                self.assetCache[asset.localIdentifier] = asset
            }
            
            // ── 3. Incremental diff: only process truly new assets ────────
            let currentIds: Set<String> = Set(assetsArray.map(\.localIdentifier))
            self.totalAssetsCount = currentIds.count
            var updatedAssets = self.analyzedAssets.filter { currentIds.contains($0.localIdentifier) }
            let scannedIds: Set<String> = Set(updatedAssets.map(\.localIdentifier))
            let newAssets = assetsArray.filter { !scannedIds.contains($0.localIdentifier) }
            
            if newAssets.isEmpty && updatedAssets.count == currentIds.count {
                // Perfect cache hit — instant return, no blocking stats
                self.analyzedAssets = updatedAssets
                self.totalScanned = updatedAssets.count
                self.scanProgress = 1.0
                self.isFirstScanCompleted = true
                self.isScanning = false
                self.calculateStatsBackground()
                return
            }
            
            // Show cached data immediately so UI isn't empty
            if !updatedAssets.isEmpty {
                self.analyzedAssets = updatedAssets
                self.totalScanned = updatedAssets.count
                self.scanProgress = 0.01  // 1% — scanning is starting
            }
            
            // ── 4. Parallel batch scan with large batches ─────────────────
            let newCount = newAssets.count
            let batchSize = 200   // 200 vs 30 = 6.7× fewer round-trips
            let locationCacheSnapshot = self.locationCache
            var tempNewAssets: [AnalyzedAsset] = []
            tempNewAssets.reserveCapacity(newCount)
            
            for batchStart in stride(from: 0, to: newCount, by: batchSize) {
                if Task.isCancelled { break }
                let batchEnd = min(batchStart + batchSize, newCount)
                let batch = Array(newAssets[batchStart..<batchEnd])
                
                // Process batch concurrently — limited to 6 concurrent tasks to prevent XPC timeouts/hangs
                let batchResults: [AnalyzedAsset] = await withTaskGroup(of: AnalyzedAsset.self) { group in
                    var added = 0
                    var out: [AnalyzedAsset] = []
                    out.reserveCapacity(batch.count)
                    
                    for asset in batch {
                        if added >= 6 {
                            if let result = await group.next() {
                                out.append(result)
                            }
                        }
                        group.addTask {
                            self.analyzeAsset(asset, locationCacheSnapshot: locationCacheSnapshot)
                        }
                        added += 1
                    }
                    
                    while let result = await group.next() {
                        out.append(result)
                    }
                    return out
                }
                
                tempNewAssets.append(contentsOf: batchResults)
                
                // Progress tracks only the NEW assets (0%→99%), never shows 100% until done
                let newDone = tempNewAssets.count
                self.totalScanned = updatedAssets.count + newDone
                self.scanProgress = min(0.99, Double(newDone) / Double(max(newCount, 1)))
                
                // Progressive display every 1000 new assets
                if tempNewAssets.count % 1000 == 0 || tempNewAssets.count == newCount {
                    var partial = updatedAssets
                    partial.append(contentsOf: tempNewAssets)
                    self.analyzedAssets = partial
                }
            }
            
            updatedAssets.append(contentsOf: tempNewAssets)
            self.analyzedAssets = updatedAssets
            self.totalScanned = updatedAssets.count
            self.saveCache()
            self.calculateStatsBackground()
            
            if !Task.isCancelled {
                self.scanProgress = 1.0
                self.isFirstScanCompleted = true
                self.kickoffGeocoding()
            }
            self.isScanning = false
        }
    }
    
    // MARK: - Per-asset extraction (nonisolated, pure — no actor captures)
    private nonisolated func analyzeAsset(_ asset: PHAsset, locationCacheSnapshot: [String: String]) -> AnalyzedAsset {
        let resources = PHAssetResource.assetResources(for: asset)
        let primary = resources.first
        let fileSize = (primary?.value(forKey: "fileSize") as? NSNumber)?.int64Value ?? 0
        let isLocal  = (primary?.value(forKey: "locallyAvailable") as? NSNumber)?.boolValue ?? true
        let fileName = primary?.originalFilename ?? "Unknown"
        
        var locName: String? = nil
        var lat: Double? = nil
        var lon: Double? = nil
        if let loc = asset.location {
            lat = loc.coordinate.latitude
            lon = loc.coordinate.longitude
            let key = geoKey(loc.coordinate.latitude, loc.coordinate.longitude)
            locName = locationCacheSnapshot[key]
            if locName?.hasPrefix("Location (") == true {
                locName = nil
            }
        }
        
        return AnalyzedAsset(
            localIdentifier: asset.localIdentifier,
            fileName: fileName,
            fileSize: fileSize,
            isLocallyAvailable: isLocal,
            mediaType: asset.mediaType,
            isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
            isLivePhoto: asset.mediaSubtypes.contains(.photoLive),
            creationDate: asset.creationDate,
            duration: asset.duration,
            syncStatus: isLocal ? .syncedLocal : .offloaded,
            locationName: locName,
            latitude: lat,
            longitude: lon
        )
    }
    
    // MARK: - Stats — runs on a detached background task to not block main thread
    public func calculateStats() { calculateStatsBackground() }
    
    private func calculateStatsBackground() {
        let snapshot = self.analyzedAssets
        let cacheCopy = self.locationCache
        let inFlightCopy = self.inFlightGeocodes
        
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let result = await self.computeStats(snapshot, locationCache: cacheCopy, inFlightGeocodes: inFlightCopy)
            await MainActor.run {
                self.stats = result.stats
                self.similarPhotosGroups = result.similar
                self.monthlyBreakdown = result.monthly
                self.locationsBreakdown = result.locations
                self.geoKeyToIndices = result.geoKeyToIndices
                
                if !result.keysNeedingGeocode.isEmpty {
                    self.geocodePendingKeys.append(contentsOf: result.keysNeedingGeocode)
                    self.startGeocodingQueue()
                }
            }
        }
    }
    
    // Pure computation — runs off main thread
    private nonisolated func computeStats(
        _ assets: [AnalyzedAsset],
        locationCache: [String: String],
        inFlightGeocodes: Set<String>
    ) async -> (
        stats: DashboardStats,
        similar: [SimilarPhotoGroup],
        monthly: [MonthStats],
        locations: [LocationGroup],
        geoKeyToIndices: [String: [Int]],
        keysNeedingGeocode: [String]
    ) {
        var s = DashboardStats()
        s.totalCount = assets.count
        
        var groups: [String: [AnalyzedAsset]] = [:]
        var geoKeyToIndices: [String: [Int]] = [:]
        
        for (i, a) in assets.enumerated() {
            s.totalSize += a.fileSize
            switch a.mediaType {
            case .image:
                s.imageCount += 1; s.imageSize += a.fileSize
                if a.isScreenshot { s.screenshotCount += 1; s.screenshotSize += a.fileSize }
                if a.isLivePhoto  { s.livePhotoCount  += 1; s.livePhotoSize  += a.fileSize }
            case .video:
                s.videoCount += 1; s.videoSize += a.fileSize
            default: break
            }
            if a.isLocallyAvailable { s.localCount += 1; s.localSize += a.fileSize }
            else                    { s.cloudCount += 1; s.cloudSize += a.fileSize }
            switch a.syncStatus {
            case .deviceOnly:  s.deviceOnlyCount  += 1; s.deviceOnlySize  += a.fileSize
            case .syncedLocal: s.localSyncedCount += 1; s.localSyncedSize += a.fileSize
            case .offloaded:   break
            }
            if a.syncStatus == .syncedLocal || a.syncStatus == .offloaded {
                s.iCloudPhotosCount += 1; s.iCloudPhotosSize += a.fileSize
            }
            
            // Build groups for locations
            if let lat = a.latitude, let lon = a.longitude {
                let key = String(format: "%.2f,%.2f", lat, lon)
                groups[key, default: []].append(a)
                geoKeyToIndices[key, default: []].append(i)
            }
        }
        
        let similar = computeSimilar(assets)
        let monthly = computeMonthly(assets)
        
        // Build LocationGroups
        var tempGroups: [LocationGroup] = []
        var keysNeedingGeocode: [String] = []
        
        for (key, groupAssets) in groups {
            let name = locationCache[key]
            let displayName: String
            let needsGeocode: Bool
            
            if let name = name, !name.hasPrefix("Location (") {
                displayName = name
                needsGeocode = false
            } else {
                displayName = "Exploring…"
                needsGeocode = true
            }
            
            tempGroups.append(LocationGroup(
                id: key,
                name: displayName,
                count: groupAssets.count,
                size: groupAssets.reduce(0) { $0 + $1.fileSize },
                assets: groupAssets
            ))
            if needsGeocode && !inFlightGeocodes.contains(key) {
                keysNeedingGeocode.append(key)
            }
        }
        
        let locations = tempGroups.sorted {
            ($0.assets.first?.creationDate ?? .distantPast) > ($1.assets.first?.creationDate ?? .distantPast)
        }
        
        return (s, similar, monthly, locations, geoKeyToIndices, keysNeedingGeocode)
    }
    
    private nonisolated func computeSimilar(_ assets: [AnalyzedAsset]) -> [SimilarPhotoGroup] {
        let sorted = assets
            .filter { $0.creationDate != nil && $0.fileSize > 0 }
            .sorted { $0.creationDate! < $1.creationDate! }
        var groups: [SimilarPhotoGroup] = []
        guard !sorted.isEmpty else { return groups }
        var groupStart = 0
        for i in 1...sorted.count {
            let isEnd = (i == sorted.count)
            let gap = isEnd ? 6.0 : sorted[i].creationDate!.timeIntervalSince(sorted[i-1].creationDate!)
            if gap > 5.0 || isEnd {
                if i - groupStart >= 2 {
                    let slice = Array(sorted[groupStart..<i])
                    groups.append(SimilarPhotoGroup(keyAsset: slice[0], assets: slice))
                }
                groupStart = i
            }
        }
        return groups.sorted { $0.totalSize > $1.totalSize }
    }
    
    private nonisolated func computeMonthly(_ assets: [AnalyzedAsset]) -> [MonthStats] {
        let fmt = DateFormatter(); fmt.dateFormat = "MMMM yyyy"
        var countMap: [String: Int]   = [:]
        var sizeMap:  [String: Int64] = [:]
        var dateMap:  [String: Date]  = [:]
        for a in assets {
            guard let d = a.creationDate else { continue }
            let key = fmt.string(from: d)
            countMap[key, default: 0]  += 1
            sizeMap[key, default: 0]   += a.fileSize
            if dateMap[key] == nil { dateMap[key] = d }
        }
        return countMap.map {
            MonthStats(name: $0.key, count: $0.value, size: sizeMap[$0.key]!, date: dateMap[$0.key]!)
        }.sorted { $0.date > $1.date }
    }
    
    // Kept for compatibility — delegates to background variant
    private func calculateStatsImmediate() { calculateStatsBackground() }
    
    // MARK: - Rate-limited geocoding queue (Apple allows ~50 geocodes/min) ─
    private func kickoffGeocoding() {
        startGeocodingQueue()
    }
    
    private func startGeocodingQueue() {
        guard geocodeTimer == nil else { return }
        // Fire every 1.3s — stays comfortably under Apple's 50/min rate limit
        geocodeTimer = Timer.scheduledTimer(withTimeInterval: 1.3, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let key = self.geocodePendingKeys.first else {
                    self.geocodeTimer?.invalidate()
                    self.geocodeTimer = nil
                    return
                }
                self.geocodePendingKeys.removeFirst()
                self.geocodeOneKey(key)
            }
        }
    }
    
    private func geocodeOneKey(_ key: String) {
        guard !inFlightGeocodes.contains(key) else { return }
        let parts = key.split(separator: ",")
        guard parts.count == 2,
              let lat = Double(parts[0]),
              let lon = Double(parts[1]) else { return }
        
        inFlightGeocodes.insert(key)
        
        Task {
            let name = await performHTTPGeocode(latitude: lat, longitude: lon)
            
            if let resolvedName = name {
                await updateLocationName(key: key, name: resolvedName)
            } else {
                let location = CLLocation(latitude: lat, longitude: lon)
                CLGeocoder().reverseGeocodeLocation(location) { [weak self] placemarks, _ in
                    guard let self else { return }
                    let city = placemarks?.first.flatMap {
                        $0.locality ?? $0.subAdministrativeArea ?? $0.administrativeArea ?? $0.name
                    }
                    let country = placemarks?.first?.country ?? ""
                    
                    let fallbackName: String
                    if let city = city {
                        fallbackName = country.isEmpty ? city : "\(city), \(country)"
                    } else {
                        fallbackName = String(format: "Location (%.2f, %.2f)", lat, lon)
                    }
                    
                    Task {
                        await self.updateLocationName(key: key, name: fallbackName)
                    }
                }
            }
        }
    }
    
    private func performHTTPGeocode(latitude: Double, longitude: Double) async -> String? {
        let urlString = "https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=\(latitude)&longitude=\(longitude)&localityLanguage=en"
        guard let url = URL(string: urlString) else { return nil }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 2.0 // Strict 2 second timeout to prevent hangs
        request.setValue("PhotoStorageAnalyzer/1.0", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }
            
            struct BigDataCloudResponse: Codable {
                let city: String?
                let locality: String?
                let principalSubdivision: String?
                let countryName: String?
            }
            
            let decoded = try JSONDecoder().decode(BigDataCloudResponse.self, from: data)
            let city = decoded.city ?? decoded.locality ?? decoded.principalSubdivision
            let country = decoded.countryName ?? ""
            
            if let city = city, !city.isEmpty {
                return country.isEmpty ? city : "\(city), \(country)"
            }
            return nil
        } catch {
            return nil
        }
    }
    
    @MainActor
    private func updateLocationName(key: String, name: String) {
        self.inFlightGeocodes.remove(key)
        guard self.locationCache[key] != name else { return }
        self.locationCache[key] = name
        self.saveLocationCache()
        
        if let indices = self.geoKeyToIndices[key] {
            for idx in indices where idx < self.analyzedAssets.count {
                var a = self.analyzedAssets[idx]
                a = AnalyzedAsset(
                    localIdentifier: a.localIdentifier, fileName: a.fileName,
                    fileSize: a.fileSize, isLocallyAvailable: a.isLocallyAvailable,
                    mediaType: a.mediaType, isScreenshot: a.isScreenshot,
                    isLivePhoto: a.isLivePhoto, creationDate: a.creationDate,
                    duration: a.duration, syncStatus: a.syncStatus,
                    locationName: name, latitude: a.latitude, longitude: a.longitude
                )
                self.analyzedAssets[idx] = a
            }
        }
        
        self.refreshLocationsBreakdownOnly()
    }
    
    private func refreshLocationsBreakdownOnly() {
        let snapshot = self.analyzedAssets
        let cacheCopy = self.locationCache
        
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            var groups: [String: [AnalyzedAsset]] = [:]
            for a in snapshot {
                guard let lat = a.latitude, let lon = a.longitude else { continue }
                let key = String(format: "%.2f,%.2f", lat, lon)
                groups[key, default: []].append(a)
            }
            var tempGroups: [LocationGroup] = []
            for (key, assets) in groups {
                let name = cacheCopy[key] ?? "Exploring…"
                tempGroups.append(LocationGroup(
                    id: key,
                    name: name,
                    count: assets.count,
                    size: assets.reduce(0) { $0 + $1.fileSize },
                    assets: assets
                ))
            }
            let sorted = tempGroups.sorted {
                ($0.assets.first?.creationDate ?? .distantPast) > ($1.assets.first?.creationDate ?? .distantPast)
            }
            
            await MainActor.run {
                self.locationsBreakdown = sorted
                self.saveCache()
            }
        }
    }
    
    // MARK: - Demo mode
    public func startDemoMode() {
        isScanning = true
        scanProgress = 0.0
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            self.generateMockAssets()
            self.isScanning = false
        }
    }
    
    private func generateMockAssets() {
        self.isDemoMode = true
        let baseDate = Date()
        let mockFiles: [(String, Int, Bool, PHAssetMediaType, Bool, Bool, Date, TimeInterval, iCloudSyncStatus, String?, Double?, Double?)] = [
            ("IMG_0982_RAW.DNG", 42_500_000, true, .image, false, false, baseDate.addingTimeInterval(-86400*1), 0.0, .syncedLocal, "New York, USA", 40.7128, -74.0060),
            ("REC_TRIP_4K.MOV", 1_280_000_000, true, .video, false, false, baseDate.addingTimeInterval(-86400*2), 242.0, .syncedLocal, "Paris, France", 48.8566, 2.3522),
            ("SCREENSHOT_HOMESCREEN.PNG", 4_200_000, true, .image, true, false, baseDate.addingTimeInterval(-86400*3), 0.0, .deviceOnly, nil, nil, nil),
            ("PORTRAIT_SHOT_1.HEIC", 3_400_000, false, .image, false, false, baseDate.addingTimeInterval(-86400*4), 0.0, .offloaded, "Tokyo, Japan", 35.6762, 139.6503),
            ("IMG_BURST_1.HEIC", 8_500_000, true, .image, false, false, baseDate.addingTimeInterval(-86400*5+0.0), 0.0, .syncedLocal, "San Francisco, USA", 37.7749, -122.4194),
            ("IMG_BURST_2.HEIC", 8_400_000, true, .image, false, false, baseDate.addingTimeInterval(-86400*5+1.5), 0.0, .syncedLocal, "San Francisco, USA", 37.7749, -122.4194),
            ("IMG_BURST_3.HEIC", 8_600_000, true, .image, false, false, baseDate.addingTimeInterval(-86400*5+3.0), 0.0, .syncedLocal, "San Francisco, USA", 37.7749, -122.4194),
            ("LIVE_ACTION_JUMP.HEIC", 8_900_000, false, .image, false, true, baseDate.addingTimeInterval(-86400*6), 0.0, .offloaded, "Grand Canyon Village, AZ", 36.0544, -112.1401),
            ("SLOW_MO_SURFING.MOV", 620_000_000, false, .video, false, false, baseDate.addingTimeInterval(-86400*7), 55.0, .offloaded, "Hawaii, USA", 20.7984, -156.3319),
            ("IMG_SCENIC_A.HEIC", 15_200_000, false, .image, false, false, baseDate.addingTimeInterval(-86400*8+0.0), 0.0, .offloaded, "Tokyo, Japan", 35.6762, 139.6503),
            ("IMG_SCENIC_B.HEIC", 15_100_000, false, .image, false, false, baseDate.addingTimeInterval(-86400*8+2.0), 0.0, .offloaded, "Tokyo, Japan", 35.6762, 139.6503),
            ("MEME_COMIC.JPG", 1_800_000, true, .image, false, false, baseDate.addingTimeInterval(-86400*9), 0.0, .deviceOnly, nil, nil, nil),
            ("RECEIPT_SCAN.PNG", 2_100_000, true, .image, true, false, baseDate.addingTimeInterval(-86400*10), 0.0, .deviceOnly, nil, nil, nil),
            ("IMG_1820.HEIC", 2_900_000, true, .image, false, false, baseDate.addingTimeInterval(-86400*11), 0.0, .syncedLocal, "New York, USA", 40.7128, -74.0060),
            ("SHORT_CLIP.MP4", 32_000_000, true, .video, false, false, baseDate.addingTimeInterval(-86400*12), 12.0, .syncedLocal, "Paris, France", 48.8566, 2.3522)
        ]
        var tempAssets: [AnalyzedAsset] = []
        for (name, size, local, type, screenshot, live, date, duration, sync, locName, lat, lon) in mockFiles {
            tempAssets.append(AnalyzedAsset(
                localIdentifier: "mock_\(name)_\(UUID().uuidString)",
                fileName: name, fileSize: Int64(size), isLocallyAvailable: local,
                mediaType: type, isScreenshot: screenshot, isLivePhoto: live,
                creationDate: date, duration: duration, syncStatus: sync,
                locationName: locName, latitude: lat, longitude: lon
            ))
        }
        self.analyzedAssets = tempAssets.sorted { $0.fileSize > $1.fileSize }
        self.totalScanned = tempAssets.count
        self.totalAssetsCount = tempAssets.count
        self.isFirstScanCompleted = true
        self.calculateStatsImmediate()
        self.authorizationStatus = .authorized
    }
    
    // MARK: - Delete
    public func deleteAssets(_ assetsToDelete: [AnalyzedAsset]) async -> Bool {
        #if targetEnvironment(simulator)
        let deletedIDs = Set(assetsToDelete.map(\.localIdentifier))
        self.analyzedAssets.removeAll { deletedIDs.contains($0.localIdentifier) }
        self.calculateStatsImmediate()
        self.saveCache()
        return true
        #else
        let localIDs = assetsToDelete.map(\.localIdentifier)
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: localIDs, options: nil)
        var realAssets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in realAssets.append(asset) }
        guard !realAssets.isEmpty else { return false }
        let deletedIDs = Set(localIDs)
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.deleteAssets(realAssets as NSArray)
            }) { success, error in
                if success {
                    DispatchQueue.main.async {
                        self.analyzedAssets.removeAll { deletedIDs.contains($0.localIdentifier) }
                        self.calculateStatsImmediate()
                        self.saveCache()
                        continuation.resume(returning: true)
                    }
                } else {
                    continuation.resume(returning: false)
                }
            }
        }
        #endif
    }
    
    // MARK: - Custom Albums
    public func saveAlbums() {
        let snapshot = self.customAlbums
        let fileURL = getAlbumsFileURL()
        cacheQueue.async {
            if let encoded = try? JSONEncoder().encode(snapshot) {
                try? encoded.write(to: fileURL, options: .atomic)
            }
        }
    }
    
    public func loadAlbums() {
        let fileURL = getAlbumsFileURL()
        // Synchronous initial check or read is okay for launch default setup
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([CustomAlbum].self, from: data) {
            self.customAlbums = decoded
        } else {
            self.customAlbums = [CustomAlbum(id: UUID(), name: "Favorites", assetIdentifiers: [])]
        }
    }
    
    public func createAlbum(name: String) {
        customAlbums.append(CustomAlbum(id: UUID(), name: name, assetIdentifiers: []))
        saveAlbums()
    }
    
    public func deleteAlbum(id: UUID) {
        customAlbums.removeAll { $0.id == id }
        saveAlbums()
    }
    
    public func addAsset(_ assetId: String, toAlbum id: UUID) {
        if let idx = customAlbums.firstIndex(where: { $0.id == id }) {
            customAlbums[idx].assetIdentifiers.insert(assetId)
            saveAlbums()
        }
    }
    
    public func removeAsset(_ assetId: String, fromAlbum id: UUID) {
        if let idx = customAlbums.firstIndex(where: { $0.id == id }) {
            customAlbums[idx].assetIdentifiers.remove(assetId)
            saveAlbums()
        }
    }
    
    public func getLocationName(for asset: AnalyzedAsset, completion: @escaping (String) -> Void) {
        if let pre = asset.locationName { completion(pre); return }
        guard let lat = asset.latitude, let lon = asset.longitude else { completion("No Location"); return }
        let key = geoKey(lat, lon)
        if let cached = locationCache[key] { completion(cached); return }
        let location = CLLocation(latitude: lat, longitude: lon)
        CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
            if let p = placemarks?.first, let city = p.locality, let country = p.country {
                let name = "\(city), \(country)"
                DispatchQueue.main.async { self.locationCache[key] = name; completion(name) }
            } else {
                completion(String(format: "%.2f, %.2f", lat, lon))
            }
        }
    }
}

// MARK: - PHPhotoLibraryChangeObserver
extension PhotoAnalyzer: PHPhotoLibraryChangeObserver {
    nonisolated public func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            if !self.isScanning && !self.isDemoMode { await self.startScan() }
        }
    }
}

public enum AppFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case giant = "Giant (>100MB)"
    case large = "Large (10-100MB)"
    case cloud = "iCloud Only"
    case screenshots = "Screenshots"
    case similar = "Similar Photos"
    
    public var id: String { self.rawValue }
}
