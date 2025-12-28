import SwiftUI
import Combine
import AVFoundation

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
    
    // NEW: Track where the touch started to prevent "sliding" into other colors
    private var touchStartQuadrant: Quadrant?
    
    private let audioEngine: AudioService = AudioEngine()
    private var sequencePlaybackTask: Task<Void, Error>?
    
    init() {
        self.highScore = UserDefaults.standard.integer(forKey: "highScore")
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)
    }

    var displayDuration: TimeInterval {
        max(0.1, 0.6 - (Double(score) / 20.0) * 0.9)
    }

    func startGame() {
        score = 0
        sequence = []
        userSequence = []
        gameState = .computer
        activeQuadrant = nil
        touchStartQuadrant = nil // Reset lock
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
            try await Task.sleep(for: .seconds(0.5))
            for quadrant in sequence {
                await MainActor.run {
                    activeQuadrant = quadrant
                    audioEngine.play(quadrant: quadrant)
                }
                try await Task.sleep(for: .seconds(displayDuration))
                await MainActor.run {
                    activeQuadrant = nil
                    audioEngine.stop()
                }
                try await Task.sleep(for: .seconds(0.05))
                if Task.isCancelled { return }
            }
            await MainActor.run { gameState = .user }
        }
    }

    // MARK: - Input Handling
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
            
            // 1. LOCK ON: If this is the start of the touch, lock the quadrant
            if touchStartQuadrant == nil && currentPointQuadrant != nil {
                touchStartQuadrant = currentPointQuadrant
                activeQuadrant = currentPointQuadrant
                audioEngine.play(quadrant: currentPointQuadrant!)
                // Optional: Add a heavy haptic here to simulate the "click" down
                WKInterfaceDevice.current().play(.click)
                return
            }
            
            // 2. VISUAL FEEDBACK:
            // If the finger is still over the LOCKED quadrant, keep it lit.
            // If the finger slides off, dim the light (like a physical button popping back up),
            // but WE DO NOT change the touchStartQuadrant.
            if let locked = touchStartQuadrant {
                if currentPointQuadrant == locked {
                    activeQuadrant = locked
                    // If the sound stopped because they slid off and back on, restart it
                    // (Depends on if your AudioEngine handles re-playing while already playing)
                } else {
                    activeQuadrant = nil
                    // We keep the sound playing or stop it based on your preference.
                    // Usually, physical buttons stop the tone when the contact is "broken".
                    audioEngine.stop()
                }
            }
        }

        func handleDragEnded(location: CGPoint, size: CGSize) {
            // Handle Reset separately as it's a special utility
            let centerX = size.width / 2
            let centerY = size.height / 2
            let distance = sqrt(pow(location.x - centerX, 2) + pow(location.y - centerY, 2))
            
            if distance < (size.width * 0.125) {
                touchStartQuadrant = nil
                startGame()
                return
            }

            guard gameState == .user else {
                touchStartQuadrant = nil
                return
            }

            // 3. REGISTER THE HIT:
            // We don't care where the finger is now. We only care what quadrant was "primed" at the start.
            if let locked = touchStartQuadrant {
                // Register the sequence hit
                userSequence.append(locked)
                
                // Clean up visuals/audio
                activeQuadrant = nil
                audioEngine.stop()

                // Logic Check
                if userSequence.last != sequence[userSequence.count - 1] {
                    endGame()
                } else if userSequence.count == sequence.count {
                    score += 1
                    gameState = .computer
                    addToSequenceAndPlay()
                }
            }
            
            // Clear the lock for the next touch
            touchStartQuadrant = nil
        }

    private func endGame() {
        gameState = .gameOver
        sequencePlaybackTask?.cancel()
        audioEngine.playError()
        if score > highScore {
            highScore = score
            UserDefaults.standard.set(highScore, forKey: "highScore")
        }
    }
}

// MARK: - Main Game View
import SwiftUI
import Combine
import AVFoundation

struct ContentView: View {
    @StateObject private var viewModel = GameViewModel()
    
    var body: some View {
        GeometryReader { geometry in
            // By wrapping the ZStack in a frame equal to geometry.size,
            // we force the center point to align with the screen center.
            ZStack {
                // 1. The main game board
                gameView(geometry: geometry)
                    .blur(radius: viewModel.gameState == .gameOver ? 4 : 0)
                
                // 2. Game Over Overlay
                if viewModel.gameState == .gameOver {
                    gameOverOverlay
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .onAppear(perform: viewModel.startGame)
        .ignoresSafeArea() // Keeps the board large, but we center it manually above
    }
    
    private var gameOverOverlay: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 8) {
                Text("GAME OVER")
                    .font(.system(size: 18, weight: .black, design: .monospaced))
                    .foregroundColor(.red)
                
                VStack(spacing: 2) {
                    Text("SCORE: \(viewModel.score)")
                    Text("BEST: \(viewModel.highScore)")
                        .foregroundColor(.yellow)
                }
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                
                Button("TRY AGAIN") {
                    viewModel.startGame()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
    }

    private func gameView(geometry: GeometryProxy) -> some View {
        // We use the smaller of the two dimensions to ensure a perfect circle
        let boardSize = min(geometry.size.width, geometry.size.height)
        
        return ZStack {
            // Background Board
            Image("ecko_board")
                .resizable()
                .scaledToFit()
                .frame(width: boardSize, height: boardSize)
                .brightness(-0.2)
            
            // Active Quadrant Highlight
            if let active = viewModel.activeQuadrant {
                Image("ecko_board")
                    .resizable()
                    .scaledToFit()
                    .frame(width: boardSize, height: boardSize)
                    .brightness(0.2)
                    .contrast(1.2)
                    .saturation(1.5)
                    .mask(QuadrantClipShape(quadrant: active))
                    .shadow(color: active.color.opacity(0.7), radius: 15)
                    .blendMode(.screen)
            }
            
            // Central Reset Button
            resetButtonView(size: boardSize * 0.25)
        }
        // Force the ZStack to the center of the GeometryReader
        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { v in
                    viewModel.handleDragChanged(location: v.location, size: geometry.size)
                }
                .onEnded { v in
                    viewModel.handleDragEnded(location: v.location, size: geometry.size)
                }
        )
    }

    private func resetButtonView(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color(white: 0.1))
                .overlay(Circle().stroke(Color.gray.opacity(0.5), lineWidth: 1))
            
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Shapes
struct QuadrantClipShape: Shape {
    let quadrant: GameViewModel.Quadrant
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let startAngle: Angle = {
            switch quadrant {
            case .green: return .degrees(180); case .red: return .degrees(270)
            case .yellow: return .degrees(90); case .blue: return .degrees(0)
            }
        }()
        path.move(to: center)
        path.addArc(center: center, radius: rect.width, startAngle: startAngle, endAngle: startAngle + .degrees(90), clockwise: false)
        path.closeSubpath()
        return path
    }
}
