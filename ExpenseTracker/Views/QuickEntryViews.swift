import SwiftUI
import Speech
import AVFoundation
import Vision
import VisionKit

// MARK: - Voice entry

/// Hold-free voice capture: tap the mic, say "2.5 dinars coffee at Costa", tap again.
struct VoiceEntryView: View {
    /// When set (opened from the add screen), the result fills that form instead of opening a new one.
    var onResult: ((ExpensePrefill) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speech = SpeechCapture()
    @State private var prefill: ExpensePrefill?

    var body: some View {
        NavigationStack {
            if let prefill {
                ExpenseEditView(expense: nil, presentedAsSheet: false, prefill: prefill)
            } else {
                recorder
            }
        }
    }

    private var recorder: some View {
            VStack(spacing: 24) {
                Spacer()
                Text(speech.transcript.isEmpty ? "Try: “2.5 dinars coffee at Costa”" : speech.transcript)
                    .font(.title3.weight(.medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(speech.transcript.isEmpty ? .secondary : .primary)
                    .padding(.horizontal, 24)
                    .animation(.snappy, value: speech.transcript)

                Button {
                    speech.isRecording ? finish() : speech.start()
                } label: {
                    ZStack {
                        Circle().fill(Theme.emerald.opacity(0.15))
                            .frame(width: 150, height: 150)
                            .scaleEffect(speech.isRecording ? 1 + speech.level * 0.35 : 1)
                            .animation(.easeOut(duration: 0.12), value: speech.level)
                        Circle().fill(speech.isRecording ? Theme.danger.gradient : Theme.emerald.gradient)
                            .frame(width: 96, height: 96)
                        Image(systemName: speech.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact, trigger: speech.isRecording)

                Text(speech.error ?? (speech.isRecording ? "Listening… tap to finish" : "Tap the mic and speak"))
                    .font(.footnote)
                    .foregroundStyle(speech.error == nil ? Color.secondary : Theme.danger)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .themedBackground()
            .navigationTitle("Speak an expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { speech.stop(); dismiss() } }
            }
            .onAppear { speech.start() }
            .onDisappear { speech.stop() }
    }

    private func finish() {
        speech.stop()
        let text = speech.transcript.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let p = VoiceParser.parse(text, defaultCurrency: AppSettings.defaultCurrency)
        if let onResult {
            onResult(p)
            dismiss()
        } else {
            withAnimation(.snappy) { prefill = p }
        }
    }
}

@MainActor
final class SpeechCapture: ObservableObject {
    @Published var transcript = ""
    @Published var isRecording = false
    @Published var level: CGFloat = 0
    @Published var error: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func start() {
        error = nil
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                guard status == .authorized else {
                    self.error = "Allow Speech Recognition in Settings to use voice entry."
                    return
                }
                AVAudioApplication.requestRecordPermission { granted in
                    Task { @MainActor in
                        if granted { self.begin() } else { self.error = "Allow microphone access in Settings." }
                    }
                }
            }
        }
    }

    private func begin() {
        guard let recognizer, recognizer.isAvailable else {
            error = "Speech recognition isn't available right now."
            return
        }
        stop()
        transcript = ""
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
            self.request = request

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                request.append(buffer)
                let level = Self.rms(buffer)
                Task { @MainActor in self?.level = level }
            }
            engine.prepare()
            try engine.start()
            isRecording = true

            task = recognizer.recognitionTask(with: request) { [weak self] result, err in
                Task { @MainActor in
                    guard let self else { return }
                    if let result { self.transcript = result.bestTranscription.formattedString }
                    if err != nil || (result?.isFinal ?? false) { self.stopAudio() }
                }
            }
        } catch {
            self.error = "Couldn't start recording."
            stop()
        }
    }

    func stop() {
        request?.endAudio()
        task?.cancel()
        task = nil
        stopAudio()
    }

    private func stopAudio() {
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        request = nil
        isRecording = false
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated private static func rms(_ buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<n { sum += data[i] * data[i] }
        return CGFloat(min(1, sqrt(sum / Float(n)) * 12))
    }
}

// MARK: - Receipt scanning

/// Opens the document camera, reads the receipt with on-device text recognition,
/// then shows the editor pre-filled with merchant, total and date.
struct ReceiptScanView: View {
    var onResult: ((ExpensePrefill) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var prefill: ExpensePrefill?
    @State private var processing = false
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Group {
                if let prefill {
                    ExpenseEditView(expense: nil, presentedAsSheet: false, prefill: prefill)
                } else if processing {
                    VStack(spacing: 14) {
                        ProgressView().controlSize(.large)
                        Text("Reading receipt…").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .themedBackground()
                } else if !VNDocumentCameraViewController.isSupported {
                    ContentUnavailableView("Camera not available", systemImage: "camera.fill",
                                           description: Text("Receipt scanning needs the iPhone camera."))
                } else {
                    DocumentCamera { images in
                        guard !images.isEmpty else { dismiss(); return }
                        processing = true
                        Task {
                            let lines = await ReceiptOCR.lines(from: images)
                            var p = ReceiptParser.parse(lines: lines, defaultCurrency: AppSettings.defaultCurrency)
                            p.photo = images.first?.jpegData(compressionQuality: 0.6)   // keep the receipt as the attachment
                            processing = false
                            if let onResult {
                                onResult(p)
                                dismiss()
                            } else {
                                prefill = p
                            }
                        }
                    }
                    .ignoresSafeArea()
                    .toolbar(.hidden, for: .navigationBar)
                }
            }
        }
    }
}

private struct DocumentCamera: UIViewControllerRepresentable {
    let onFinish: ([UIImage]) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([UIImage]) -> Void
        init(onFinish: @escaping ([UIImage]) -> Void) { self.onFinish = onFinish }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            onFinish((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { onFinish([]) }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { onFinish([]) }
    }
}

enum ReceiptOCR {
    /// On-device text recognition, returned top-to-bottom as lines.
    static func lines(from images: [UIImage]) async -> [String] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var all: [String] = []
                for image in images {
                    guard let cg = image.cgImage else { continue }
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.usesLanguageCorrection = false
                    try? VNImageRequestHandler(cgImage: cg).perform([request])
                    let observations = (request.results ?? []).sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
                    all += observations.compactMap { $0.topCandidates(1).first?.string }
                }
                continuation.resume(returning: all)
            }
        }
    }
}
