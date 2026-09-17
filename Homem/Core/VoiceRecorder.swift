import AVFoundation
import Observation

@MainActor @Observable final class VoiceRecorder {
    var recording = false
    var error: String?
    private var recorder: AVAudioRecorder?
    private var url: URL?
    private let speech = AVSpeechSynthesizer()
    func start() async {
        guard await AVAudioApplication.requestRecordPermission() else { error = "Allow microphone access in iOS Settings to record a voice message."; return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP]); try session.setActive(true)
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("Voice-\(UUID().uuidString).m4a")
            let recorder = try AVAudioRecorder(url: file, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue])
            guard recorder.record(forDuration: 300) else { throw ClientError.message("Could not start recording.".localized) }
            self.recorder = recorder; url = file; recording = true; error = nil
        } catch { self.error = error.localizedDescription }
    }
    func finish() -> URL? { recorder?.stop(); recording = false; try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation); let result = url; url = nil; recorder = nil; return result }
    func cancel() { if let url = finish() { try? FileManager.default.removeItem(at: url) }; speech.stopSpeaking(at: .immediate) }
    func speak(_ text: String) { speech.stopSpeaking(at: .immediate); let utterance = AVSpeechUtterance(string: text); speech.speak(utterance) }
}
