import AVFoundation

class ToneGenerator {
    enum Waveform: Int, CaseIterable {
        case square = 0, sine = 1, sawtooth = 2, triangle = 3
        var name: String {
            switch self {
            case .square: return "Retro Square"
            case .sine: return "Modern Sine"
            case .sawtooth: return "Gritty Saw"
            case .triangle: return "Smooth Triangle"
            }
        }
    }

    private var engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode!
    private var isPlaying = false
    private var currentFrequency: Float = 440.0
    private var sampleRate: Float = 22050
    private var phase: Float = 0.0
    
    // NEW: masterVolume stays constant based on Crown
    var masterVolume: Float = 0.5
    // gate is 1.0 when a note is playing, 0.0 when stopped
    private var gate: Float = 0.0
    
    var selectedWaveform: Waveform = .square

    init() {
        let savedRaw = UserDefaults.standard.integer(forKey: "selectedWaveform")
        self.selectedWaveform = Waveform(rawValue: savedRaw) ?? .square
        let retroFormat = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1)!
        setupEngine(format: retroFormat)
    }

    private func setupEngine(format: AVAudioFormat) {
        sourceNode = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let strongSelf = self else { return noErr }
            
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let phaseIncrement = strongSelf.currentFrequency / strongSelf.sampleRate
            
            // MATH: Combined Volume
            let currentAmp = strongSelf.masterVolume * strongSelf.gate
            let waveform = strongSelf.selectedWaveform
            
            for frame in 0..<Int(frameCount) {
                var value: Float = 0
                let p = strongSelf.phase
                
                switch waveform {
                case .square: value = (p < 0.5) ? 1.0 : -1.0
                case .sine: value = sin(p * 2.0 * .pi)
                case .sawtooth: value = 2.0 * p - 1.0
                case .triangle: value = 4.0 * abs(p - 0.5) - 1.0
                }
                
                let sample = value * currentAmp
                
                for buffer in ablPointer {
                    let buf = buffer.mData!.assumingMemoryBound(to: Float.self)
                    buf[frame] = sample
                }
                
                strongSelf.phase += phaseIncrement
                if strongSelf.phase >= 1.0 { strongSelf.phase -= 1.0 }
            }
            return noErr
        }
        
        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: nil)
        engine.prepare()
    }

    func play(frequency: Float) {
        self.currentFrequency = frequency
        self.gate = 0.6 // Consistent note gain
        
        if !isPlaying {
            try? engine.start()
            isPlaying = true
        }
    }

    func stop() {
        self.gate = 0.0 // Close the gate, but keep masterVolume ready
    }
}
