import AVFoundation

class ToneGenerator {
    enum Waveform {
        case sine
        case sawtooth
        case square
    }

    private var engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode!
    private var isPlaying = false

    private var currentFrequency: Float = 440.0
    private var currentWaveform: Waveform = .sine
    private let sampleRate: Float
    private var phase: Float = 0.0 // Phase now represents 0.0 to 1.0 of a cycle

    init() {
        let format = engine.outputNode.inputFormat(forBus: 0)
        self.sampleRate = Float(format.sampleRate)
        setupEngine(format: format)
    }

    private func setupEngine(format: AVAudioFormat) {
        sourceNode = AVAudioSourceNode(format: format) { [unowned self] _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            
            for frame in 0..<Int(frameCount) {
                var value: Float = 0
                
                // Mathematical generation based on waveform type
                switch self.currentWaveform {
                case .sine:
                    value = sin(self.phase * 2.0 * .pi)
                case .sawtooth:
                    // Ramp from -1 to 1: (phase * 2) - 1
                    value = (self.phase * 2.0) - 1.0
                case .square:
                    // If phase is less than 0.5, output 1.0; else output -1.0
                    value = (self.phase < 0.5) ? 1.0 : -1.0
                }
                
                // Increment phase based on frequency
                self.phase += self.currentFrequency / self.sampleRate
                if self.phase >= 1.0 {
                    self.phase -= 1.0
                }
                
                for buffer in ablPointer {
                    let bufferPointer = UnsafeMutableBufferPointer<Float>(buffer)
                    bufferPointer[frame] = value * 0.4 // Reduced volume slightly for harsh waves
                }
            }
            return noErr
        }
        
        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: nil)
        engine.prepare()
    }

    func play(frequency: Float, waveform: Waveform = .sine) {
        self.currentFrequency = frequency
        self.currentWaveform = waveform
        
        if !isPlaying {
            do {
                try engine.start()
                isPlaying = true
            } catch {
                print("Could not start engine: \(error)")
            }
        }
    }

    func stop() {
        if isPlaying {
            engine.stop()
            engine.reset() // Required to clear the sourceNode state
            isPlaying = false
            phase = 0 // Reset phase to avoid clicks on next start
        }
    }
}
