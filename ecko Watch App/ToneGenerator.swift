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
    private var currentWaveform: Waveform = .square
    private let sampleRate: Float
    private var phase: Float = 0.0
    private var amplitude: Float = 0.0 // Start silent

    init() {
        let retroFormat = AVAudioFormat(standardFormatWithSampleRate: 22050, channels: 1)!
        self.sampleRate = 22050
        setupEngine(format: retroFormat)
    }

    private func setupEngine(format: AVAudioFormat) {
        sourceNode = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let strongSelf = self else { return noErr }
            
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let localFreq = strongSelf.currentFrequency
            let sampleRate = strongSelf.sampleRate
            var localPhase = strongSelf.phase
            let phaseIncrement = localFreq / sampleRate
            
            // OPTIMIZATION: Capture amplitude once per buffer cycle
            let currentAmp = strongSelf.amplitude
            
            for frame in 0..<Int(frameCount) {
                // High/Low square wave logic using the captured amplitude
                let value: Float = (localPhase < 0.5) ? currentAmp : -currentAmp
                
                for buffer in ablPointer {
                    if let rawData = buffer.mData {
                        let buf = rawData.assumingMemoryBound(to: Float.self)
                        buf[frame] = value
                    }
                }
                
                localPhase += phaseIncrement
                if localPhase >= 1.0 { localPhase -= 1.0 }
            }
            
            strongSelf.phase = localPhase
            return noErr
        }
        
        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: nil)
        engine.prepare()
    }

    func play(frequency: Float, waveform: Waveform = .square) {
        self.currentFrequency = frequency
        self.currentWaveform = waveform
        
        self.amplitude = 0.3
        
        if !isPlaying {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
                try AVAudioSession.sharedInstance().setActive(true)
                try engine.start()
                isPlaying = true
            } catch {
                print("Could not start engine: \(error)")
            }
        }
    }

    func stop() {
        // Smoothly silence without tearing down the engine
        self.amplitude = 0.0
    }
}
