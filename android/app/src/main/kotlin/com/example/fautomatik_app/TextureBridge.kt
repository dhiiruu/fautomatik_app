package com.example.fautomatik_app

import android.graphics.SurfaceTexture
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.util.concurrent.Executors

/**
 * Bridges [NativeImg] handles directly to Flutter's [Texture] widget.
 *
 * Lifecycle:
 *  1. Dart calls `createTexture`  → registers [SurfaceTextureEntry], returns `textureId`.
 *  2. Dart calls `updateTexture`  → JNI copies cv::Mat data into the surface, frame flagged.
 *  3. Dart calls `disposeTexture` → releases the entry.
 */
class TextureBridge private constructor(
    private val registry: TextureRegistry
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val CHANNEL = "com.example.fautomatik_app/texture"

        init {
            System.loadLibrary("vulkan_compute_engine")
        }

        fun bindTo(flutterEngine: FlutterEngine): TextureBridge {
            val channel = MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            val bridge = TextureBridge(flutterEngine.textureRegistry)
            channel.setMethodCallHandler(bridge)
            return bridge
        }
    }

    private val bgExecutor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "TextureBridge-bg").also { it.isDaemon = true }
    }
    private val mainHandler = Handler(Looper.getMainLooper())
    private val entries = mutableMapOf<Long, CachedEntry>()

    private class CachedEntry(val entry: TextureRegistry.SurfaceTextureEntry) {
        val surface = android.view.Surface(entry.surfaceTexture())
    }

    // ── MethodChannel ────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "createTexture" -> onCreateTexture(result)
            "updateTexture" -> onUpdateTexture(call, result)
            "disposeTexture" -> onDisposeTexture(call, result)
            else -> result.notImplemented()
        }
    }

    private fun onCreateTexture(result: MethodChannel.Result) {
        try {
            val entry = registry.createSurfaceTexture()
            val textureId = entry.id()
            val cached = CachedEntry(entry)
            // Set buffer size from the SurfaceTexture side so the
            // ANativeWindow_Buffer we get is sized correctly.
            // Exact dimensions come later in updateTexture.
            entries[textureId] = cached
            result.success(textureId)
        } catch (e: Exception) {
            result.error("CREATE_FAIL", e.message, null)
        }
    }

    private fun onUpdateTexture(call: MethodCall, result: MethodChannel.Result) {
        val textureId = call.argument<Long>("textureId")
            ?: return result.error("NO_ID", "textureId required", null)
        val nativeHandle = call.argument<Long>("nativeHandle")
            ?: return result.error("NO_HANDLE", "nativeHandle required", null)
        val cached = entries[textureId]
            ?: return result.error("UNKNOWN_ID", "no entry for textureId $textureId", null)

        // Set SurfaceTexture buffer size to match image dimensions
        val w = call.argument<Int>("width") ?: return result.error("NO_WIDTH", "width required", null)
        val h = call.argument<Int>("height") ?: return result.error("NO_HEIGHT", "height required", null)
        if (w <= 0 || h <= 0) return result.error("INVALID_DIMS", "${w}x${h}", null)
        cached.entry.surfaceTexture().setDefaultBufferSize(w, h)

        bgExecutor.execute {
            try {
                val rc = nativeUpdateTexture(cached.surface, nativeHandle)
                if (rc != 0) {
                    mainHandler.post { result.error("RENDER_FAIL", "nativeUpdateTexture returned $rc", null) }
                    return@execute
                }
                mainHandler.post {
                    cached.entry.markTextureFrameAvailable()
                    result.success(null)
                }
            } catch (e: Exception) {
                mainHandler.post { result.error("EXCEPTION", e.message, null) }
            }
        }
    }

    private fun onDisposeTexture(call: MethodCall, result: MethodChannel.Result) {
        val textureId = call.argument<Long>("textureId")
        if (textureId != null) {
            entries.remove(textureId)?.let {
                it.surface.release()
                it.entry.release()
            }
        }
        result.success(null)
    }

    // ── JNI ──────────────────────────────────────────────────────────

    private external fun nativeUpdateTexture(surface: android.view.Surface, nativeHandle: Long): Int

    // ── Cleanup ──────────────────────────────────────────────────────

    fun dispose() {
        bgExecutor.shutdownNow()
        for ((_, cached) in entries) {
            cached.surface.release()
            cached.entry.release()
        }
        entries.clear()
    }
}
