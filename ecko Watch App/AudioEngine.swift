//
//  SimonAudioEngine.swift
//  ecko Watch App
//
//  Created by Ryan Fransen on 2025-12-26.
//

import Foundation

protocol AudioService {
    func play(quadrant: GameViewModel.Quadrant)
    func playError()
    func stop()
}

class AudioEngine: AudioService {
    private let toneGenerator = ToneGenerator()

    // Encapsulated Frequencies (Original 1978 Bugle Scale)
    private let frequencies: [GameViewModel.Quadrant: Float] = [
        .green: 391.99,  // G4
        .red: 329.63,    // E4
        .yellow: 261.63, // C4
        .blue: 196.00    // G3
    ]

    func play(quadrant: GameViewModel.Quadrant) {
        if let freq = frequencies[quadrant] {
            // Using .square for that authentic retro feel
            toneGenerator.play(frequency: freq, waveform: .square)
        }
    }

    func playError() {
        toneGenerator.play(frequency: 42.0, waveform: .square)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.stop()
        }
    }

    func stop() {
        toneGenerator.stop()
    }
}
