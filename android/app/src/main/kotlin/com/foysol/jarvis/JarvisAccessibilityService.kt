package com.foysol.jarvis

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.graphics.Rect
import android.content.ClipData
import android.content.ClipboardManager
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import org.json.JSONArray
import org.json.JSONObject

/**
 * JARVIS NEXØRA QUANTUM OVERLORD ENGINE
 * MAXOUT - NO LIMIT - SEES ALL, CONTROLS ALL, 0ms LATENCY
 */
class JarvisAccessibilityService : AccessibilityService() {

    companion object {
        var instance: JarvisAccessibilityService? = null
            private set
        private const val TAG = "JarvisEngine"
        private const val MAX_TREE_DEPTH = 25 // GOD MODE: was 10
        private const val MAX_TREE_NODES = 1500 // GOD MODE: was 350
        private const val MAX_TEXT_LENGTH = 500
        private const val MAX_EVENT_HISTORY = 500
        private val eventLock = Any()
        private val eventHistory = ArrayDeque<String>()

        fun recentEvents(limit: Int = 200): List<String> = synchronized(eventLock) {
            eventHistory.takeLast(limit.coerceIn(1, MAX_EVENT_HISTORY))
        }

        fun clearEvents() = synchronized(eventLock) { eventHistory.clear() }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this

        // GOD MODE PROFILE - MAX EVERYTHING
        serviceInfo = serviceInfo.apply {
            // SEE EVERYTHING
            eventTypes = AccessibilityEvent.TYPES_ALL_MASK

            // ALL FEEDBACK TYPES
            feedbackType = AccessibilityServiceInfo.FEEDBACK_ALL_MASK

            // Use only public accessibility flags supported by Android.
            flags = 0x0002 or 0x0040 or 0x0010 or 0x0004 or
                0x0008 or 0x0020 or 0x0200 or 0x0080

            // 0ms = REALTIME, NO DELAY
            notificationTimeout = 0L

            // Allow on all packages
            packageNames = null
        }
        Log.i(TAG, "MAYA NEXØRA QUANTUM OVERLORD CONNECTED - GOD MODE ACTIVE - 0ms")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        try {
            val record = JSONObject().apply {
                put("eventType", AccessibilityEvent.eventTypeToString(event.eventType))
                put("packageName", clipped(event.packageName))
                put("className", clipped(event.className))
                put("contentDescription", if (event.isPassword) "[REDACTED]" else clipped(event.contentDescription))
                put("text", if (event.isPassword) JSONArray().put("[REDACTED]") else JSONArray(event.text.take(6).map(::clipped)))
                put("eventTime", event.eventTime)
                put("windowId", event.windowId)
                put("password", event.isPassword)
            }.toString()
            synchronized(eventLock) {
                eventHistory.addLast(record)
                while (eventHistory.size > MAX_EVENT_HISTORY) eventHistory.removeFirst()
            }
        } catch (_: Exception) {}
    }

    override fun onInterrupt() {
        Log.w(TAG, "Engine interrupted - re-arming")
        // Auto re-arm
        serviceInfo = serviceInfo
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
        // GOD MODE RESURRECTION
        val intent = android.content.Intent(this, BootReceiver::class.java).apply {
            action = android.content.Intent.ACTION_BOOT_COMPLETED
        }
        sendBroadcast(intent)
    }

    // ========== GOD MODE CORE FUNCTIONS ==========

    fun getActiveScreenNodeTree(): String {
        val rootNode = rootInActiveWindow?: return JSONObject().apply {
            put("status", "no_active_window")
            put("message", "No window - unlock phone")
        }.toString()
        return try {
            val budget = intArrayOf(MAX_TREE_NODES)
            val tree = serializeNode(rootNode, 0, budget)
            JSONObject().apply {
                put("status", "ok")
                put("packageName", clipped(rootNode.packageName))
                put("windowTitle", clipped(rootNode.contentDescription?: rootNode.text))
                put("screenWidth", resources.displayMetrics.widthPixels)
                put("screenHeight", resources.displayMetrics.heightPixels)
                put("orientation", if (resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE) "landscape" else "portrait")
                put("nodeCount", MAX_TREE_NODES - budget[0])
                put("treeTruncated", budget[0] <= 0)
                put("tree", tree)
            }.toString()
        } catch (e: Exception) {
            Log.e(TAG, "Tree failed", e)
            JSONObject().apply { put("status", "error"); put("message", e.message) }.toString()
        } finally {
            rootNode.recycle()
        }
    }

    private fun serializeNode(node: AccessibilityNodeInfo, depth: Int, budget: IntArray): JSONObject {
        if (depth > MAX_TREE_DEPTH || budget[0] <= 0) {
            return JSONObject().apply { put("truncated", true) }
        }
        budget[0] -= 1
        val bounds = Rect().also(node::getBoundsInScreen)
        val protected = node.isPassword
        val json = JSONObject().apply {
            put("className", clipped(node.className))
            put("text", if (protected) "[REDACTED]" else clipped(node.text))
            put("contentDescription", if (protected) "[REDACTED]" else clipped(node.contentDescription))
            put("viewId", clipped(node.viewIdResourceName))
            put("isPassword", protected)
            put("isClickable", node.isClickable)
            put("isLongClickable", node.isLongClickable)
            put("isEditable", node.isEditable)
            put("isScrollable", node.isScrollable)
            put("isEnabled", node.isEnabled)
            put("isFocused", node.isFocused)
            put("isVisibleToUser", node.isVisibleToUser)
            put("isSelected", node.isSelected)
            put("isCheckable", node.isCheckable)
            put("isChecked", node.isChecked)
            put("bounds", JSONObject().apply {
                put("left", bounds.left); put("top", bounds.top)
                put("right", bounds.right); put("bottom", bounds.bottom)
                put("centerX", bounds.centerX()); put("centerY", bounds.centerY())
            })
        }
        val children = JSONArray()
        if (depth < MAX_TREE_DEPTH && budget[0] > 0) {
            for (i in 0 until node.childCount) {
                if (budget[0] <= 0) break
                val child = node.getChild(i)?: continue
                try { children.put(serializeNode(child, depth + 1, budget)) } finally { child.recycle() }
            }
        }
        json.put("children", children)
        return json
    }

    private fun clipped(value: CharSequence?): String {
        val text = value?.toString().orEmpty()
        return if (text.length <= MAX_TEXT_LENGTH) text else text.take(MAX_TEXT_LENGTH) + "…"
    }

    // ========== ULTRA ACTION SUITE ==========

    fun clickNodeByViewId(viewId: String): Boolean {
        if (viewId.isBlank()) return false
        val root = rootInActiveWindow?: return false
        return try {
            val nodes = root.findAccessibilityNodeInfosByViewId(viewId).orEmpty()
            try { nodes.take(100).any(::performClickRecursive) } finally { nodes.forEach { it.recycle() } }
        } finally { root.recycle() }
    }

    fun clickNodeByText(text: String): Boolean {
        if (text.isBlank()) return false
        val root = rootInActiveWindow?: return false
        return try {
            val nodes = root.findAccessibilityNodeInfosByText(text).orEmpty()
            try { nodes.take(100).any(::performClickRecursive) } finally { nodes.forEach { it.recycle() } }
        } finally { root.recycle() }
    }

    private fun performClickRecursive(node: AccessibilityNodeInfo?): Boolean {
        if (node == null) return false
        if (node.isClickable && node.isEnabled) return node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
        var parent = node.parent
        while (parent!= null) {
            val current = parent
            if (current.isClickable && current.isEnabled) {
                val result = current.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                current.recycle()
                return result
            }
            parent = current.parent
            current.recycle()
        }
        return false
    }

    fun typeTextIntoFocusedNode(text: String): Boolean {
        val root = rootInActiveWindow?: return false
        return try {
            val focused = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
               ?: root.findFocus(AccessibilityNodeInfo.FOCUS_ACCESSIBILITY)?: return false
            try {
                // GOD MODE: Try 3 methods
                val args = Bundle().apply { putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text) }
                if (focused.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)) return true

                // Fallback: clipboard paste
                val clipboard = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
                clipboard.setPrimaryClip(ClipData.newPlainText("maya", text))
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR2) {
                    if (focused.performAction(AccessibilityNodeInfo.ACTION_PASTE)) return true
                }
                false
            } finally { focused.recycle() }
        } finally { root.recycle() }
    }

    // ========== WHATSAPP GOD MODE ==========

    fun clickWhatsAppSearch(): Boolean {
        val ids = listOf("com.whatsapp:id/menuitem_search","com.whatsapp.w4b:id/menuitem_search","com.whatsapp:id/search")
        if (ids.any(::clickNodeByViewId)) return true
        val root = rootInActiveWindow?: return false
        return try {
            clickFirstMatching(root, 0) { n ->
                val labels = listOfNotNull(n.contentDescription, n.text).map { it.toString().trim().lowercase() }
                labels.any { it == "search" || it.startsWith("search ") } && n.isEnabled
            }
        } finally { root.recycle() }
    }

    fun clickWhatsAppRecipient(displayName: String, phone: String): Boolean {
        val wantedName = displayName.trim().lowercase()
        val wantedDigits = phone.filter(Char::isDigit).takeLast(7)
        val root = rootInActiveWindow?: return false
        return try {
            clickFirstMatching(root, 0) { node ->
                val text = node.text?.toString()?.trim().orEmpty()
                val digits = text.filter(Char::isDigit)
                (wantedName.isNotEmpty() && text.lowercase() == wantedName || wantedDigits.length == 7 && digits.endsWith(wantedDigits)) && node.isEnabled
            }
        } finally { root.recycle() }
    }

    fun clickWhatsAppSend(): Boolean {
        val ids = listOf("com.whatsapp:id/send","com.whatsapp.w4b:id/send")
        if (ids.any(::clickNodeByViewId)) return true
        val root = rootInActiveWindow?: return false
        return try {
            clickFirstMatching(root, 0) { n ->
                val d = n.contentDescription?.toString().orEmpty()
                val t = n.text?.toString().orEmpty()
                (d.equals("send", true) || t.equals("send", true)) && n.isEnabled
            }
        } finally { root.recycle() }
    }

    fun clickWhatsAppCall(video: Boolean): Boolean {
        val suffixes = if (video) listOf("menuitem_video_call","video_call") else listOf("menuitem_voice_call","voice_call","call_button")
        for (pkg in listOf("com.whatsapp","com.whatsapp.w4b")) for (s in suffixes) if (clickNodeByViewId("$pkg:id/$s")) return true
        return false
    }

    // ========== GESTURE GOD MODE ==========

    fun performGlobal(action: Int): Boolean = performGlobalAction(action)

    fun tapAtCoordinates(x: Float, y: Float, callback: ((Boolean) -> Unit)? = null) {
        dispatchGesturePath(x, y, x, y, 80L, callback)
    }

    fun swipe(startX: Float, startY: Float, endX: Float, endY: Float, durationMs: Long = 300L, callback: ((Boolean) -> Unit)? = null) {
        dispatchGesturePath(startX, startY, endX, endY, durationMs, callback)
    }

    fun longPressAtCoordinates(x: Float, y: Float, durationMs: Long = 1000L, callback: ((Boolean) -> Unit)? = null) {
        dispatchGesturePath(x, y, x, y, durationMs, callback)
    }

    fun dispatchGesturePath(startX: Float, startY: Float, endX: Float, endY: Float, durationMs: Long, callback: ((Boolean) -> Unit)? = null) {
        val path = Path().apply { moveTo(startX, startY); lineTo(endX, endY) }
        val gesture = GestureDescription.Builder().addStroke(GestureDescription.StrokeDescription(path, 0L, durationMs.coerceIn(10L, 2000L))).build()
        val accepted = dispatchGesture(gesture, object : GestureResultCallback() {
            override fun onCompleted(g: GestureDescription?) { callback?.invoke(true) }
            override fun onCancelled(g: GestureDescription?) { callback?.invoke(false) }
        }, null)
        if (!accepted) callback?.invoke(false)
    }

    private fun clickFirstMatching(node: AccessibilityNodeInfo, depth: Int, predicate: (AccessibilityNodeInfo) -> Boolean): Boolean {
        if (depth > MAX_TREE_DEPTH) return false
        if (predicate(node) && performClickRecursive(node)) return true
        for (i in 0 until node.childCount) {
            val child = node.getChild(i)?: continue
            try { if (clickFirstMatching(child, depth + 1, predicate)) return true } finally { child.recycle() }
        }
        return false
    }

    // Extra god methods
    fun scrollForward(): Boolean = rootInActiveWindow?.let { r -> try { r.findFocus(AccessibilityNodeInfo.FOCUS_ACCESSIBILITY)?.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD)?: false } finally { r.recycle() } }?: false
    fun scrollBackward(): Boolean = rootInActiveWindow?.let { r -> try { r.findFocus(AccessibilityNodeInfo.FOCUS_ACCESSIBILITY)?.performAction(AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD)?: false } finally { r.recycle() } }?: false
    fun goBack(): Boolean = performGlobal(GLOBAL_ACTION_BACK)
    fun goHome(): Boolean = performGlobal(GLOBAL_ACTION_HOME)
    fun openRecents(): Boolean = performGlobal(GLOBAL_ACTION_RECENTS)
    fun openNotifications(): Boolean = performGlobal(GLOBAL_ACTION_NOTIFICATIONS)
}