import Foundation

protocol AudioService {
    func play(quadrant: GameViewModel.Quadrant) async
    func playError() async  // Now properly async
    func stop()
}

class AudioEngine: AudioService {
    private let toneGenerator = ToneGenerator()

    private let frequencies: [GameViewModel.Quadrant: Float] = [
        .green: 391.99, .red: 329.63, .yellow: 261.63, .blue: 196.00
    ]
    
    private let errorFrequency:Float = 44.0

    func play(quadrant: GameViewModel.Quadrant) async {
        if let frequency = frequencies[quadrant] {
            await play(frequency: frequency)
        }
    }
    
    func play(frequency: Float) async {
        toneGenerator.play(frequency: frequency)
        
        // Wait for 0.4s for the tone to play out
        try? await Task.sleep(for: .seconds(0.4))
        
        toneGenerator.stop()
        
        // Give the audio buffer a tiny moment (1 frame) to clear
        try? await Task.sleep(for: .seconds(0.05))
    }

    // This function now controls the lifecycle of the error sound
    func playError() async {
        await play(frequency: errorFrequency)
    }

    func stop() {
        toneGenerator.stop()
    }
}
