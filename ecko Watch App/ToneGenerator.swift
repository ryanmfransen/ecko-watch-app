import AVFoundation

class ToneGenerator {
    enum Waveform { case sine, sawtooth, square }

    private var engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode!
    private var isPlaying = false

    private var currentFrequency: Float = 440.0
    private var sampleRate: Float = 22050
    private var phase: Float = 0.0
    
    // Use an Atomic-style approach: amplitude is modified here, read in render block
    var amplitude: Float = 0.0

    init() {
        let retroFormat = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1)!
        setupEngine(format: retroFormat)
    }

    private func setupEngine(format: AVAudioFormat) {
        sourceNode = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let strongSelf = self else { return noErr }
            
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let phaseIncrement = strongSelf.currentFrequency / strongSelf.sampleRate
            let currentAmp = strongSelf.amplitude
            
            for frame in 0..<Int(frameCount) {
                // Square wave math
                let value: Float = (strongSelf.phase < 0.5) ? currentAmp : -currentAmp
                
                for buffer in ablPointer {
                    let buf = buffer.mData!.assumingMemoryBound(to: Float.self)
                    buf[frame] = value
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
        self.amplitude = 0.3
        
        if !isPlaying {
            try? engine.start()
            isPlaying = true
        }
    }

    func stop() {
        self.amplitude = 0.0
    }
}
