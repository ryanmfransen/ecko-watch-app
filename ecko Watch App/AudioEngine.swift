import Foundation

protocol AudioService {
    func play(quadrant: GameViewModel.Quadrant)
    func playError() async  // Now properly async
    func stop()
}

class AudioEngine: AudioService {
    private let toneGenerator = ToneGenerator()

    private let frequencies: [GameViewModel.Quadrant: Float] = [
        .green: 391.99, .red: 329.63, .yellow: 261.63, .blue: 196.00
    ]

    func play(quadrant: GameViewModel.Quadrant) {
        if let freq = frequencies[quadrant] {
            toneGenerator.play(frequency: freq)
        }
    }

    // This function now controls the lifecycle of the error sound
    func playError() async {
        toneGenerator.play(frequency: 42.0)
        
        // Wait for 0.6s for the "buzz" to play out
        // By awaiting here, we keep the CPU focus on the generator
        try? await Task.sleep(for: .seconds(0.6))
        
        toneGenerator.stop()
        
        // Give the audio buffer a tiny moment (1 frame) to clear
        // before we tell the UI to start blurring/rendering
        try? await Task.sleep(for: .seconds(0.05))
    }

    func stop() {
        toneGenerator.stop()
    }
}
