/// Cactus Flutter SDK — on-device AI inference.
///
/// Provides language models (LM), speech-to-text (STT), audio processing,
/// vector indexing, and text embedding — all running locally on device.
library cactus;

export 'models/types.dart';
export 'models/tools.dart';
export 'services/lm.dart';
export 'services/stt.dart';
export 'services/audio.dart';
export 'services/index.dart';
export 'services/config.dart';
export 'services/api/huggingface.dart';
export 'utils/models/download_state.dart';
