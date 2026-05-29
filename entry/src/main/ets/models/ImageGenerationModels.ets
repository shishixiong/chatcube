export enum ImageAspectRatio {
  SQUARE = 'square',
  LANDSCAPE = 'landscape',
  PORTRAIT = 'portrait'
}

export enum ImageGenerationQuality {
  AUTO = 'auto',
  LOW = 'low',
  MEDIUM = 'medium',
  HIGH = 'high'
}

export enum ImageGenerationOutputFormat {
  PNG = 'png',
  JPEG = 'jpeg',
  WEBP = 'webp'
}

export enum ImageGenerationModeration {
  AUTO = 'auto',
  LOW = 'low'
}

export enum ImageGenerationApiRoute {
  OPENAI_GPT_IMAGE = 'openai_gpt_image',
  OPENAI_LEGACY_IMAGE = 'openai_legacy_image',
  GOOGLE_IMAGEN = 'google_imagen',
  GOOGLE_GEMINI_IMAGE = 'google_gemini_image',
  XAI_GROK_IMAGE = 'xai_grok_image',
  MINIMAX_IMAGE = 'minimax_image',
  UNKNOWN = 'unknown'
}

export enum GeneratedMediaType {
  IMAGE_GENERATION = 'image_generation',
  IMAGE_EDIT = 'image_edit'
}

export class ImageGenerationOptions {
  prompt: string = ''
  numberOfImages: number = 1
  aspectRatio: ImageAspectRatio = ImageAspectRatio.SQUARE
}

export class ImageGenerationRequest {
  providerId: string = ''
  modelId: string = ''
  prompt: string = ''
  numberOfImages: number = 1
  aspectRatio: ImageAspectRatio = ImageAspectRatio.SQUARE
  referenceImagePaths: string[] = []
  quality: ImageGenerationQuality = ImageGenerationQuality.AUTO
  outputFormat: ImageGenerationOutputFormat = ImageGenerationOutputFormat.PNG
  outputCompression: number = -1
  moderation: ImageGenerationModeration = ImageGenerationModeration.LOW
  promptOptimizer: boolean = false
  seed: number = -1
  styleType: string = ''
  styleWeight: number = -1
}

export class ImageGenerationItem {
  base64Data: string = ''
  mimeType: string = 'image/png'
  revisedPrompt: string = ''
  actualSize: string = ''
  actualQuality: string = ''
  actualOutputFormat: string = ''
  actualOutputCompression: number = -1
  actualModeration: string = ''
}

export class ImageGenerationResult {
  items: ImageGenerationItem[] = []
}

@ObservedV2
export class GeneratedMedia {
  @Trace id: string = ''
  @Trace type: string = GeneratedMediaType.IMAGE_GENERATION
  @Trace prompt: string = ''
  @Trace providerId: string = ''
  @Trace providerName: string = ''
  @Trace modelId: string = ''
  @Trace modelName: string = ''
  @Trace filePath: string = ''
  @Trace mimeType: string = 'image/png'
  @Trace aspectRatio: string = ImageAspectRatio.SQUARE
  @Trace sourcePathsJson: string = ''
  @Trace requestOptionsJson: string = ''
  @Trace actualOptionsJson: string = ''
  @Trace revisedPrompt: string = ''
  @Trace createdAt: number = 0
}
