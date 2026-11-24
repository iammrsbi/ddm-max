package com.idrish.dd8max

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

object AudioTranscoder {
    fun decodeToWav(inputPath: String, outputPath: String) {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            extractor.setDataSource(inputPath)
            var trackIndex = -1
            var inputFormat: MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("audio/")) {
                    trackIndex = i
                    inputFormat = format
                    break
                }
            }
            if (trackIndex < 0 || inputFormat == null) {
                throw IllegalArgumentException("Is file mein supported audio stream nahi mila.")
            }
            extractor.selectTrack(trackIndex)
            val mime = inputFormat.getString(MediaFormat.KEY_MIME)!!
            codec = MediaCodec.createDecoderByType(mime)
            codec.configure(inputFormat, null, null, 0)
            codec.start()

            val pcm = ByteArrayOutputStream()
            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            var sampleRate = inputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var sourceChannels = inputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            var outputChannels = sourceChannels.coerceIn(1, 2)
            var pcmEncoding = AudioFormat.ENCODING_PCM_16BIT

            while (!outputDone) {
                if (!inputDone) {
                    val inputIndex = codec.dequeueInputBuffer(10000)
                    if (inputIndex >= 0) {
                        val inputBuffer = codec.getInputBuffer(inputIndex)!!
                        inputBuffer.clear()
                        val sampleSize = extractor.readSampleData(inputBuffer, 0)
                        if (sampleSize < 0) {
                            codec.queueInputBuffer(inputIndex, 0, 0, 0L, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            val pts = extractor.sampleTime.coerceAtLeast(0L)
                            codec.queueInputBuffer(inputIndex, 0, sampleSize, pts, 0)
                            extractor.advance()
                        }
                    }
                }

                val outputIndex = codec.dequeueOutputBuffer(info, 10000)
                when {
                    outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val outFormat = codec.outputFormat
                        sampleRate = outFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        sourceChannels = outFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                        outputChannels = sourceChannels.coerceIn(1, 2)
                        if (outFormat.containsKey(MediaFormat.KEY_PCM_ENCODING)) {
                            pcmEncoding = outFormat.getInteger(MediaFormat.KEY_PCM_ENCODING)
                        }
                    }
                    outputIndex >= 0 -> {
                        if (info.size > 0) {
                            val buffer = codec.getOutputBuffer(outputIndex)!!.duplicate().order(ByteOrder.LITTLE_ENDIAN)
                            buffer.position(info.offset)
                            buffer.limit(info.offset + info.size)
                            when (pcmEncoding) {
                                AudioFormat.ENCODING_PCM_FLOAT -> {
                                    val frameBytes = sourceChannels * 4
                                    while (buffer.remaining() >= frameBytes) {
                                        for (channel in 0 until outputChannels) {
                                            val value = buffer.getFloat().coerceIn(-1f, 0.999969f)
                                            writeShort(pcm, (value * 32768f).toInt())
                                        }
                                        for (channel in outputChannels until sourceChannels) buffer.getFloat()
                                    }
                                }
                                AudioFormat.ENCODING_PCM_8BIT -> {
                                    val frameBytes = sourceChannels
                                    while (buffer.remaining() >= frameBytes) {
                                        for (channel in 0 until outputChannels) {
                                            val value = ((buffer.get().toInt() and 0xff) - 128) shl 8
                                            writeShort(pcm, value)
                                        }
                                        for (channel in outputChannels until sourceChannels) buffer.get()
                                    }
                                }
                                else -> {
                                    val frameBytes = sourceChannels * 2
                                    while (buffer.remaining() >= frameBytes) {
                                        for (channel in 0 until outputChannels) writeShort(pcm, buffer.short.toInt())
                                        for (channel in outputChannels until sourceChannels) buffer.short
                                    }
                                }
                            }
                        }
                        outputDone = (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
                        codec.releaseOutputBuffer(outputIndex, false)
                    }
                }
            }

            val payload = pcm.toByteArray()
            if (payload.isEmpty()) throw IllegalArgumentException("Audio decode nahi ho paya.")
            val file = File(outputPath)
            file.parentFile?.mkdirs()
            file.outputStream().use { out ->
                fun text(value: String) { out.write(value.toByteArray(Charsets.US_ASCII)) }
                fun u16(value: Int) { out.write(value and 0xff); out.write((value shr 8) and 0xff) }
                fun u32(value: Int) {
                    out.write(value and 0xff); out.write((value shr 8) and 0xff)
                    out.write((value shr 16) and 0xff); out.write((value shr 24) and 0xff)
                }
                text("RIFF"); u32(36 + payload.size); text("WAVE")
                text("fmt "); u32(16); u16(1); u16(outputChannels)
                u32(sampleRate); u32(sampleRate * outputChannels * 2)
                u16(outputChannels * 2); u16(16)
                text("data"); u32(payload.size); out.write(payload)
            }
        } finally {
            try { codec?.stop() } catch (_: Exception) {}
            try { codec?.release() } catch (_: Exception) {}
            extractor.release()
        }
    }

    private fun writeShort(out: ByteArrayOutputStream, value: Int) {
        out.write(value and 0xff)
        out.write((value shr 8) and 0xff)
    }
}
