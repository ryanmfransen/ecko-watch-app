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
    
    // Dependency Injection: The VM doesn't care how the sound is made
    private let toneGenerator = ToneGenerator()
    private let audioEngine: AudioService = AudioEngine()
    private var sequencePlaybackTask: Task<Void, Error>?
    
    init() {
        // This ensures the Watch speaker is ready for generated tones
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)
    }

    var displayDuration: TimeInterval {
        max(0.1, 1.0 - (Double(score) / 20.0) * 0.9)
    }

    func startGame() {
        score = 0
        sequence = []
        userSequence = []
        gameState = .computer
        activeQuadrant = nil
        toneGenerator.stop()
        addToSequenceAndPlay()
    }

    private func addToSequenceAndPlay() {
        sequence.append(Quadrant.allCases.randomElement()!)
        playSequence()
    }

    func playSequence() {
            sequencePlaybackTask?.cancel()
            sequencePlaybackTask = Task {
                try await Task.sleep(for: .seconds(1))
                for quadrant in sequence {
                    await MainActor.run {
                        activeQuadrant = quadrant
                        audioEngine.play(quadrant: quadrant) // Clean abstraction
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

    // MARK: - Robust User Input Handling

    private func quadrant(for location: CGPoint, in size: CGSize) -> Quadrant? {
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2

        if location.x < halfWidth && location.y < halfHeight {
            return .green
        } else if location.x >= halfWidth && location.y < halfHeight {
            return .red
        } else if location.x < halfWidth && location.y >= halfHeight {
            return .yellow
        } else if location.x >= halfWidth && location.y >= halfHeight {
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
                audioEngine.play(quadrant: newQuadrant) // Clean abstraction
            } else {
                activeQuadrant = nil
                audioEngine.stop()
            }
        }
    }

    func handleDragEnded(location: CGPoint, size: CGSize) {
        guard gameState == .user, let releasedQuadrant = activeQuadrant else {
            // If the game state isn't '.user' or the drag ends outside a quadrant, just stop the sound.
            if activeQuadrant != nil {
                activeQuadrant = nil
                toneGenerator.stop()
            }
            return
        }

        // Stop the tone and reset the visual state
        activeQuadrant = nil
        toneGenerator.stop()
        
        // Process the guess
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
        }
}


// MARK: - Main Game View
struct ContentView: View {
    @StateObject private var viewModel = GameViewModel()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if viewModel.gameState == .gameOver {
                    gameOverView
                } else {
                    gameView(geometry: geometry)
                }
            }
        }
        .onAppear(perform: viewModel.startGame)
        .onDisappear {
             // Ensure sound stops if the view disappears
            viewModel.startGame()
        }
        .ignoresSafeArea()
    }

    private var gameOverView: some View {
        VStack {
            Text("Game Over")
                .font(.title2)
                .padding()
            Text("Score: \(viewModel.score)")
                .font(.body)
                .padding(.bottom)
            Button("Restart") {
                viewModel.startGame()
            }
        }
    }

    private func gameView(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                QuadrantView(quadrant: .green, viewModel: viewModel)
                QuadrantView(quadrant: .red, viewModel: viewModel)
            }
            HStack(spacing: 0) {
                QuadrantView(quadrant: .yellow, viewModel: viewModel)
                QuadrantView(quadrant: .blue, viewModel: viewModel)
            }
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
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
}

// MARK: - Quadrant View
struct QuadrantView: View {
    let quadrant: GameViewModel.Quadrant
    @ObservedObject var viewModel: GameViewModel
    
    private var isActive: Bool {
        viewModel.activeQuadrant == quadrant
    }

    var body: some View {
        Rectangle()
            .fill(quadrant.color)
            .opacity(isActive ? 1.0 : 0.5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
