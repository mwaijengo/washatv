package com.washatv.security

import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import android.os.Debug
import android.util.Base64
import com.washatv.BuildConfig
import java.io.File
import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

class SecureClientException(val code: String, message: String) : Exception(message)

/**
 * Signs viewer session requests and opens sealed playback payloads.
 * Must stay byte-compatible with backend/src/lib/clientAuth.ts.
 */
object SecureClient {
    private const val SIG_VERSION = "v1"
    private const val B64_FLAGS = Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP

    fun signSession(context: Context, challenge: String, deviceId: String): Map<String, String> {
        val flags = integrityFlags(context)
        if (!BuildConfig.DEBUG && (flags.contains("dbg") || flags.contains("hook"))) {
            throw SecureClientException("untrusted_device", "Environment not trusted")
        }
        val packageName = context.packageName
        val cert = signingCertSha256(context)
        val flagString = flags.sorted().joinToString(",")
        val input = listOf(SIG_VERSION, challenge, deviceId, packageName, cert, flagString).joinToString("|")
        val signature = hmac(secret(), input.toByteArray(Charsets.UTF_8)).toHex()
        return mapOf(
            "package" to packageName,
            "cert_sha256" to cert,
            "flags" to flagString,
            "signature" to signature,
        )
    }

    fun openSealed(sessionId: String, deviceId: String, sealed: String): String {
        val raw = Base64.decode(sealed, B64_FLAGS)
        if (raw.size < 12 + 16) throw SecureClientException("bad_payload", "Payload too short")
        val key = hmac(secret(), "k1|$sessionId|$deviceId".toByteArray(Charsets.UTF_8))
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, raw, 0, 12))
        val plain = cipher.doFinal(raw, 12, raw.size - 12)
        return String(plain, Charsets.UTF_8)
    }

    private fun secret(): ByteArray {
        val a = Base64.decode(BuildConfig.WS_A, Base64.NO_WRAP)
        val b = Base64.decode(BuildConfig.WS_B, Base64.NO_WRAP)
        if (a.isEmpty() || a.size != b.size) {
            throw SecureClientException("not_configured", "App signing secret missing from build")
        }
        return ByteArray(a.size) { i -> (a[i].toInt() xor b[i].toInt()).toByte() }
    }

    private fun hmac(key: ByteArray, data: ByteArray): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(key, "HmacSHA256"))
        return mac.doFinal(data)
    }

    private fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it) }

    @Suppress("DEPRECATION")
    private fun signingCertSha256(context: Context): String {
        val pm = context.packageManager
        val certs = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val info = pm.getPackageInfo(context.packageName, PackageManager.GET_SIGNING_CERTIFICATES)
            val signing = info.signingInfo ?: return ""
            if (signing.hasMultipleSigners()) signing.apkContentsSigners else signing.signingCertificateHistory
        } else {
            pm.getPackageInfo(context.packageName, PackageManager.GET_SIGNATURES).signatures
        }
        val current = certs?.lastOrNull() ?: return ""
        return MessageDigest.getInstance("SHA-256").digest(current.toByteArray()).toHex()
    }

    private fun integrityFlags(context: Context): Set<String> {
        val flags = mutableSetOf<String>()
        val debuggable = (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        if (Debug.isDebuggerConnected() || Debug.waitingForDebugger() || (debuggable && !BuildConfig.DEBUG)) {
            flags += "dbg"
        }
        if (hookFrameworkPresent()) flags += "hook"
        if (looksRooted()) flags += "root"
        if (looksLikeEmulator()) flags += "emu"
        return flags
    }

    private fun hookFrameworkPresent(): Boolean {
        val markers = listOf("frida", "xposed", "lsposed", "substrate", "edxposed")
        try {
            File("/proc/self/maps").useLines { lines ->
                if (lines.any { line -> markers.any { line.contains(it, ignoreCase = true) } }) return true
            }
        } catch (_: Exception) {
        }
        for (cls in listOf("de.robv.android.xposed.XposedBridge", "org.lsposed.lspd.core.Main")) {
            try {
                Class.forName(cls)
                return true
            } catch (_: Throwable) {
            }
        }
        return false
    }

    private fun looksRooted(): Boolean {
        if (Build.TAGS?.contains("test-keys") == true) return true
        val paths = listOf(
            "/system/bin/su", "/system/xbin/su", "/sbin/su", "/su/bin/su",
            "/system/app/Superuser.apk", "/data/adb/magisk", "/data/local/xbin/su",
        )
        return paths.any { File(it).exists() }
    }

    private fun looksLikeEmulator(): Boolean {
        val fp = Build.FINGERPRINT.orEmpty()
        return fp.startsWith("generic") || fp.contains("emulator") ||
            Build.MODEL.orEmpty().contains("Android SDK built for") ||
            Build.HARDWARE.orEmpty().let { it == "goldfish" || it == "ranchu" } ||
            Build.PRODUCT.orEmpty().contains("sdk_gphone")
    }
}
