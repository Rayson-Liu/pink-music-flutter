package com.pinkmusic.app

import android.content.Context
import android.media.audiofx.DynamicsProcessing
import android.media.audiofx.Equalizer
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 10 段均衡器平台通道
 * 优先使用 DynamicsProcessing（API 28+，可配置 10 频段 31Hz–16kHz）
 * 低版本回退到系统 audiofx Equalizer（频段由设备决定）
 */
class EqualizerPlugin(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val CHANNEL = "com.pinkmusic.app/equalizer"
        private val BAND_CUTOFFS = listOf(
            31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000
        )
    }

    private val channel = MethodChannel(messenger, CHANNEL)

    @Volatile
    private var dynamicsProcessing: DynamicsProcessing? = null
    @Volatile
    private var fallbackEqualizer: Equalizer? = null

    fun onAttachedToEngine() {
        channel.setMethodCallHandler(this)
    }

    fun onDetachedFromEngine() {
        channel.setMethodCallHandler(null)
        release()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "attach" -> {
                val sessionId = (call.argument<Number>("sessionId"))?.toInt() ?: 0
                if (sessionId <= 0) {
                    result.success(false)
                    return
                }
                try {
                    attach(sessionId)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("EQ_UNSUPPORTED", e.message, null)
                }
            }
            "setEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") ?: true
                try {
                    setEnabled(enabled)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("EQ_ERROR", e.message, null)
                }
            }
            "setBands" -> {
                val gains = call.argument<List<*>>("gains")
                if (gains == null || gains.size != 10) {
                    result.error("EQ_ERROR", "gains must have 10 values", null)
                    return
                }
                try {
                    setBands(gains.mapNotNull { (it as? Number)?.toDouble() })
                    result.success(true)
                } catch (e: Exception) {
                    result.error("EQ_ERROR", e.message, null)
                }
            }
            "release" -> {
                release()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    @Suppress("DEPRECATION")
    private fun attach(sessionId: Int) {
        release()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            try {
                val cfgBuilder = DynamicsProcessing.Config.Builder(
                    /* channelCount */ 1,
                    /* preEqBandCount */ 10,
                    /* mb1Enable */ false, /* mbcBandCount */ 0,
                    /* mb2Enable */ false, /* postEqBandCount */ 0,
                    /* postMbcEnable */ false, /* postLimiterCount */ 0,
                    /* limiterEnable */ false
                )
                val eq = DynamicsProcessing.Eq(true, true, 10)
                for (i in BAND_CUTOFFS.indices) {
                    eq.setBand(
                        i,
                        DynamicsProcessing.EqBand(
                            true, BAND_CUTOFFS[i].toFloat(), 0f
                        )
                    )
                }
                val channelCfg = DynamicsProcessing.Channel(
                    /* inputGain */ 0f,
                    /* preEqInUse */ true, 10,
                    /* mbcInUse */ false, 0,
                    /* postEqInUse */ false, 0,
                    /* limiterInUse */ false
                ).apply { setPreEq(eq) }
                cfgBuilder.setChannelTo(0, channelCfg)
                val config = cfgBuilder.build()
                val effect = DynamicsProcessing(0, sessionId, config)
                effect.enabled = true
                dynamicsProcessing = effect
                return
            } catch (e: Exception) {
                dynamicsProcessing = null
            }
        }
        // 回退：系统 Equalizer
        try {
            val eq = Equalizer(0, sessionId)
            eq.enabled = true
            fallbackEqualizer = eq
        } catch (e: Exception) {
            throw e
        }
    }

    private fun setEnabled(enabled: Boolean) {
        dynamicsProcessing?.enabled = enabled
        fallbackEqualizer?.enabled = enabled
    }

    private fun setBands(gains: List<Double>) {
        val dp = dynamicsProcessing
        if (dp != null) {
            val channel = dp.getChannelByChannelIndex(0)
            val eq = channel.getPreEq()
            for (i in gains.indices) {
                val band = eq.getBand(i)
                band.setGain((gains[i] * 100).toInt().toFloat())
                eq.setBand(i, band)
            }
            dp.setChannelTo(0, channel)
            return
        }
        // 回退：映射到设备频段（就近取中心频率）
        val eq = fallbackEqualizer ?: return
        val bandCount = eq.numberOfBands
        for (i in 0 until bandCount) {
            val center = eq.getCenterFreq(i.toShort()) / 1000f
            var best = 0
            var bestDist = Float.MAX_VALUE
            for (j in gains.indices) {
                val dist = Math.abs(BAND_CUTOFFS[j] - center)
                if (dist < bestDist) {
                    bestDist = dist
                    best = j
                }
            }
            eq.setBandLevel(i.toShort(), (gains[best] * 100).toInt().toShort())
        }
    }

    private fun release() {
        try {
            dynamicsProcessing?.release()
        } catch (_: Exception) {
        }
        try {
            fallbackEqualizer?.release()
        } catch (_: Exception) {
        }
        dynamicsProcessing = null
        fallbackEqualizer = null
    }
}
