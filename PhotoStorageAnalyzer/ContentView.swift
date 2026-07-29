import SwiftUI
import Photos

struct ContentView: View {
    @EnvironmentObject var analyzer: PhotoAnalyzer
    @State private var selectedTab = 0
    @State private var selectedFilter: AppFilter = .all
    @State private var spinAngle: Double = 0
    @State private var isAnimating = false
    
    var body: some View {
        Group {
            switch analyzer.authorizationStatus {
            case .notDetermined:
                welcomeView
            case .denied, .restricted:
                permissionDeniedView
            case .authorized, .limited:
                if !analyzer.isFirstScanCompleted {
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
        .animation(.easeInOut(duration: 0.3), value: analyzer.isFirstScanCompleted)
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
    
    // Loading / Scanning View (Premium Splash View Interface)
    private var scanningView: some View {
        ZStack {
            // Soft premium background gradient
            LinearGradient(
                colors: [Color.white, Color(red: 0.96, green: 0.96, blue: 0.98)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            // Soft background grid pattern for visual texture
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Circle()
                        .fill(Color.purple.opacity(0.04))
                        .frame(width: 300, height: 300)
                        .blur(radius: 50)
                        .offset(x: 100, y: 100)
                }
            }
            .ignoresSafeArea()
            
            VStack(spacing: 36) {
                Spacer()
                
                // Centered Brand Icon & Pulsing Rings
                ZStack {
                    // Pulsing Outer Aura
                    Circle()
                        .stroke(Color.purple.opacity(0.15), lineWidth: 1)
                        .frame(width: 150, height: 150)
                        .scaleEffect(isAnimating ? 1.12 : 0.98)
                        .opacity(isAnimating ? 0.0 : 1.0)
                    
                    Circle()
                        .fill(Color.purple.opacity(0.03))
                        .frame(width: 110, height: 110)
                        .scaleEffect(isAnimating ? 1.05 : 0.95)
                    
                    // App Logo with modern gradient & shadow
                    Image(systemName: "photo.stack.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .purple.opacity(0.25), radius: 10, y: 5)
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                        isAnimating = true
                    }
                }
                
                VStack(spacing: 12) {
                    Text("Photo Storage Analyzer")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundColor(.primary)
                    
                    if analyzer.totalAssetsCount > 0 {
                        Text("Analyzing photo library metadata…")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(.secondary)
                    } else {
                        Text("Preparing storage database…")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
                
                // Elegant loading bar (smooth capsule track)
                VStack(spacing: 8) {
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.purple.opacity(0.08))
                            .frame(height: 6)
                        
                        if analyzer.scanProgress > 0 {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [.purple, .blue],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(12, 240 * CGFloat(analyzer.scanProgress)), height: 6)
                                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: analyzer.scanProgress)
                        } else {
                            // Shimmer indicator
                            Capsule()
                                .fill(LinearGradient(colors: [.purple.opacity(0.3), .blue.opacity(0.3)], startPoint: .leading, endPoint: .trailing))
                                .frame(width: 40, height: 6)
                                .offset(x: isAnimating ? 200 : 0)
                                .animation(.linear(duration: 1.5).repeatForever(autoreverses: false), value: isAnimating)
                        }
                    }
                    .frame(width: 240)
                    
                    if analyzer.totalAssetsCount > 0 {
                        Text("\(analyzer.totalScanned) of \(analyzer.totalAssetsCount) files processed")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.8))
                    } else {
                        Text("Initializing connection…")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }
                
                Spacer()
                
                Text("EXODE DESIGN SYSTEM")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.4))
                    .tracking(2.0)
                    .padding(.bottom, 20)
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
