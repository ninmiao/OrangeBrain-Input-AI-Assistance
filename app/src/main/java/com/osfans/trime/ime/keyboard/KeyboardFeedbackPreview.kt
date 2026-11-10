// SPDX-License-Identifier: GPL-3.0-or-later
package com.osfans.trime.ime.keyboard

import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool
import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import android.view.View
import com.osfans.trime.data.prefs.AppPrefs
import com.osfans.trime.data.soundeffect.SoundEffectManager

/** Settings-only feedback. Does not initialize/destroy the IME's audio or speech resources. */
class KeyboardFeedbackPreview : AutoCloseable {
    private val prefs get() = AppPrefs.defaultInstance().keyboard
    private val handler = Handler(Looper.getMainLooper())
    private var pool: SoundPool? = null

    fun vibrate(view: View) {
        InputFeedbackManager.keyPressVibrate(view)
    }

    fun sound() {
        close()
        if (!prefs.soundOnKeyPress.getValue()) return
        if (!prefs.soundEffectEnabled.getValue()) {
            InputFeedbackManager.keyPressSound(KeyEvent.KEYCODE_A)
            return
        }
        val volume = prefs.soundVolume.getValue() / 100f
        if (volume <= 0f) return
        val effect = SoundEffectManager.activeSoundEffect ?: return
        val index = if (effect.melody.isNotEmpty()) effect.sound.indexOf(effect.melody.first()) else
            effect.keyset.firstNotNullOfOrNull { it.querySoundIndex(KeyEvent.KEYCODE_A).takeIf { i -> i >= 0 } } ?: 0
        val path = SoundEffectManager.activeAudioPaths.getOrNull(index) ?: return
        val preview = SoundPool.Builder().setMaxStreams(1).setAudioAttributes(
            AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()).build()
        pool = preview
        preview.setOnLoadCompleteListener { loadedPool, id, status ->
            if (pool === loadedPool && status == 0 && prefs.soundOnKeyPress.getValue()) {
                loadedPool.play(id, volume, volume, 0, 0, 1f)
            }
        }
        try { preview.load(path, 1) } catch (_: Exception) { close(); return }
        handler.postDelayed({ if (pool === preview) close() }, 2000)
    }

    override fun close() {
        handler.removeCallbacksAndMessages(null)
        pool?.release(); pool = null
    }
}
