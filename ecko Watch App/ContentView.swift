import SwiftUI
import Combine
import AVFoundation
import WatchKit

// MARK: - Game State and Logic
class GameViewModel: ObservableObject {
    enum GameState {
        case computer, user, gameOver
    }

    enum Quadrant: CaseIterable {
        case green, red, yellow, blue
        var color: Color {
            switch self {
            case .green: return .green
            case .red: return .red
            case .yellow: return .yellow
            case .blue: return .blue
            }
        }
    }

    @Published var gameState: GameState = .computer
    @Published var sequence: [Quadrant] = []
    @Published var userSequence: [Quadrant] = []
    @Published var activeQuadrant: Quadrant?
    @Published var score = 0
    @Published var highScore: Int = 0
    @Published var isNewHighScore = false // Track celebration state
    
    @Published var selectedWaveform: ToneGenerator.Waveform = .square {
        didSet {
            audioEngine.setWaveform(selectedWaveform)
        }
    }
    
    private var touchStartQuadrant: Quadrant?
    private let audioEngine: AudioService = AudioEngine()
    private var sequencePlaybackTask: Task<Void, Error>?
    
    init() {
        self.highScore = UserDefaults.standard.integer(forKey: "highScore")
        let savedWaveform = UserDefaults.standard.integer(forKey: "selectedWaveform")
        self.selectedWaveform = ToneGenerator.Waveform(rawValue: savedWaveform) ?? .square
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)
    }

    var displayDuration: TimeInterval {
        max(0.1, 0.6 - (Double(score) / 20.0) * 0.9)
    }

    func startGame() {
        sequencePlaybackTask?.cancel()
        score = 0
        sequence = []
        userSequence = []
        gameState = .computer
        activeQuadrant = nil
        touchStartQuadrant = nil
        isNewHighScore = false
        audioEngine.stop()
        addToSequenceAndPlay()
    }

    private func addToSequenceAndPlay() {
        userSequence = []
        sequence.append(Quadrant.allCases.randomElement()!)
        playSequence()
    }

    func playSequence() {
            sequencePlaybackTask?.cancel()
            sequencePlaybackTask = Task {
                // Initial "Get Ready" pause
                try await Task.sleep(for: .seconds(0.8))
                
                for quadrant in sequence {
                    if Task.isCancelled { return }
                    
                    // 1. Start Light & Sound simultaneously
                    await MainActor.run { activeQuadrant = quadrant }
                    await audioEngine.play(quadrant: quadrant)
                    
                    // 2. The ONLY sleep that matters (Master Clock)
                    try await Task.sleep(for: .seconds(displayDuration))
                    
                    // 3. Stop Light & Sound simultaneously
                    await MainActor.run { activeQuadrant = nil }
                    audioEngine.stop()
                    
                    // 4. Short gap between notes
                    try await Task.sleep(for: .seconds(0.05))
                }
                
                // Hand control back to the user
                await MainActor.run { gameState = .user }
            }
        }

    // Helper to determine which quadrant was touched
    private func quadrant(for location: CGPoint, in size: CGSize) -> Quadrant? {
        let centerX = size.width / 2
        let centerY = size.height / 2
        let dx = location.x - centerX
        let dy = location.y - centerY
        let distance = sqrt(dx*dx + dy*dy)
        if distance < (size.width * 0.125) { return nil }
        
        if location.x < centerX && location.y < centerY { return .green }
        else if location.x >= centerX && location.y < centerY { return .red }
        else if location.x < centerX && location.y >= centerY { return .yellow }
        else if location.x >= centerX && location.y >= centerY { return .blue }
        return nil
    }

    func handleDragChanged(location: CGPoint, size: CGSize) {
        guard gameState == .user else { return }
        let currentPointQuadrant = quadrant(for: location, in: size)
        
        if touchStartQuadrant == nil && currentPointQuadrant != nil {
            touchStartQuadrant = currentPointQuadrant
            activeQuadrant = currentPointQuadrant
            
            // BRIDGE: Start a new Task to "enter" the async world
            Task {
                await audioEngine.play(quadrant: currentPointQuadrant!)
            }
            
            WKInterfaceDevice.current().play(.click)
            return
        }
        
        if let locked = touchStartQuadrant {
            if currentPointQuadrant == locked {
                // Finger is still inside the quadrant it started in
                activeQuadrant = locked
            } else {
                // Finger slid out - turn off light and sound
                activeQuadrant = nil
                audioEngine.stop()
            }
        }
    }

    func handleDragEnded(location: CGPoint, size: CGSize) {
        let centerX = size.width / 2
        let centerY = size.height / 2
        let distance = sqrt(pow(location.x - centerX, 2) + pow(location.y - centerY, 2))
        
        if distance < (size.width * 0.125) {
            startGame()
            return
        }

        guard gameState == .user, let locked = touchStartQuadrant else {
            touchStartQuadrant = nil
            return
        }

        userSequence.append(locked)
        activeQuadrant = nil
        audioEngine.stop()

        if userSequence.last != sequence[userSequence.count - 1] {
            endGame()
        } else if userSequence.count == sequence.count {
            score += 1
            gameState = .computer
            addToSequenceAndPlay()
        }
        touchStartQuadrant = nil
    }

    private func endGame() {
        sequencePlaybackTask?.cancel()
        WKInterfaceDevice.current().play(.failure)

        Task {
            // Check for high score BEFORE the UI changes
            let recordBroken = score > highScore
            
            // Await the hardware audio to finish so CPU is free for Blur
            await audioEngine.playError()
            
            await MainActor.run {
                if recordBroken {
                    self.isNewHighScore = true
                    self.highScore = self.score
                    UserDefaults.standard.set(self.highScore, forKey: "highScore")
                    WKInterfaceDevice.current().play(.success)
                }
                
                withAnimation(.easeInOut(duration: 0.5)) {
                    self.gameState = .gameOver
                }
            }
        }
    }
}

// MARK: - Celebration View
struct ConfettiParticle: View {
    @State private var xOffset: CGFloat = 0
    @State private var yOffset: CGFloat = 0
    @State private var opacity: Double = 1.0
    
    let color: Color
    
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .offset(x: xOffset, y: yOffset)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 2.0)) {
                    xOffset = CGFloat.random(in: -100...100)
                    yOffset = CGFloat.random(in: -150...50)
                    opacity = 0
                }
            }
    }
}

// MARK: - Main Game View
struct ContentView: View {
    @StateObject private var viewModel = GameViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasInitialStarted = false
    @State private var showSettings = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                gameView(geometry: geometry)
                    .blur(radius: viewModel.gameState == .gameOver ? 4 : 0)
                
                // Celebration layer
                if viewModel.isNewHighScore {
                    ForEach(0..<20, id: \.self) { i in
                        ConfettiParticle(color: [.yellow, .orange, .white].randomElement()!)
                    }
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
                
                if viewModel.gameState == .gameOver {
                    gameOverOverlay
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(viewModel: viewModel)
        }
        .onAppear {
            if !hasInitialStarted {
                viewModel.startGame()
                hasInitialStarted = true
            }
        }
        .onChange(of: scenePhase) { oldValue, newValue in
            if newValue == .active && oldValue == .background {
                viewModel.startGame()
            }
        }
        .ignoresSafeArea()
    }
    
    private var gameOverOverlay: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 8) {
                Text(viewModel.isNewHighScore ? "NEW RECORD!" : "GAME OVER")
                    .font(.system(size: 16, weight: .black, design: .monospaced))
                    .foregroundColor(viewModel.isNewHighScore ? .yellow : .red)
                
                VStack(spacing: 2) {
                    Text("SCORE: \(viewModel.score)")
                        .scaleEffect(viewModel.isNewHighScore ? 1.2 : 1.0)
                    Text("BEST: \(viewModel.highScore)").foregroundColor(.yellow)
                }
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                
                Button("TRY AGAIN") { viewModel.startGame() }
                    .buttonStyle(.borderedProminent)
                    .tint(viewModel.isNewHighScore ? .yellow : .red)
                    .foregroundColor(viewModel.isNewHighScore ? .black : .white)
                
                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
    }

    private func gameView(geometry: GeometryProxy) -> some View {
        let boardSize = min(geometry.size.width, geometry.size.height)
        return ZStack {
            Image("ecko_board")
                .resizable()
                .scaledToFit()
                .frame(width: boardSize, height: boardSize)
                .brightness(-0.2)
            
            if let active = viewModel.activeQuadrant {
                Image("ecko_board")
                    .resizable()
                    .scaledToFit()
                    .frame(width: boardSize, height: boardSize)
                    .brightness(0.2).contrast(1.2).saturation(1.5)
                    .mask(QuadrantClipShape(quadrant: active))
                    .shadow(color: active.color.opacity(0.7), radius: 15)
                    .blendMode(.screen)
            }
            resetButtonView(size: boardSize * 0.28)
        }
        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { v in viewModel.handleDragChanged(location: v.location, size: geometry.size) }
                .onEnded { v in viewModel.handleDragEnded(location: v.location, size: geometry.size) }
        )
    }

    private func resetButtonView(size: CGFloat) -> some View {
        let internalIconSize = size * 0.95 // Size for the main arrow
        
        return ZStack {
            // The Button Background
            Circle()
                .fill(Color(white: 0.12))
                .overlay(Circle().stroke(Color.gray.opacity(0.4), lineWidth: 1.5))
                .shadow(radius: 4)

                Image(systemName: "slider.horizontal.2.arrow.trianglehead.counterclockwise")
                    .font(.system(size: internalIconSize))
                    .foregroundColor(.gray.opacity(0.75))
                    .shadow(radius: 4)
                    .offset(y: -2.7)
        }
        .frame(width: size * 1.15, height: size * 1.15)
        .contentShape(Circle())
        // Gesture Logic
        .onTapGesture {
            WKInterfaceDevice.current().play(.click)
            viewModel.startGame()
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            WKInterfaceDevice.current().play(.directionDown) // Distinct haptic for settings
            showSettings = true
        }
    }
}

// MARK: - Shapes
struct QuadrantClipShape: Shape {
    let quadrant: GameViewModel.Quadrant
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = max(rect.width, rect.height)
        let startAngle: Angle = {
            switch quadrant {
            case .green: return .degrees(180); case .red: return .degrees(270)
            case .yellow: return .degrees(90); case .blue: return .degrees(0)
            }
        }()
        path.move(to: center)
        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: startAngle + .degrees(90), clockwise: false)
        path.closeSubpath()
        return path
    }
}

struct SettingsView: View {
    @ObservedObject var viewModel: GameViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 10) {
            Text("SOUND STYLE")
                .font(.system(.headline, design: .monospaced))
            
            // Picker is much better than Toggles for enums
            Picker("Waveform", selection: $viewModel.selectedWaveform) {
                ForEach(ToneGenerator.Waveform.allCases, id: \.self) { wave in
                    Text(wave.name).tag(wave)
                }
            }
            .pickerStyle(.wheel) // Optimized for Digital Crown
            .frame(height: 80)

            Button("DONE") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
