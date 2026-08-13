package com.bellinghamfolks.docconverter

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import java.net.HttpURLConnection
import java.net.URL
import java.io.IOException

/**
 * Routes the app's server calls over CELLULAR data on demand.
 *
 * Why: to use the glasses the phone is joined to a Wi-Fi that has no internet
 * (the glasses' own hotspot). Android keeps that dead Wi-Fi as the DEFAULT
 * network — good, because the eSight app needs it to reach the glasses — but it
 * means our online requests would go to the dead Wi-Fi too. When "prefer
 * cellular" is on we bind OUR http connections to the cellular network, so the
 * reader works online while eSight keeps the glasses on Wi-Fi. Per-app routing:
 * only our traffic moves, eSight is untouched.
 */
object NetManager {
    class CellularUnavailable : IOException("cellular_unavailable")
    @Volatile private var preferCellular = false
    @Volatile private var cellular: Network? = null
    private var cm: ConnectivityManager? = null
    private var callback: ConnectivityManager.NetworkCallback? = null

    fun setPreferCellular(ctx: Context, enabled: Boolean) {
        preferCellular = enabled
        cm = ctx.applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        DiagLog.log("NET", "preferCellular=$enabled")
        if (enabled) requestCellular() else release()
    }

    private fun requestCellular() {
        if (callback != null) return
        val c = cm ?: return
        // Ask the system to keep a CELLULAR internet network available even while
        // Wi-Fi stays the default. IMPORTANT: we do NOT require NET_CAPABILITY_
        // VALIDATED here — on several OEMs (e.g. Xiaomi) the cellular link isn't
        // marked "validated" while a Wi-Fi is default, which stopped the callback
        // from ever firing and left every request on the dead Wi-Fi. Requiring
        // only INTERNET is enough; open() also has a synchronous fallback.
        val req = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_CELLULAR)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) { cellular = network; DiagLog.log("NET", "cellular available") }
            override fun onLost(network: Network) { if (cellular == network) { cellular = null; DiagLog.log("NET", "cellular lost") } }
        }
        callback = cb
        // requestNetwork keeps the cellular radio up for us; keep it registered
        // for the whole session so the network stays bindable.
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
        val net = if (preferCellular) (cellular ?: findCellular()) else null
        DiagLog.log("NET", "open via ${if (net != null) "CELLULAR" else "default network"} (preferCellular=$preferCellular cellularReady=${net != null})")
        if (preferCellular && net == null) throw CellularUnavailable()
        return if (net != null) net.openConnection(url) as HttpURLConnection
        else url.openConnection() as HttpURLConnection
    }

    /**
     * Synchronous fallback: scan the phone's active networks for a live cellular
     * one with internet. Used when the requestNetwork callback hasn't delivered
     * a network yet (or never fires because the link isn't "validated"). As long
     * as mobile data is on, the cellular network exists here and is bindable.
     */
    private fun findCellular(): Network? {
        val c = cm ?: return null
        return try {
            @Suppress("DEPRECATION")
            c.allNetworks.firstOrNull { n ->
                val caps = c.getNetworkCapabilities(n)
                caps != null &&
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) &&
                    caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            }?.also { cellular = it }
        } catch (_: Exception) { null }
    }
}
