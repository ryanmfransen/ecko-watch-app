//
//  ContentView.swift
//  ecko Watch App
//
//  Created by Ryan Fransen on 2025-12-26.
//

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
            
            await MainActor.run {
                gameState = .user
            }
        }
    }

    // MARK: - Input Handling
    private func quadrant(for location: CGPoint, in size: CGSize) -> Quadrant? {
        let centerX = size.width / 2
        let centerY = size.height / 2
        
        // 1. Calculate distance from center (Pythagorean theorem)
        let dx = location.x - centerX
        let dy = location.y - centerY
        let distance = sqrt(dx*dx + dy*dy)
        
        // 2. Define the Dead Zone (Reset Circle)
        let deadZoneRadius = size.width * 0.125
        if distance < deadZoneRadius {
            return nil // Finger is inside the reset button
        }
        
        // 3. Logic for the four quadrants
        if location.x < centerX && location.y < centerY {
            return .green
        } else if location.x >= centerX && location.y < centerY {
            return .red
        } else if location.x < centerX && location.y >= centerY {
            return .yellow
        } else if location.x >= centerX && location.y >= centerY {
            return .blue
        }
        
        return nil
    }

    func handleDragChanged(location: CGPoint, size: CGSize) {
        guard gameState == .user else { return }
        let newQuadrant = quadrant(for: location, in: size)
        
        if activeQuadrant != newQuadrant {
            if let newQuadrant = newQuadrant {
                activeQuadrant = newQuadrant
                audioEngine.play(quadrant: newQuadrant)
            } else {
                activeQuadrant = nil
                audioEngine.stop()
            }
        }
    }

    func handleDragEnded(location: CGPoint, size: CGSize) {
        let centerX = size.width / 2
        let centerY = size.height / 2
        let dx = location.x - centerX
        let dy = location.y - centerY
        let distance = sqrt(dx*dx + dy*dy)
        
        let resetRadius = size.width * 0.125
        
        // UNIVERSAL RESET: If released in center, always restart
        if distance < resetRadius {
            startGame()
            return
        }

        // NORMAL GAMEPLAY: Handle quadrant selection
        guard gameState == .user, let releasedQuadrant = activeQuadrant else {
            activeQuadrant = nil
            audioEngine.stop()
            return
        }
        
        activeQuadrant = nil
        audioEngine.stop()
        
        userSequence.append(releasedQuadrant)

        if userSequence.last != sequence[userSequence.count - 1] {
            endGame()
            return
        }

        if userSequence.count == sequence.count {
            score += 1
            gameState = .computer
            addToSequenceAndPlay()
        }
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
struct ContentView: View {
    @StateObject private var viewModel = GameViewModel()
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 1. The main game board (Always visible)
                gameView(geometry: geometry)
                    .blur(radius: viewModel.gameState == .gameOver ? 4 : 0)
                
                // 2. Game Over Overlay
                if viewModel.gameState == .gameOver {
                    ZStack {
                        Color.black.opacity(0.6)
                            .ignoresSafeArea()
                        
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

                            Button(action: {
                                viewModel.startGame()
                            }) {
                                Text("TRY AGAIN")
                                    .font(.system(size: 12, weight: .bold))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.red.opacity(0.8))
                                    .cornerRadius(20)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
        }
        .onAppear(perform: viewModel.startGame)
        .ignoresSafeArea()
    }
    
    // MARK: - Game Board View
    private func gameView(geometry: GeometryProxy) -> some View {
        ZStack {
            Image("ecko_board")
                .resizable()
                .scaledToFit()
                .brightness(-0.2)
            
            if let active = viewModel.activeQuadrant {
                Image("ecko_board")
                    .resizable()
                    .scaledToFit()
                    .brightness(0.2)
                    .contrast(1.2)
                    .saturation(1.5)
                    .mask(QuadrantClipShape(quadrant: active))
                    .shadow(color: active.color.opacity(0.7), radius: 15)
                    .blendMode(.screen)
            }
            
            // Central Reset UI (Visual Only - logic handled by gesture)
            resetButtonView(size: geometry.size.width * 0.25)
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    viewModel.handleDragChanged(location: value.location, size: geometry.size)
                }
                .onEnded { value in
                    viewModel.handleDragEnded(location: value.location, size: geometry.size)
                }
        )
    }

    private func resetButtonView(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color(white: 0.1))
                .overlay(Circle().stroke(Color.gray.opacity(0.5), lineWidth: 1))
            
            VStack(spacing: 2) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 18, weight: .bold))
                //Text("RESET")
                //    .font(.system(size: 7, weight: .black))
            }
            .foregroundColor(.white)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Quadrant Clip Shape
struct QuadrantClipShape: Shape {
    let quadrant: GameViewModel.Quadrant
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        
        let startAngle: Angle = {
            switch quadrant {
            case .green:  return .degrees(180)
            case .red:    return .degrees(270)
            case .yellow: return .degrees(90)
            case .blue:   return .degrees(0)
            }
        }()
        
        path.move(to: center)
        path.addArc(center: center, radius: rect.width,
                    startAngle: startAngle, endAngle: startAngle + .degrees(90),
                    clockwise: false)
        path.closeSubpath()
        return path
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
