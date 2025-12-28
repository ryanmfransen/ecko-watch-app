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
        sequencePlaybackTask?.cancel()
        score = 0
        sequence = []
        userSequence = []
        gameState = .computer
        activeQuadrant = nil
        touchStartQuadrant = nil
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
            try await Task.sleep(for: .seconds(0.8))
            for quadrant in sequence {
                if Task.isCancelled { return }
                await MainActor.run {
                    activeQuadrant = quadrant
                }
                
                await audioEngine.play(quadrant: quadrant)

                await MainActor.run {
                    activeQuadrant = nil
                }
                try await Task.sleep(for: .seconds(0.05))
            }
            await MainActor.run { gameState = .user }
        }
    }

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
            Task {
                await audioEngine.play(quadrant: currentPointQuadrant!)
            }
            WKInterfaceDevice.current().play(.click)
            return
        }
        
        if let locked = touchStartQuadrant {
            if currentPointQuadrant == locked {
                activeQuadrant = locked
            } else {
                activeQuadrant = nil
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
        
        // Fire haptic immediately (hardware-level, doesn't affect CPU)
        WKInterfaceDevice.current().play(.failure)

        Task {
            // 1. Play error sound and WAIT for it to finish
            await audioEngine.playError()
            
            // 2. ONLY NOW update the UI. The CPU is now free from audio duties
            // and can dedicate 100% of its power to the Blur effect.
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.5)) {
                    self.gameState = .gameOver
                }
            }
            
            // 3. Save score last (Disk I/O is also slow, keep it out of the animation window)
            if score > highScore {
                highScore = score
                UserDefaults.standard.set(highScore, forKey: "highScore")
            }
        }
    }
}

// MARK: - Main Game View
struct ContentView: View {
    @StateObject private var viewModel = GameViewModel()
    
    // ADDED: This is the environment variable that tracks app state
    @Environment(\.scenePhase) private var scenePhase

    @State private var hasInitialStarted = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                gameView(geometry: geometry)
                    .blur(radius: viewModel.gameState == .gameOver ? 4 : 0)
                
                if viewModel.gameState == .gameOver {
                    gameOverOverlay
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .onAppear {
            // 1. Cold Launch: Start the game once and mark it as done
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
                Text("GAME OVER")
                    .font(.system(size: 18, weight: .black, design: .monospaced))
                    .foregroundColor(.red)
                VStack(spacing: 2) {
                    Text("SCORE: \(viewModel.score)")
                    Text("BEST: \(viewModel.highScore)").foregroundColor(.yellow)
                }
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                Button("TRY AGAIN") { viewModel.startGame() }
                    .buttonStyle(.borderedProminent).tint(.red)
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
            resetButtonView(size: boardSize * 0.25)
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
        ZStack {
            Circle().fill(Color(white: 0.1)).overlay(Circle().stroke(Color.gray.opacity(0.5), lineWidth: 1))
            Image(systemName: "arrow.counterclockwise").font(.system(size: 18, weight: .bold)).foregroundColor(.white)
        }.frame(width: size, height: size)
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
