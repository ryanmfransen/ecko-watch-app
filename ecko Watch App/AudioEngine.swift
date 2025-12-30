import Foundation

protocol AudioService {
    func play(quadrant: GameViewModel.Quadrant) async
    func playError() async
    func stop()
    func setWaveform(_ waveform: ToneGenerator.Waveform)
    func setVolume(_ volume: Float) // New method
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

    // Connect the Crown/ViewModel volume to the generator
    func setVolume(_ volume: Float) {
        toneGenerator.masterVolume = volume
    }

    func play(quadrant: GameViewModel.Quadrant) async {
        if let frequency = frequencies[quadrant] {
            toneGenerator.play(frequency: frequency)
        }
    }
    
    private func playWithDuration(frequency: Float, duration: Double) async {
        toneGenerator.play(frequency: frequency)
        try? await Task.sleep(for: .seconds(duration))
        toneGenerator.stop()
        try? await Task.sleep(for: .seconds(0.05))
    }

    func playError() async {
        await playWithDuration(frequency: errorFrequency, duration: 0.6)
    }

    func stop() {
        toneGenerator.stop()
    }
}
