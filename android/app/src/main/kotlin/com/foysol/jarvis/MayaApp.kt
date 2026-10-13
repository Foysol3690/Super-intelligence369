package com.foysol.jarvis
import android.app.Application
import android.content.Context
class MayaApp : Application() {
    companion object { lateinit var appContext: Context }
    override fun onCreate() { super.onCreate(); appContext = applicationContext }
}
