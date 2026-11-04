import Foundation
import llama
import os

public enum LlamaRunnerError: Error, LocalizedError, Equatable {
    case loadFailed(String)
    case contextFailed
    case notLoaded
    case promptTooLong
    case decodeFailed(Int32)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .loadFailed(let path): "The model at \(path) couldn't be loaded."
        case .contextFailed: "The model loaded but couldn't start."
        case .notLoaded: "The model isn't loaded."
        case .promptTooLong: "The text is too long for the model."
        case .decodeFailed(let status): "The model stopped with error \(status)."
        case .cancelled: "Cancelled."
        }
    }
}

/// One GGUF model loaded with llama.cpp, generating greedily on this Mac (Metal when available).
///
/// Every llama.cpp call runs on one serial queue, so the model and context are never touched from
/// two threads, and the async API never blocks Swift's cooperative pool.
public final class LlamaRunner: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.ruddvz.hushkey.llama", qos: .userInitiated)
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var loadedPath: String?
    private let cancelFlag = OSAllocatedUnfairLock(initialState: false)

    /// Silences llama.cpp's stderr logging and initializes its backends once per process.
    private static let backend: Void = {
        llama_log_set({ _, _, _ in }, nil)
        llama_backend_init()
    }()

    private struct WeakRunner: @unchecked Sendable { weak var runner: LlamaRunner? }
    private static let live = OSAllocatedUnfairLock(initialState: [WeakRunner]())

    public init() {
        Self.live.withLock { runners in
            runners.removeAll { $0.runner == nil }
            runners.append(WeakRunner(runner: self))
        }
    }

    /// Frees every loaded model now. Call when the app quits: ggml's Metal backend asserts if a
    /// model is still loaded when the process exits.
    public static func unloadAll() {
        let runners = live.withLock { $0.compactMap(\.runner) }
        for runner in runners { runner.unloadNow() }
    }

    deinit {
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
    }

    /// Loads the model at `path`. Does nothing if it's already loaded.
    public func load(path: String, contextLength: UInt32 = 4096) async throws {
        try await run { [self] in
            if loadedPath == path, context != nil { return }
            freeModel()
            _ = Self.backend
            var modelParams = llama_model_default_params()
            modelParams.n_gpu_layers = 999
            guard let loaded = llama_model_load_from_file(path, modelParams) else {
                throw LlamaRunnerError.loadFailed(path)
            }
            var contextParams = llama_context_default_params()
            contextParams.n_ctx = contextLength
            contextParams.n_batch = contextLength
            let threads = Int32(max(1, min(8, ProcessInfo.processInfo.activeProcessorCount - 2)))
            contextParams.n_threads = threads
            contextParams.n_threads_batch = threads
            contextParams.no_perf = true
            guard let created = llama_init_from_model(loaded, contextParams) else {
                llama_model_free(loaded)
                throw LlamaRunnerError.contextFailed
            }
            model = loaded
            context = created
            loadedPath = path
        }
    }

    public func unload() async {
        try? await run { [self] in freeModel() }
    }

    /// Frees the model now, after stopping a running answer. For app shutdown: ggml's Metal
    /// backend asserts if a model is still loaded when the process exits.
    public func unloadNow() {
        cancel()
        queue.sync { freeModel() }
    }

    /// Stops a running `generate` at its next token.
    public func cancel() {
        cancelFlag.withLock { $0 = true }
    }

    /// Greedy completion of `prompt` (special tokens such as `<|im_start|>` are parsed), up to
    /// `maxTokens` or the model's end-of-turn token.
    public func generate(prompt: String, maxTokens: Int) async throws -> String {
        cancelFlag.withLock { $0 = false }
        return try await withTaskCancellationHandler {
            try await run { [self] in try generateNow(prompt: prompt, maxTokens: maxTokens) }
        } onCancel: {
            cancel()
        }
    }

    /// A ChatML prompt (Qwen, SmolLM and most small instruct models) ending where the
    /// assistant's answer starts. `examples` become earlier user/assistant turns (few-shot), and
    /// `assistantPrefix` is pre-filled, e.g. an empty think block.
    public static func chatML(system: String, examples: [(user: String, assistant: String)] = [],
                              user: String, assistantPrefix: String = "") -> String {
        var prompt = "<|im_start|>system\n\(system)<|im_end|>\n"
        for example in examples {
            prompt += "<|im_start|>user\n\(example.user)<|im_end|>\n<|im_start|>assistant\n\(example.assistant)<|im_end|>\n"
        }
        return prompt + "<|im_start|>user\n\(user)<|im_end|>\n<|im_start|>assistant\n" + assistantPrefix
    }

    // MARK: - On the queue

    private func run<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try work() }) }
        }
    }

    private func freeModel() {
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
        context = nil
        model = nil
        loadedPath = nil
    }

    private func generateNow(prompt: String, maxTokens: Int) throws -> String {
        guard let context, let model else { throw LlamaRunnerError.notLoaded }
        let vocab = llama_model_get_vocab(model)
        llama_memory_clear(llama_get_memory(context), true)

        var tokens = tokenize(prompt, vocab: vocab)
        guard !tokens.isEmpty, tokens.count + maxTokens <= Int(llama_n_ctx(context)) else {
            throw LlamaRunnerError.promptTooLong
        }
        let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params())
        defer { llama_sampler_free(sampler) }
        llama_sampler_chain_add(sampler, llama_sampler_init_greedy())

        var status = tokens.withUnsafeMutableBufferPointer {
            llama_decode(context, llama_batch_get_one($0.baseAddress, Int32($0.count)))
        }
        guard status == 0 else { throw LlamaRunnerError.decodeFailed(status) }

        var bytes: [UInt8] = []
        for _ in 0..<maxTokens {
            if cancelFlag.withLock({ $0 }) { throw LlamaRunnerError.cancelled }
            var token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) { break }
            bytes += piece(token, vocab: vocab)
            status = withUnsafeMutablePointer(to: &token) { llama_decode(context, llama_batch_get_one($0, 1)) }
            guard status == 0 else { throw LlamaRunnerError.decodeFailed(status) }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func tokenize(_ text: String, vocab: OpaquePointer?) -> [llama_token] {
        let length = Int32(text.utf8.count)
        var buffer = [llama_token](repeating: 0, count: Int(length) + 16)
        var count = llama_tokenize(vocab, text, length, &buffer, Int32(buffer.count), true, true)
        if count < 0 {
            buffer = [llama_token](repeating: 0, count: Int(-count))
            count = llama_tokenize(vocab, text, length, &buffer, Int32(buffer.count), true, true)
        }
        return Array(buffer.prefix(Int(max(0, count))))
    }

    private func piece(_ token: llama_token, vocab: OpaquePointer?) -> [UInt8] {
        var buffer = [CChar](repeating: 0, count: 64)
        var count = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        if count < 0 {
            buffer = [CChar](repeating: 0, count: Int(-count))
            count = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        }
        return buffer.prefix(Int(max(0, count))).map { UInt8(bitPattern: $0) }
    }
}
