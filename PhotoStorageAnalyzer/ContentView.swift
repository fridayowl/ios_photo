import SwiftUI
import Photos

struct ContentView: View {
    @EnvironmentObject var analyzer: PhotoAnalyzer
    @State private var selectedTab = 0
    @State private var selectedFilter: AppFilter = .all
    @State private var spinAngle: Double = 0
    
    var body: some View {
        Group {
            switch analyzer.authorizationStatus {
            case .notDetermined:
                welcomeView
            case .denied, .restricted:
                permissionDeniedView
            case .authorized, .limited:
                if analyzer.analyzedAssets.isEmpty {
                    // Show scanning/loading screen until we have data (first launch or cache miss)
                    scanningView
                        .onAppear {
                            Task { await analyzer.startScan() }
                        }
                } else {
                    mainAppView
                }
            @unknown default:
                welcomeView
            }
        }
        .animation(.easeInOut(duration: 0.3), value: analyzer.authorizationStatus.rawValue)
        .animation(.easeInOut(duration: 0.3), value: analyzer.analyzedAssets.isEmpty)
        .task {
            if analyzer.authorizationStatus == .authorized || analyzer.authorizationStatus == .limited {
                await analyzer.startScan()
            }
        }
    }
    
    // Welcome / Permissions Request Screen
    private var welcomeView: some View {
        ZStack {
            LinearGradient(
                colors: [Color.white, Color.mainBg],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 30) {
                Spacer()
                
                Image(systemName: "photo.stack.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100)
                    .foregroundStyle(
                        .linearGradient(
                            colors: [.blue, .purple, .pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .purple.opacity(0.35), radius: 15)
                
                VStack(spacing: 12) {
                    Text("Photo Storage Analyzer")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                    
                    Text("Analyze your gallery sizes, identify iCloud-only files, and optimize your local storage.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }
                
                Spacer()
                
                Button(action: {
                    Task {
                        await analyzer.requestPermission()
                    }
                }) {
                    Text("Analyze Photo Library")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(14)
                        .shadow(color: .purple.opacity(0.25), radius: 8, y: 4)
                }
                .padding(.horizontal, 40)
                
                Button(action: {
                    analyzer.startDemoMode()
                }) {
                    Text("Use Simulated Demo Mode")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.purple)
                        .padding(.bottom, 20)
                }
            }
        }
    }
    
    // Permission Denied View
    private var permissionDeniedView: some View {
        ZStack {
            Color.mainBg
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.shield.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .foregroundColor(.red)
                
                VStack(spacing: 10) {
                    Text("Permission Required")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("We need full access to your photo library to analyze file sizes, detect iCloud sync state, and support group deletion.\n\nPlease enable Photo permissions in settings.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                
                VStack(spacing: 12) {
                    Button(action: {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        Text("Open iOS Settings")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(width: 250)
                            .padding(.vertical, 14)
                            .background(Color.blue)
                            .cornerRadius(12)
                            .shadow(color: .blue.opacity(0.25), radius: 6, y: 3)
                    }
                    
                    Button(action: {
                        analyzer.startDemoMode()
                    }) {
                        Text("Use Simulated Demo Mode")
                            .font(.headline)
                            .foregroundColor(.purple)
                            .frame(width: 250)
                            .padding(.vertical, 14)
                            .background(Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.purple, lineWidth: 1.5)
                            )
                    }
                }
            }
        }
    }
    
    // Loading / Scanning View
    private var scanningView: some View {
        ZStack {
            Color.mainBg.ignoresSafeArea()
            
            VStack(spacing: 32) {
                Spacer()
                
                // Icon + pulse ring
                ZStack {
                    // Outer pulsing glow
                    Circle()
                        .fill(Color.purple.opacity(0.08))
                        .frame(width: 160, height: 160)
                    
                    // Track ring
                    Circle()
                        .stroke(Color.purple.opacity(0.1), lineWidth: 10)
                        .frame(width: 130, height: 130)
                    
                    // Progress arc (or animated spinner if progress = 0)
                    if analyzer.scanProgress > 0 {
                        Circle()
                            .trim(from: 0.0, to: CGFloat(analyzer.scanProgress))
                            .stroke(
                                LinearGradient(
                                    colors: [.purple, .blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 10, lineCap: .round)
                            )
                            .frame(width: 130, height: 130)
                            .rotationEffect(.degrees(-90))
                            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: analyzer.scanProgress)
                    } else {
                        // Indeterminate spinner while waiting to start
                        Circle()
                            .trim(from: 0.0, to: 0.25)
                            .stroke(
                                LinearGradient(
                                    colors: [.purple, .blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 10, lineCap: .round)
                            )
                            .frame(width: 130, height: 130)
                            .rotationEffect(.degrees(spinAngle))
                            .onAppear {
                                withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                                    spinAngle = 360
                                }
                            }
                    }
                    
                    // Center content
                    VStack(spacing: 4) {
                        if analyzer.scanProgress > 0 {
                            Text(String(format: "%.0f%%", analyzer.scanProgress * 100))
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                            Text("\(analyzer.totalScanned) / \(analyzer.totalAssetsCount)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else {
                            Image(systemName: "photo.stack.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(
                                    LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                                )
                        }
                    }
                }
                
                VStack(spacing: 10) {
                    Text(analyzer.scanProgress > 0 ? "Analyzing Photo Library" : "Loading…")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text(analyzer.scanProgress > 0
                         ? "Reading file metadata, matching duplicates, and calculating iCloud sync states…"
                         : "Preparing to scan your photo library")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 48)
                }
                
                Spacer()
            }
        }
    }
    
    // Main App with Tabs
    private var mainAppView: some View {
        TabView(selection: $selectedTab) {
            DashboardView(selectedTab: $selectedTab, selectedFilter: $selectedFilter)
                .tabItem {
                    Label("Dashboard", systemImage: "chart.pie.fill")
                }
                .tag(0)
            
            GalleryView()
                .tabItem {
                    Label("Gallery", systemImage: "photo.fill")
                }
                .tag(1)
            
            TravelVlogView()
                .tabItem {
                    Label("Travel Vlog", systemImage: "map.fill")
                }
                .tag(2)
            
            PhotoListView(selectedFilter: $selectedFilter)
                .tabItem {
                    Label("Cleanup", systemImage: "trash.fill")
                }
                .tag(3)
        }
        .tint(.purple)
        .preferredColorScheme(.light)
    }
}
