/**
 * 音乐生成数据模型
 *
 * 对应 MiniMax Music Generation API (POST /v1/music_generation)。
 * 与 ImageGenerationModels 同构, 但输入是 prompt + 可选 lyrics / 器乐参考,
 * 输出是 hex 编码的音频字节 + audio_format。
 *
 * 4 个支持的模型: music-2.6 / music-cover / music-2.6-free / music-cover-free
 * (由 MINIMAX_COMPATIBLE_MODELS 注册, services/registry/types.ets)
 */
export enum MusicGenerationOutputFormat {
  MP3 = 'mp3',
  PCM = 'pcm',
  WAV = 'wav',
  FLAC = 'flac'
}

export enum MusicGenerationSampleRate {
  RATE_16000 = 16000,
  RATE_24000 = 24000,
  RATE_32000 = 32000,
  RATE_44100 = 44100
}

export enum MusicGenerationBitrate {
  BITRATE_64000 = 64000,
  BITRATE_96000 = 96000,
  BITRATE_128000 = 128000,
  BITRATE_192000 = 192000,
  BITRATE_256000 = 256000,
  BITRATE_320000 = 320000
}

export enum MusicGenerationChannel {
  MONO = 1,
  STEREO = 2
}

export class MusicGenerationAudioSetting {
  sampleRate: MusicGenerationSampleRate = MusicGenerationSampleRate.RATE_32000
  bitrate: MusicGenerationBitrate = MusicGenerationBitrate.BITRATE_128000
  format: MusicGenerationOutputFormat = MusicGenerationOutputFormat.MP3
  channel: MusicGenerationChannel = MusicGenerationChannel.MONO
}

export class MusicGenerationRequest {
  providerId: string = ''
  modelId: string = ''
  prompt: string = ''
  lyrics: string = ''
  referVoice: string = ''
  referInstrumental: string = ''
  audioSetting: MusicGenerationAudioSetting = new MusicGenerationAudioSetting()
  outputDirectory: string = ''
  stream: boolean = false
}

export class MusicGenerationItem {
  hexData: string = ''
  audioFormat: MusicGenerationOutputFormat = MusicGenerationOutputFormat.MP3
  audioLengthMs: number = 0
  mimeType: string = 'audio/mpeg'
}

export class MusicGenerationResult {
  items: MusicGenerationItem[] = []
  traceId: string = ''
}

export function resolveAudioMimeType(format: MusicGenerationOutputFormat): string {
  if (format === MusicGenerationOutputFormat.WAV) {
    return 'audio/wav'
  }
  if (format === MusicGenerationOutputFormat.FLAC) {
    return 'audio/flac'
  }
  if (format === MusicGenerationOutputFormat.PCM) {
    return 'audio/L16'
  }
  return 'audio/mpeg'
}

export function resolveAudioExtension(format: MusicGenerationOutputFormat): string {
  if (format === MusicGenerationOutputFormat.WAV) {
    return '.wav'
  }
  if (format === MusicGenerationOutputFormat.FLAC) {
    return '.flac'
  }
  if (format === MusicGenerationOutputFormat.PCM) {
    return '.pcm'
  }
  return '.mp3'
}
