import 'package:cactus/cactus.dart';
import 'package:cactus/src/utils/models/download.dart';

class TestHelper {
  CactusLM? lm;
  final String defaultModel;
  final String defaultQuantization;

  TestHelper({
    this.defaultModel = 'lfm2-vl-450m',
    this.defaultQuantization = 'int4',
  });

  Future<CactusLM> setupModel({
    String model = 'lfm2-vl-450m',
    String quantization = 'int4',
    bool skipDownload = false,
  }) async {
    lm = CactusLM();

    if (skipDownload) {
      final onDisk = await isModelOnDisk(model);
      if (!onDisk) {
        await lm!.downloadModel(model: model, quantization: quantization);
      }
    } else {
      await lm!.downloadModel(model: model, quantization: quantization);
    }

    await lm!.initializeModel(
      params: CactusInitParams(model: model),
    );

    return lm!;
  }

  Future<void> teardownModel() async {
    lm?.unload();
    lm = null;
  }

  static Future<bool> isModelOnDisk(String model) async {
    return await DownloadService.modelExists(model);
  }
}
