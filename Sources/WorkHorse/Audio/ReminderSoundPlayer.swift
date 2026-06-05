import AppKit
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
    private let moanResourceName = "horse-moan"
    private let badgeEarnedResourceName = "badge-earned"
    private let taskPauseResourceName = "task-pause"
    private let taskCompleteResourceName = "task-complete"
    private let taskStartResourceName = "task-start"
    private let audioResourceExtensions = ["mp3", "wav"]
    private var resourceSounds: [String: NSSound] = [:]

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
        startEngineIfNeeded()
    }

    /// 播放"牛马哀嚎"音效，作为专注提醒中用户点击"继续"按钮后的吐槽式反馈。
    ///
    /// 实现说明：原本想复用共享的 `AVAudioEngine` + `AVAudioPlayerNode`，
    /// 但实测在 11.025 kHz / MPEG-2.5 Layer III 这种非主流 MP3 上，
    /// `AVAudioFile.read` 可能抛出 `kAudioFileUnsupportedFileTypeError`，
    /// 而更关键的是：与 `FocusSynth` 共享同一个 `AVAudioEngine` 时，
    /// 在 `play()` 之后引擎会进入"全部采样渲染完→输出静音"状态，
    /// 后续 `moanPlayer.scheduleBuffer` 排进队列但引擎不主动 wake，导致无声。
    /// 改用 `NSSound`（走系统音频服务）独立播放，问题全消失。
    ///
    /// 资源文件：Sources/WorkHorse/Resources/horse-moan.mp3，
    /// 经 Package.swift 的 `.process("Resources")` 自动拷贝进 Bundle.module。
    /// 找不到资源或解码失败时静默回退 —— 弹窗行为本身不应被音效问题阻塞。
    func playMoan() {
        playBundledSound(resourceName: moanResourceName, debugLabel: "哀嚎")
    }

    /// 播放超级牛马勋章获得音效。
    ///
    /// 资源文件：Sources/WorkHorse/Resources/badge-earned.mp3。
    func playBadgeEarned() {
        playBundledSound(resourceName: badgeEarnedResourceName, debugLabel: "勋章获得")
    }

    /// 播放任务列表点击暂停后的反馈音效。
    ///
    /// 资源文件：Sources/WorkHorse/Resources/task-pause.mp3。
    func playTaskPaused() {
        playBundledSound(resourceName: taskPauseResourceName, debugLabel: "任务暂停")
    }

    /// 播放任务列表点击完成后的反馈音效。
    ///
    /// 资源文件：Sources/WorkHorse/Resources/task-complete.mp3。
    func playTaskCompleted() {
        playBundledSound(resourceName: taskCompleteResourceName, debugLabel: "任务完成")
    }

    /// 播放任务列表点击开始后的反馈音效。
    ///
    /// 资源文件：Sources/WorkHorse/Resources/task-start.mp3。
    func playTaskStarted() {
        playBundledSound(resourceName: taskStartResourceName, debugLabel: "任务开始")
    }

    private func startEngineIfNeeded() {
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

    /// 按优先级在 Bundle.module、Bundle.main、用户提供的源码相对路径里找资源。
    /// 拷贝到 Sources/WorkHorse/Resources 后 .process 会把它打进 Bundle.module，
    /// 找不到时回退到源码目录方便本地 swift run 调试。
    private func playBundledSound(resourceName: String, debugLabel: String) {
        guard let sound = loadBundledSound(resourceName: resourceName, debugLabel: debugLabel) else { return }
        sound.stop()
        sound.currentTime = 0
        sound.volume = 1.0
        sound.play()
    }

    // NSSound 在主线程同步构造 + play() 异步返回，不会阻塞 UI。
    // 缓存 NSSound 实例，避免本地变量释放后音频播放被系统提前终止。
    private func loadBundledSound(resourceName: String, debugLabel: String) -> NSSound? {
        if let sound = resourceSounds[resourceName] {
            return sound
        }

        guard let url = locateAudioResourceURL(resourceName: resourceName) else {
            #if DEBUG
            let names = audioResourceExtensions.map { "\(resourceName).\($0)" }.joined(separator: " / ")
            print("ReminderSoundPlayer: 找不到\(debugLabel)音频资源 \(names)")
            #endif
            return nil
        }

        guard let sound = NSSound(contentsOf: url, byReference: true) else {
            #if DEBUG
            print("ReminderSoundPlayer: NSSound 加载\(debugLabel)音频失败 -> \(url.path)")
            #endif
            return nil
        }

        resourceSounds[resourceName] = sound
        return sound
    }

    private func locateAudioResourceURL(resourceName: String) -> URL? {
        let candidates = audioResourceExtensions.flatMap { fileExtension in
            [
                Bundle.module.url(forResource: resourceName, withExtension: fileExtension),
                Bundle.main.url(forResource: resourceName, withExtension: fileExtension),
                Bundle.main.resourceURL?.appendingPathComponent("\(resourceName).\(fileExtension)"),
                URL(fileURLWithPath: "/Users/hukang/Documents/Work Horse/Sources/WorkHorse/Resources/\(resourceName).\(fileExtension)")
            ]
        }
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
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
