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
    
    // Explicit constructor
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
    
    public var cloudCount: Int = 0 // iCloud-only (offloaded)
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
    
    public var totalSize: Int64 {
        assets.reduce(0) { $0 + $1.fileSize }
    }
}

public struct LocationGroup: Identifiable, Codable, Hashable {
    public var id: String { name }
    public let name: String
    public let count: Int
    public let size: Int64
    public let assets: [AnalyzedAsset]
}

@MainActor
public final class PhotoAnalyzer: NSObject, ObservableObject {
    @Published public var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published public var isScanning = false
    @Published public var scanProgress: Double = 0.0
    @Published public var totalScanned = 0
    @Published public var totalAssetsCount = 0
    @Published public var analyzedAssets: [AnalyzedAsset] = []
    @Published public var stats = DashboardStats()
    @Published public var isDemoMode = false
    @Published public var monthlyBreakdown: [MonthStats] = []
    @Published public var similarPhotosGroups: [SimilarPhotoGroup] = []
    @Published public var customAlbums: [CustomAlbum] = []
    @Published public var locationsBreakdown: [LocationGroup] = []
    
    private var scanTask: Task<Void, Never>?
    private var locationCache: [String: String] = [:]
    private var assetCache: [String: PHAsset] = [:]
    
    public override init() {
        super.init()
        self.loadAlbums()
        self.loadLocationCache()
        self.loadCache()
        
        #if targetEnvironment(simulator)
        self.authorizationStatus = .authorized
        if self.analyzedAssets.isEmpty {
            self.startDemoMode()
        }
        #else
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        self.authorizationStatus = status
        PHPhotoLibrary.shared().register(self)
        #endif
    }
    
    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }
    
    public func getPHAsset(for identifier: String) -> PHAsset? {
        if let cached = assetCache[identifier] {
            return cached
        }
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
        if status == .authorized || status == .limited {
            await startScan()
        }
    }
    
    // Caching layer
    private func loadCache() {
        if let data = UserDefaults.standard.data(forKey: "cached_analyzed_assets"),
           let decoded = try? JSONDecoder().decode([AnalyzedAsset].self, from: data) {
            self.analyzedAssets = decoded
            self.totalScanned = decoded.count
            self.totalAssetsCount = decoded.count
            self.calculateStats()
        }
    }
    
    private func saveCache() {
        if let encoded = try? JSONEncoder().encode(self.analyzedAssets) {
            UserDefaults.standard.set(encoded, forKey: "cached_analyzed_assets")
        }
    }
    
    private func loadLocationCache() {
        if let cached = UserDefaults.standard.dictionary(forKey: "geocoded_locations_cache") as? [String: String] {
            self.locationCache = cached
        }
    }
    
    private func saveLocationCache() {
        UserDefaults.standard.set(self.locationCache, forKey: "geocoded_locations_cache")
    }
    
    public func startScan() async {
        if isScanning { return }
        isScanning = true
        scanProgress = 0.0
        isDemoMode = false
        
        scanTask = Task {
            let fetchOptions = PHFetchOptions()
            let fetchResult = PHAsset.fetchAssets(with: fetchOptions)
            let count = fetchResult.count
            self.totalAssetsCount = count
            
            #if targetEnvironment(simulator)
            if count == 0 || self.authorizationStatus == .denied || self.authorizationStatus == .restricted {
                try? await Task.sleep(nanoseconds: 800_000_000)
                self.generateMockAssets()
                self.isScanning = false
                return
            }
            #endif
            
            if count == 0 {
                self.analyzedAssets = []
                self.calculateStats()
                self.saveCache()
                self.isScanning = false
                return
            }
            
            // Build cache map of PHAssets quickly in background
            let assetsArray: [PHAsset] = (0..<count).map { fetchResult.object(at: $0) }
            for asset in assetsArray {
                self.assetCache[asset.localIdentifier] = asset
            }
            
            let currentIds = Set(assetsArray.map { $0.localIdentifier })
            
            // Incremental Scan: filter out any cached assets that have been deleted
            var updatedAssets = self.analyzedAssets.filter { currentIds.contains($0.localIdentifier) }
            let scannedIds = Set(updatedAssets.map { $0.localIdentifier })
            
            // Identify newly added assets
            let newAssetsToScan = assetsArray.filter { !scannedIds.contains($0.localIdentifier) }
            
            if newAssetsToScan.isEmpty && updatedAssets.count == count {
                // Library matches cache perfectly, stop early
                self.analyzedAssets = updatedAssets.sorted(by: { $0.fileSize > $1.fileSize })
                self.totalScanned = updatedAssets.count
                self.calculateStats()
                self.saveCache()
                self.isScanning = false
                return
            }
            
            // Scan only the new assets in batches
            var tempNewAssets: [AnalyzedAsset] = []
            let newCount = newAssetsToScan.count
            let batchSize = 30
            
            for i in stride(from: 0, to: newCount, by: batchSize) {
                if Task.isCancelled { break }
                
                let end = min(i + batchSize, newCount)
                let batch = Array(newAssetsToScan[i..<end])
                
                let cacheSnapshot = self.locationCache
                let batchResults = await withTaskGroup(of: AnalyzedAsset?.self) { group in
                    for asset in batch {
                        group.addTask {
                            let resources = PHAssetResource.assetResources(for: asset)
                            guard let primaryResource = resources.first else {
                                return AnalyzedAsset(
                                    localIdentifier: asset.localIdentifier,
                                    fileName: "Unknown",
                                    fileSize: 0,
                                    isLocallyAvailable: true,
                                    mediaType: asset.mediaType,
                                    isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
                                    isLivePhoto: asset.mediaSubtypes.contains(.photoLive),
                                    creationDate: asset.creationDate,
                                    duration: asset.duration,
                                    syncStatus: .deviceOnly,
                                    locationName: nil,
                                    latitude: nil,
                                    longitude: nil
                                )
                            }
                            
                            let fileSize = primaryResource.value(forKey: "fileSize") as? Int64 ?? 0
                            let isLocallyAvailable = primaryResource.value(forKey: "locallyAvailable") as? Bool ?? true
                            let fileName = primaryResource.originalFilename
                            
                            let locName: String?
                            if let loc = asset.location {
                                let key = String(format: "%.2f,%.2f", loc.coordinate.latitude, loc.coordinate.longitude)
                                locName = cacheSnapshot[key] ?? String(format: "Location (%.2f, %.2f)", loc.coordinate.latitude, loc.coordinate.longitude)
                            } else {
                                locName = nil
                            }
                            
                            return AnalyzedAsset(
                                localIdentifier: asset.localIdentifier,
                                fileName: fileName,
                                fileSize: fileSize,
                                isLocallyAvailable: isLocallyAvailable,
                                mediaType: asset.mediaType,
                                isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
                                isLivePhoto: asset.mediaSubtypes.contains(.photoLive),
                                creationDate: asset.creationDate,
                                duration: asset.duration,
                                syncStatus: isLocallyAvailable ? .syncedLocal : .offloaded,
                                locationName: locName,
                                latitude: asset.location?.coordinate.latitude,
                                longitude: asset.location?.coordinate.longitude
                            )
                        }
                    }
                    
                    var results: [AnalyzedAsset] = []
                    for await assetInfo in group {
                        if let info = assetInfo {
                            results.append(info)
                        }
                    }
                    return results
                }
                
                tempNewAssets.append(contentsOf: batchResults)
                
                // Update progress dynamically
                let currentProgressCount = updatedAssets.count + tempNewAssets.count
                self.totalScanned = currentProgressCount
                self.scanProgress = Double(currentProgressCount) / Double(count)
            }
            
            if !Task.isCancelled {
                updatedAssets.append(contentsOf: tempNewAssets)
                self.analyzedAssets = updatedAssets.sorted(by: { $0.fileSize > $1.fileSize })
                self.calculateStats()
                self.saveCache()
            }
            self.isScanning = false
        }
    }
    
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
            ("IMG_0982_RAW.DNG", 42_500_000, true, PHAssetMediaType.image, false, false, baseDate.addingTimeInterval(-86400 * 1), 0.0, .syncedLocal, "New York, USA", 40.7128, -74.0060),
            ("REC_TRIP_4K.MOV", 1_280_000_000, true, PHAssetMediaType.video, false, false, baseDate.addingTimeInterval(-86400 * 2), 242.0, .syncedLocal, "Paris, France", 48.8566, 2.3522),
            ("SCREENSHOT_HOMESCREEN.PNG", 4_200_000, true, PHAssetMediaType.image, true, false, baseDate.addingTimeInterval(-86400 * 3), 0.0, .deviceOnly, nil, nil, nil),
            ("PORTRAIT_SHOT_1.HEIC", 3_400_000, false, PHAssetMediaType.image, false, false, baseDate.addingTimeInterval(-86400 * 4), 0.0, .offloaded, "Tokyo, Japan", 35.6762, 139.6503),
            
            // Similar Photo Group 1 (Burst/Duplicates)
            ("IMG_BURST_1.HEIC", 8_500_000, true, PHAssetMediaType.image, false, false, baseDate.addingTimeInterval(-86400 * 5 + 0.0), 0.0, .syncedLocal, "San Francisco, USA", 37.7749, -122.4194),
            ("IMG_BURST_2.HEIC", 8_400_000, true, PHAssetMediaType.image, false, false, baseDate.addingTimeInterval(-86400 * 5 + 1.5), 0.0, .syncedLocal, "San Francisco, USA", 37.7749, -122.4194),
            ("IMG_BURST_3.HEIC", 8_600_000, true, PHAssetMediaType.image, false, false, baseDate.addingTimeInterval(-86400 * 5 + 3.0), 0.0, .syncedLocal, "San Francisco, USA", 37.7749, -122.4194),
            
            ("LIVE_ACTION_JUMP.HEIC", 8_900_000, false, PHAssetMediaType.image, false, true, baseDate.addingTimeInterval(-86400 * 6), 0.0, .offloaded, "Grand Canyon, AZ", 36.0544, -112.1401),
            ("SLOW_MO_SURFING.MOV", 620_000_000, false, PHAssetMediaType.video, false, false, baseDate.addingTimeInterval(-86400 * 7), 55.0, .offloaded, "Hawaii, USA", 20.7984, -156.3319),
            
            // Similar Photo Group 2
            ("IMG_SCENIC_A.HEIC", 15_200_000, false, PHAssetMediaType.image, false, false, baseDate.addingTimeInterval(-86400 * 8 + 0.0), 0.0, .offloaded, "Tokyo, Japan", 35.6762, 139.6503),
            ("IMG_SCENIC_B.HEIC", 15_100_000, false, PHAssetMediaType.image, false, false, baseDate.addingTimeInterval(-86400 * 8 + 2.0), 0.0, .offloaded, "Tokyo, Japan", 35.6762, 139.6503),
            
            ("MEME_COMIC.JPG", 1_800_000, true, PHAssetMediaType.image, false, false, baseDate.addingTimeInterval(-86400 * 9), 0.0, .deviceOnly, nil, nil, nil),
            ("RECEIPT_SCAN.PNG", 2_100_000, true, PHAssetMediaType.image, true, false, baseDate.addingTimeInterval(-86400 * 10), 0.0, .deviceOnly, nil, nil, nil),
            ("IMG_1820.HEIC", 2_900_000, true, PHAssetMediaType.image, false, false, baseDate.addingTimeInterval(-86400 * 11), 0.0, .syncedLocal, "New York, USA", 40.7128, -74.0060),
            ("SHORT_CLIP.MP4", 32_000_000, true, PHAssetMediaType.video, false, false, baseDate.addingTimeInterval(-86400 * 12), 12.0, .syncedLocal, "Paris, France", 48.8566, 2.3522)
        ]
        
        var tempAssets: [AnalyzedAsset] = []
        for (name, size, local, type, screenshot, live, date, duration, sync, locName, lat, lon) in mockFiles {
            let mockAsset = AnalyzedAsset(
                localIdentifier: "mock_\(name)_\(UUID().uuidString)",
                fileName: name,
                fileSize: Int64(size),
                isLocallyAvailable: local,
                mediaType: type,
                isScreenshot: screenshot,
                isLivePhoto: live,
                creationDate: date,
                duration: duration,
                syncStatus: sync,
                locationName: locName,
                latitude: lat,
                longitude: lon
            )
            tempAssets.append(mockAsset)
        }
        
        self.analyzedAssets = tempAssets.sorted(by: { $0.fileSize > $1.fileSize })
        self.totalScanned = tempAssets.count
        self.totalAssetsCount = tempAssets.count
        self.calculateStats()
        self.authorizationStatus = .authorized
    }
    
    public func calculateStats() {
        var tempStats = DashboardStats()
        tempStats.totalCount = analyzedAssets.count
        
        for asset in analyzedAssets {
            tempStats.totalSize += asset.fileSize
            
            if asset.mediaType == .image {
                tempStats.imageCount += 1
                tempStats.imageSize += asset.fileSize
                
                if asset.isScreenshot {
                    tempStats.screenshotCount += 1
                    tempStats.screenshotSize += asset.fileSize
                }
                
                if asset.isLivePhoto {
                    tempStats.livePhotoCount += 1
                    tempStats.livePhotoSize += asset.fileSize
                }
            } else if asset.mediaType == .video {
                tempStats.videoCount += 1
                tempStats.videoSize += asset.fileSize
            }
            
            if asset.isLocallyAvailable {
                tempStats.localCount += 1
                tempStats.localSize += asset.fileSize
            } else {
                tempStats.cloudCount += 1
                tempStats.cloudSize += asset.fileSize
            }
            
            switch asset.syncStatus {
            case .deviceOnly:
                tempStats.deviceOnlyCount += 1
                tempStats.deviceOnlySize += asset.fileSize
            case .syncedLocal:
                tempStats.localSyncedCount += 1
                tempStats.localSyncedSize += asset.fileSize
            case .offloaded:
                break
            }
            
            if asset.syncStatus == .syncedLocal || asset.syncStatus == .offloaded {
                tempStats.iCloudPhotosCount += 1
                tempStats.iCloudPhotosSize += asset.fileSize
            }
        }
        
        self.stats = tempStats
        self.calculateSimilarPhotos()
        self.calculateMonthlyBreakdown()
        self.calculateLocationsBreakdown()
    }
    
    private func calculateLocationsBreakdown() {
        var coordinateGroups: [String: [AnalyzedAsset]] = [:]
        for asset in analyzedAssets {
            guard let lat = asset.latitude, let lon = asset.longitude else { continue }
            let key = String(format: "%.2f,%.2f", lat, lon)
            coordinateGroups[key, default: []].append(asset)
        }
        
        var tempGroups: [LocationGroup] = []
        for (coordinateKey, assets) in coordinateGroups {
            let name = self.locationCache[coordinateKey] ?? "Location (\(coordinateKey))"
            
            let group = LocationGroup(
                name: name,
                count: assets.count,
                size: assets.reduce(0) { $0 + $1.fileSize },
                assets: assets
            )
            tempGroups.append(group)
            
            if self.locationCache[coordinateKey] == nil {
                geocodeCoordinateKey(coordinateKey, assets: assets)
            }
        }
        
        // Sort chronologically by trip date (latest trip first)
        self.locationsBreakdown = tempGroups.sorted(by: {
            ($0.assets.first?.creationDate ?? Date()) > ($1.assets.first?.creationDate ?? Date())
        })
    }
    
    private func geocodeCoordinateKey(_ key: String, assets: [AnalyzedAsset]) {
        guard let first = assets.first,
              let lat = first.latitude,
              let lon = first.longitude else { return }
        
        let location = CLLocation(latitude: lat, longitude: lon)
        CLGeocoder().reverseGeocodeLocation(location) { placemarks, error in
            guard let placemark = placemarks?.first else { return }
            
            // Check granular fields: locality (city), subAdmin (county), admin (state), landmark name
            let city = placemark.locality ?? placemark.subAdministrativeArea ?? placemark.administrativeArea ?? placemark.name ?? "Unknown Location"
            let country = placemark.country ?? ""
            let name = country.isEmpty ? city : "\(city), \(country)"
            
            DispatchQueue.main.async {
                self.locationCache[key] = name
                self.saveLocationCache()
                
                var updated = self.analyzedAssets
                for i in 0..<updated.count {
                    if let aLat = updated[i].latitude, let aLon = updated[i].longitude {
                        let aKey = String(format: "%.2f,%.2f", aLat, aLon)
                        if aKey == key {
                            updated[i] = AnalyzedAsset(
                                localIdentifier: updated[i].localIdentifier,
                                fileName: updated[i].fileName,
                                fileSize: updated[i].fileSize,
                                isLocallyAvailable: updated[i].isLocallyAvailable,
                                mediaType: updated[i].mediaType,
                                isScreenshot: updated[i].isScreenshot,
                                isLivePhoto: updated[i].isLivePhoto,
                                creationDate: updated[i].creationDate,
                                duration: updated[i].duration,
                                syncStatus: updated[i].syncStatus,
                                locationName: name,
                                latitude: aLat,
                                longitude: aLon
                            )
                        }
                    }
                }
                self.analyzedAssets = updated
                self.calculateStats()
                self.saveCache()
            }
        }
    }
    
    private func calculateSimilarPhotos() {
        let sortedByDate = analyzedAssets.filter { $0.creationDate != nil }.sorted(by: { $0.creationDate! < $1.creationDate! })
        
        var groups: [SimilarPhotoGroup] = []
        var currentGroupAssets: [AnalyzedAsset] = []
        
        for asset in sortedByDate {
            if currentGroupAssets.isEmpty {
                currentGroupAssets.append(asset)
            } else {
                let lastAsset = currentGroupAssets.last!
                let timeDelta = asset.creationDate!.timeIntervalSince(lastAsset.creationDate!)
                
                if timeDelta <= 5.0 {
                    currentGroupAssets.append(asset)
                } else {
                    if currentGroupAssets.count >= 2 {
                        groups.append(SimilarPhotoGroup(keyAsset: currentGroupAssets.first!, assets: currentGroupAssets))
                    }
                    currentGroupAssets = [asset]
                }
            }
        }
        
        if currentGroupAssets.count >= 2 {
            groups.append(SimilarPhotoGroup(keyAsset: currentGroupAssets.first!, assets: currentGroupAssets))
        }
        
        self.similarPhotosGroups = groups.sorted(by: { $0.totalSize > $1.totalSize })
    }
    
    private func calculateMonthlyBreakdown() {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        
        var groups: [String: [AnalyzedAsset]] = [:]
        for asset in analyzedAssets {
            guard let date = asset.creationDate else { continue }
            let monthString = formatter.string(from: date)
            groups[monthString, default: []].append(asset)
        }
        
        var breakdown: [MonthStats] = []
        for (monthName, assets) in groups {
            let totalSize = assets.reduce(0) { $0 + $1.fileSize }
            breakdown.append(MonthStats(name: monthName, count: assets.count, size: totalSize, date: assets.first?.creationDate ?? Date()))
        }
        
        self.monthlyBreakdown = breakdown.sorted(by: { $0.date > $1.date })
    }
    
    public func deleteAssets(_ assetsToDelete: [AnalyzedAsset]) async -> Bool {
        #if targetEnvironment(simulator)
        let deletedIDs = Set(assetsToDelete.map { $0.localIdentifier })
        DispatchQueue.main.async {
            self.analyzedAssets.removeAll(where: { deletedIDs.contains($0.localIdentifier) })
            self.calculateStats()
            self.saveCache()
        }
        return true
        #else
        let localIDs = assetsToDelete.map { $0.localIdentifier }
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: localIDs, options: nil)
        var realAssets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            realAssets.append(asset)
        }
        
        if realAssets.isEmpty {
            return false
        }
        
        let deletedIDs = Set(localIDs)
        
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.deleteAssets(realAssets as NSArray)
            }) { success, error in
                if success {
                    DispatchQueue.main.async {
                        self.analyzedAssets.removeAll(where: { deletedIDs.contains($0.localIdentifier) })
                        self.calculateStats()
                        self.saveCache()
                        continuation.resume(returning: true)
                    }
                } else {
                    print("Error deleting assets: \(String(describing: error))")
                    continuation.resume(returning: false)
                }
            }
        }
        #endif
    }
    
    // MARK: - Custom Albums & Favorites
    public func saveAlbums() {
        if let encoded = try? JSONEncoder().encode(customAlbums) {
            UserDefaults.standard.set(encoded, forKey: "custom_albums")
        }
    }
    
    public func loadAlbums() {
        if let data = UserDefaults.standard.data(forKey: "custom_albums"),
           let decoded = try? JSONDecoder().decode([CustomAlbum].self, from: data) {
            self.customAlbums = decoded
        } else {
            self.customAlbums = [
                CustomAlbum(id: UUID(), name: "Favorites", assetIdentifiers: [])
            ]
        }
    }
    
    public func createAlbum(name: String) {
        let newAlbum = CustomAlbum(id: UUID(), name: name, assetIdentifiers: [])
        customAlbums.append(newAlbum)
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
        if let preDefined = asset.locationName {
            completion(preDefined)
            return
        }
        guard let lat = asset.latitude, let lon = asset.longitude else {
            completion("No Location")
            return
        }
        let cacheKey = String(format: "%.3f,%.3f", lat, lon)
        if let cached = locationCache[cacheKey] {
            completion(cached)
            return
        }
        
        let location = CLLocation(latitude: lat, longitude: lon)
        CLGeocoder().reverseGeocodeLocation(location) { placemarks, error in
            if let placemark = placemarks?.first,
               let city = placemark.locality,
               let country = placemark.country {
                let name = "\(city), \(country)"
                DispatchQueue.main.async {
                    self.locationCache[cacheKey] = name
                    completion(name)
                }
            } else {
                let fallback = String(format: "Lat: %.2f, Lon: %.2f", lat, lon)
                DispatchQueue.main.async {
                    completion(fallback)
                }
            }
        }
    }
}

// MARK: - PHPhotoLibraryChangeObserver
extension PhotoAnalyzer: PHPhotoLibraryChangeObserver {
    nonisolated public func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            if !self.isScanning && !self.isDemoMode {
                await self.startScan()
            }
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
