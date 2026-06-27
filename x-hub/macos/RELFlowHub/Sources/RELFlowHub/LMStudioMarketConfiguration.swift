import Foundation

extension LMStudioMarketBridge {
    static let huggingFaceBaseURL = "https://huggingface.co"
    static let huggingFaceFallbackBaseURLs = ["https://hf-mirror.com"]
    static let huggingFaceBasePreferenceFileName = "huggingface_base_preference.json"
    static let defaultDiscoverQueries = ["vision", "coder", "embedding", "voice", "qwen", "llama", "glm"]
    static let categoryQueryExpansions: [String: [String]] = [
        "chat": ["chat", "instruct", "assistant", "qwen", "llama", "glm"],
        "vision": ["vision", "vl", "llava", "glm-4.6v", "qwen2-vl", "qwen3-vl", "florence", "ocr", "image"],
        "ocr": ["ocr", "document", "trocr", "donut", "florence"],
        "coding": ["coder", "coding", "code", "qwen-coder", "deepseek-coder"],
        "embedding": ["embedding", "embed", "bge", "gte", "qwen-embedding"],
        "voice": ["tts", "voice", "text-to-speech", "kokoro", "melo", "parler", "bark", "speecht5", "f5-tts", "cosyvoice"],
        "speech": ["speech", "audio", "asr", "whisper"],
    ]
    static let categoryQueryAliases: [String: String] = [
        "assistant": "chat",
        "chat": "chat",
        "general": "chat",
        "instruct": "chat",
        "llm": "chat",
        "text": "chat",
        "asr": "speech",
        "audio": "speech",
        "speech": "speech",
        "tts": "voice",
        "text-to-speech": "voice",
        "speech-synthesis": "voice",
        "speechsynthesis": "voice",
        "transcribe": "speech",
        "transcription": "speech",
        "voice": "voice",
        "kokoro": "voice",
        "melo": "voice",
        "parler": "voice",
        "parler-tts": "voice",
        "bark": "voice",
        "speecht5": "voice",
        "f5-tts": "voice",
        "f5tts": "voice",
        "cosyvoice": "voice",
        "chattts": "voice",
        "whisper": "speech",
        "code": "coding",
        "coder": "coding",
        "coding": "coding",
        "dev": "coding",
        "programming": "coding",
        "document": "ocr",
        "doc": "ocr",
        "ocr": "ocr",
        "pdf": "ocr",
        "scan": "ocr",
        "embed": "embedding",
        "embedding": "embedding",
        "embeddings": "embedding",
        "rerank": "embedding",
        "retrieval": "embedding",
        "vector": "embedding",
        "image": "vision",
        "images": "vision",
        "multimodal": "vision",
        "photo": "vision",
        "vision": "vision",
        "vl": "vision",
        "vlm": "vision",
    ]
    static let categoryTagFilters: [String: Set<String>] = [
        "chat": ["Text"],
        "vision": ["Vision", "OCR"],
        "ocr": ["OCR"],
        "coding": ["Coding"],
        "embedding": ["Embedding"],
        "voice": ["Voice"],
        "speech": ["Speech"],
    ]
    static let curatedRecommendationBucketsBase: [MarketRecommendationBucket] = [
        MarketRecommendationBucket(tag: "Text", weight: 6),
        MarketRecommendationBucket(tag: "Coding", weight: 4),
        MarketRecommendationBucket(tag: "Embedding", weight: 4),
    ]
    static let curatedRecommendationBucketsHelper: [MarketRecommendationBucket] = [
        MarketRecommendationBucket(tag: "Vision", weight: 4),
        MarketRecommendationBucket(tag: "Voice", weight: 3),
        MarketRecommendationBucket(tag: "OCR", weight: 2),
    ]
    static let repoExcludeTags: Set<String> = ["gguf", "onnx", "diffusers"]
    static let discoveryTimeout: TimeInterval = 8.0
    static let terminalEscapeRegex = try? NSRegularExpression(
        pattern: #"\u{001B}\[[0-?]*[ -/]*[@-~]"#,
        options: []
    )
    static let nonPrintableControlRegex = try? NSRegularExpression(
        pattern: #"[\u{0000}-\u{0008}\u{000B}\u{000C}\u{000E}-\u{001F}\u{007F}]"#,
        options: []
    )
    static let modelKeySearchRegex = try? NSRegularExpression(
        pattern: #"([A-Za-z0-9._-]+/[A-Za-z0-9._:+-]+)"#,
        options: []
    )
    static let matchingStopWords: Set<String> = [
        "mlx",
        "gguf",
        "model",
        "models",
        "local",
        "hub",
        "4bit",
        "8bit",
        "bf16",
        "fp16",
        "fp32",
        "q4",
        "q8",
    ]

}
