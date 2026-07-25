package com.bellinghamfolks.docconverter

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import java.net.HttpURLConnection
import java.net.URL

/**
 * Routes the app's server calls over CELLULAR data on demand.
 *
 * Why: to use the glasses the phone is joined to a Wi-Fi that has no internet
 * (e.g. the glasses' own hotspot). Android then sends app traffic to that
 * dead Wi-Fi and the server is unreachable even though mobile data is on. When
 * "prefer cellular" is enabled we explicitly bind our HTTP connections to the
 * cellular network so online mode works anyway.
 */
object NetManager {
    @Volatile private var preferCellular = false
    @Volatile private var cellular: Network? = null
    private var cm: ConnectivityManager? = null
    private var callback: ConnectivityManager.NetworkCallback? = null

    fun setPreferCellular(ctx: Context, enabled: Boolean) {
        preferCellular = enabled
        if (enabled) requestCellular(ctx) else release()
    }

    private fun requestCellular(ctx: Context) {
        if (callback != null) return
        val c = ctx.applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        cm = c
        val req = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_CELLULAR)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) { cellular = network }
            override fun onLost(network: Network) { if (cellular == network) cellular = null }
        }
        callback = cb
        try { c.requestNetwork(req, cb) } catch (_: Exception) {}
    }

    private fun release() {
        try { callback?.let { cm?.unregisterNetworkCallback(it) } } catch (_: Exception) {}
        callback = null
        cellular = null
    }

    /** Open a connection, over cellular when preferred and available. */
    fun open(urlStr: String): HttpURLConnection {
        val url = URL(urlStr)
        val net = cellular
        return if (preferCellular && net != null)
            net.openConnection(url) as HttpURLConnection
        else
            url.openConnection() as HttpURLConnection
    }
}
