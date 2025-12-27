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

class SimonAudioEngine: AudioService {
    private let toneGenerator = ToneGenerator()

    // Encapsulated Frequencies (Original 1978 Bugle Scale)
    private let frequencies: [GameViewModel.Quadrant: Float] = [
        .green: 391.99,  // G4
        .red: 329.63,    // E4 (Original standard)
        .yellow: 261.63, // C4
        .blue: 196.00    // G3 (Original standard)
    ]

    func play(quadrant: GameViewModel.Quadrant) {
        if let freq = frequencies[quadrant] {
            // Using .square for that authentic retro feel
            toneGenerator.play(frequency: freq, waveform: .square)
        }
    }

    func playError() {
        toneGenerator.play(frequency: 100.0, waveform: .sawtooth)
    }

    func stop() {
        toneGenerator.stop()
    }
}
