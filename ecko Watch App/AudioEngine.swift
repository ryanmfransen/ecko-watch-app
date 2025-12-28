import Foundation

protocol AudioService {
    func play(quadrant: GameViewModel.Quadrant) async
    func playError() async
    func stop()
    func setWaveform(_ waveform: ToneGenerator.Waveform)
}

class AudioEngine: AudioService {
    private let toneGenerator = ToneGenerator()

    private let frequencies: [GameViewModel.Quadrant: Float] = [
        .green: 391.99, .red: 329.63, .yellow: 261.63, .blue: 196.00
    ]
    
    private let errorFrequency: Float = 44.0
    
    func setWaveform(_ waveform: ToneGenerator.Waveform) {
        toneGenerator.selectedWaveform = waveform
        UserDefaults.standard.set(waveform.rawValue, forKey: "selectedWaveform")
    }

    // 1. Instant Play: Used by the Game Loop and User Touches
    // This returns IMMEDIATELY after telling the hardware to start.
    func play(quadrant: GameViewModel.Quadrant) async {
        if let frequency = frequencies[quadrant] {
            toneGenerator.play(frequency: frequency)
        }
    }
    
    // 2. Duration Play: Specifically for the Error sequence
    // This is private because only the AudioEngine needs to manage this internal "sleep"
    private func playWithDuration(frequency: Float, duration: Double) async {
        toneGenerator.play(frequency: frequency)
        
        // Logical pause: The CPU yields while the sound plays
        try? await Task.sleep(for: .seconds(duration))
        
        toneGenerator.stop()
        
        // Small buffer clearance
        try? await Task.sleep(for: .seconds(0.05))
    }

    // 3. The Error Call: Uses the duration-aware helper
    func playError() async {
        await playWithDuration(frequency: errorFrequency, duration: 0.6)
    }

    func stop() {
        toneGenerator.stop()
    }
}
