/// Represents an on-device local model available for navigation and task planning.
class LocalModelInfo {
  final String id;
  final String name;
  final String description;
  final String filename;
  final int sizeInBytes;
  final String downloadUrl;
  final List<String> fallbackUrls;
  final String parameterCount;
  final String quantization;
  final int contextLength;
  final int recommendedThreads;
  final bool isDefault;

  const LocalModelInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.filename,
    required this.sizeInBytes,
    required this.downloadUrl,
    this.fallbackUrls = const [],
    required this.parameterCount,
    required this.quantization,
    this.contextLength = 2048,
    this.recommendedThreads = 4,
    this.isDefault = false,
  });

  String get formattedSize {
    if (sizeInBytes >= 1024 * 1024 * 1024) {
      return '${(sizeInBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    return '${(sizeInBytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }

  /// Preset catalog of vetted on-device navigation models
  static const List<LocalModelInfo> availableModels = [
    LocalModelInfo(
      id: 'smollm2_1_35b_q4',
      name: 'SmolLM2 1.35B Instruct (Recommended)',
      description:
          'Fast, accurate task planning and UI navigation optimized for mobile devices.',
      filename: 'smollm2-1.35b-instruct-q4_k_m.gguf',
      sizeInBytes: 742000000, // ~742 MB
      downloadUrl:
          'https://huggingface.co/HuggingFaceTB/SmolLM2-1.35B-Instruct-GGUF/resolve/main/smollm2-1.35b-instruct-q4_k_m.gguf?download=true',
      fallbackUrls: [
        'https://hf-mirror.com/HuggingFaceTB/SmolLM2-1.35B-Instruct-GGUF/resolve/main/smollm2-1.35b-instruct-q4_k_m.gguf?download=true',
        'https://huggingface.co/bartowski/SmolLM2-1.35B-Instruct-GGUF/resolve/main/SmolLM2-1.35B-Instruct-Q4_K_M.gguf?download=true',
        'https://hf-mirror.com/bartowski/SmolLM2-1.35B-Instruct-GGUF/resolve/main/SmolLM2-1.35B-Instruct-Q4_K_M.gguf?download=true',
      ],
      parameterCount: '1.35B',
      quantization: 'Q4_K_M (4-bit)',
      contextLength: 2048,
      recommendedThreads: 4,
      isDefault: true,
    ),
    LocalModelInfo(
      id: 'qwen2_5_0_5b_q4',
      name: 'Qwen 2.5 0.5B Instruct (Ultra-Fast)',
      description:
          'Ultra-compact footprint, instant response on low-RAM entry level phones.',
      filename: 'qwen2.5-0.5b-instruct-q4_k_m.gguf',
      sizeInBytes: 398000000, // ~398 MB
      downloadUrl:
          'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf?download=true',
      fallbackUrls: [
        'https://hf-mirror.com/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf?download=true',
        'https://huggingface.co/bartowski/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf?download=true',
        'https://hf-mirror.com/bartowski/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf?download=true',
      ],
      parameterCount: '0.5B',
      quantization: 'Q4_K_M (4-bit)',
      contextLength: 2048,
      recommendedThreads: 4,
      isDefault: false,
    ),
    LocalModelInfo(
      id: 'llama_3_2_1b_q4',
      name: 'Llama 3.2 1B Instruct',
      description:
          'State-of-the-art Meta small language model with strong instruction following.',
      filename: 'llama-3.2-1b-instruct-q4_k_m.gguf',
      sizeInBytes: 720000000, // ~720 MB
      downloadUrl:
          'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf?download=true',
      fallbackUrls: [
        'https://hf-mirror.com/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf?download=true',
      ],
      parameterCount: '1B',
      quantization: 'Q4_K_M (4-bit)',
      contextLength: 2048,
      recommendedThreads: 4,
      isDefault: false,
    ),
    LocalModelInfo(
      id: 'qwen2_5_1_5b_q4',
      name: 'Qwen 2.5 1.5B Instruct (High Precision)',
      description:
          'High accuracy for complex multi-app cross-screen reasoning tasks.',
      filename: 'qwen2.5-1.5b-instruct-q4_k_m.gguf',
      sizeInBytes: 986000000, // ~986 MB
      downloadUrl:
          'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf?download=true',
      fallbackUrls: [
        'https://hf-mirror.com/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf?download=true',
        'https://huggingface.co/bartowski/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/Qwen2.5-1.5B-Instruct-Q4_K_M.gguf?download=true',
        'https://hf-mirror.com/bartowski/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/Qwen2.5-1.5B-Instruct-Q4_K_M.gguf?download=true',
      ],
      parameterCount: '1.5B',
      quantization: 'Q4_K_M (4-bit)',
      contextLength: 2048,
      recommendedThreads: 4,
      isDefault: false,
    ),
  ];

  static LocalModelInfo getDefaultModel() {
    return availableModels.firstWhere((m) => m.isDefault,
        orElse: () => availableModels.first);
  }

  static LocalModelInfo? getById(String id) {
    try {
      return availableModels.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }
}
