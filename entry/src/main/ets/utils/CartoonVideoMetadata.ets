/**
 * 读视频元数据时长（毫秒）。
 * 使用独立的 fd：SDK 要求同一个 fd 不能同时交给提取器与播放器。
 */

import { media } from '@kit.MediaKit'
import { fileIo } from '@kit.CoreFileKit'
import { parseMetadataDurationMs } from './CartoonLibraryUtils'

export async function readVideoDurationMs(uri: string): Promise<number> {
  let file: fileIo.File | null = null
  let extractor: media.AVMetadataExtractor | null = null
  try {
    file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY)
    extractor = await media.createAVMetadataExtractor()
    const fdSrc: media.AVFileDescriptor = { fd: file.fd, offset: 0, length: 0 }
    extractor.fdSrc = fdSrc
    const metadata = await extractor.fetchMetadata()
    const durationText: string = metadata.duration !== undefined ? metadata.duration : ''
    return parseMetadataDurationMs(durationText)
  } catch (error) {
    console.warn('CartoonVideoMetadata', `readVideoDurationMs failed: ${JSON.stringify(error)}`)
    return 0
  } finally {
    if (extractor !== null) {
      try {
        await extractor.release()
      } catch (_e) {
        // ignore release failure
      }
    }
    if (file !== null) {
      try {
        fileIo.closeSync(file)
      } catch (_e) {
        // ignore close failure
      }
    }
  }
}
