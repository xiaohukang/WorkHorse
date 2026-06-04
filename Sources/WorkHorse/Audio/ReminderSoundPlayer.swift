import AVFoundation
import Foundation

/// 实时合成并播放轻快放松的专注提醒提示音。
///
/// 设计目标：
/// - 不依赖任何外部音频文件，零资源、零加载；
/// - 两声"叮咚"上行（C5 → E5，大三度），听感明亮但不刺耳；
/// - 总时长 ≈ 0.6s，避免打扰同事；
/// - 复用共享的 `AVAudioEngine`，避免每次弹窗都冷启动音频子系统。
final class ReminderSoundPlayer {

    static let shared = ReminderSoundPlayer()

    private let engine = AVAudioEngine()
    private let sampleRate: Double = 44_100
    private let synth: FocusSynth

    private init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let synth = FocusSynth(sampleRate: sampleRate)
        self.synth = synth

        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            return synth.render(frameCount: Int(frameCount), audioBufferList: audioBufferList)
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
    }

    /// 播放专注提醒的"叮咚"提示音。如果引擎未启动会先启动，每次播放都会重新生成样本。
    func play() {
        synth.resetForNewPlayback()
        do {
            if !engine.isRunning {
                try engine.start()
            }
        } catch {
            // 引擎启动失败时静默回退；弹窗本身仍然会展示。
            #if DEBUG
            print("ReminderSoundPlayer: 启动音频引擎失败 -> \(error)")
            #endif
        }
    }
}

/// 单个音的描述。
struct FocusTone {
    let frequency: Double
    let startFrame: Int
    let durationFrames: Int
}

/// 合成器内部状态，单独成为一个 final class 便于在闭包中捕获引用，
/// 避免在 `ReminderSoundPlayer.init` 完成前通过 self 访问属性。
final class FocusSynth {
    let sampleRate: Double
    private let lock = NSLock()
    private var tones: [FocusTone] = []
    private var totalFrames: Int = 0
    private var elapsed: Int = 0

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
    }

    /// 重新设置两声"叮咚"参数并把播放头清零。
    func resetForNewPlayback() {
        let toneFrames = Int(sampleRate * 0.22)             // 单声持续时间
        let gapFrames = Int(sampleRate * 0.08)              // 两声之间的间隔
        let firstStart = 0
        let secondStart = firstStart + toneFrames + gapFrames
        let tail = Int(sampleRate * 0.15)                   // 末尾静音缓冲

        lock.lock()
        tones = [
            FocusTone(frequency: 523.25, startFrame: firstStart, durationFrames: toneFrames),   // C5
            FocusTone(frequency: 659.25, startFrame: secondStart, durationFrames: toneFrames)    // E5
        ]
        totalFrames = secondStart + toneFrames + tail
        elapsed = 0
        lock.unlock()
    }

    /// 实时音频渲染回调。
    func render(frameCount: Int, audioBufferList: UnsafePointer<AudioBufferList>) -> OSStatus {
        let ablPointer = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: audioBufferList))
        guard let buffer = ablPointer.first else { return noErr }
        let pointer = buffer.mData?.assumingMemoryBound(to: Float.self)
        guard let pointer else { return noErr }

        lock.lock()
        let startFrame = elapsed
        let localTones = tones
        let total = totalFrames
        lock.unlock()

        let endFrame = startFrame + frameCount

        for i in 0..<frameCount {
            let globalFrame = startFrame + i
            if globalFrame >= total {
                pointer[i] = 0
            } else {
                pointer[i] = sample(frame: globalFrame, tones: localTones)
            }
        }

        lock.lock()
        elapsed = endFrame
        lock.unlock()
        return noErr
    }

    /// 计算单帧采样值：把每一声铃音的相位 + 衰减包络叠加。
    private func sample(frame: Int, tones: [FocusTone]) -> Float {
        var value: Double = 0
        for tone in tones {
            let local = frame - tone.startFrame
            if local < 0 || local >= tone.durationFrames { continue }
            let normalized = Double(local) / Double(tone.durationFrames)
            // 指数衰减包络：起音快、收尾柔和
            let envelope = exp(-3.2 * normalized) * (1 - exp(-90.0 * normalized))
            // 二次谐波轻微混合，让音色更接近"风铃"而不是纯正弦
            let basePhase = Double(local) * 2.0 * .pi * tone.frequency / sampleRate
            let fundamental = sin(basePhase)
            let harmonic = sin(basePhase * 2) * 0.18
            value += (fundamental + harmonic) * envelope
        }
        return Float(value * 0.55)
    }
}
