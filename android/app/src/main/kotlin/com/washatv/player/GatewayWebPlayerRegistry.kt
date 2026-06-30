package com.washatv.player

import java.lang.ref.WeakReference

/** Tracks live gateway platform views for resume/pause handoff from Flutter. */
object GatewayWebPlayerRegistry {
    private val views = mutableMapOf<Int, WeakReference<GatewayWebPlayerPlatformView>>()

    fun register(viewId: Int, view: GatewayWebPlayerPlatformView) {
        views[viewId] = WeakReference(view)
    }

    fun unregister(viewId: Int) {
        views.remove(viewId)
    }

    fun pause(viewId: Int) {
        views[viewId]?.get()?.pauseForHandoff()
    }

    fun resume(viewId: Int) {
        views[viewId]?.get()?.resumeAfterHandoff()
    }
}
