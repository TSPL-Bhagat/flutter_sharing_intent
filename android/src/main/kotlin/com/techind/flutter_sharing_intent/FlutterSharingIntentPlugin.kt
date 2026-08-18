package com.techind.flutter_sharing_intent

import android.app.SearchManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.media.ThumbnailUtils
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Log
import android.util.Size
import android.webkit.MimeTypeMap
import android.webkit.URLUtil
import androidx.annotation.NonNull
import java.util.Objects

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.*
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.net.URLConnection

private const val EVENTS_CHANNEL_MEDIA = "flutter_sharing_intent/events-sharing"

/**
 **  Author - Bhagat Singh
 **  Contact - https://www.linkedin.com/in/bhagat-singh-79496a14b/
 **  Created On - 25/11/2022
 **  Purpose -  Created [FlutterSharingIntentPlugin] class to manage sharing intent
 */

class FlutterSharingIntentPlugin: FlutterPlugin, ActivityAware, MethodCallHandler,
  EventChannel.StreamHandler,
  PluginRegistry.NewIntentListener {
  private var TAG:String = javaClass.name

  /** To store initial & latest value when app is opened from background **/
  private var initialSharing: JSONArray? = null
  private var latestSharing: JSONArray? = null

  // Debounce duplicate intents from Samsung and other OEM launchers that
  // deliver the same intent more than once within a short window.
  private var lastIntentHash: Int = 0
  private var lastIntentTime: Long = 0

  /// The MethodChannel that will the communication between Flutter and native Android
  private lateinit var channel : MethodChannel
  private lateinit var eventChannel: EventChannel

  private var eventSinkSharing: EventChannel.EventSink? = null

  private var binding: ActivityPluginBinding? = null
  private lateinit var applicationContext: Context

  /// To sel channel & event stream
  private fun setupCallbackChannels(binaryMessenger: BinaryMessenger) {
    channel = MethodChannel(binaryMessenger, "flutter_sharing_intent")
    channel.setMethodCallHandler(this)

    eventChannel = EventChannel(binaryMessenger, EVENTS_CHANNEL_MEDIA)
    eventChannel.setStreamHandler(this)

  }

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    applicationContext = flutterPluginBinding.applicationContext
    setupCallbackChannels(flutterPluginBinding.binaryMessenger)
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    when (call.method) {
      "getInitialSharing" -> {
         FSILogger.log(applicationContext, "getInitialSharing: returning ${initialSharing?.length() ?: 0} item(s)", TAG)
         result.success(initialSharing?.toString())
          /// Clear cache data to send only once
          initialSharing = null
          latestSharing = null
      }
      "reset" -> {
        initialSharing = null
        latestSharing = null
        result.success(null)
      }
      "getDebugLogs" -> {
        result.success(FSILogger.readAll(applicationContext))
      }
      "clearDebugLogs" -> {
        FSILogger.clear(applicationContext)
        result.success(null)
      }
      "shareDebugLogs" -> {
        shareDebugLogsAsText(result)
      }
      else -> result.notImplemented()
    }
  }

  private fun shareDebugLogsAsText(result: Result) {
    val logs = FSILogger.readAll(applicationContext)
    if (logs.isEmpty()) {
      result.error("NO_LOGS", "No debug logs to share yet", null)
      return
    }
    val sendIntent = Intent(Intent.ACTION_SEND).apply {
      type = "text/plain"
      putExtra(Intent.EXTRA_TEXT, logs)
      addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    val chooser = Intent.createChooser(sendIntent, "Share debug logs").apply {
      addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    (binding?.activity ?: applicationContext).startActivity(chooser)
    result.success(null)
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    initialSharing = null
    latestSharing = null
    eventChannel.setStreamHandler(null)
  }

  private fun handleIntent(intent: Intent, initial: Boolean) {
    val intentFlags = intent.flags
    if ((intentFlags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0) return

    // Skip duplicate intents delivered within 500ms — seen on Samsung and some other OEM devices.
    val extraStream = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.toString()
    val intentHash = Objects.hash(intent.action, intent.type, intent.dataString,
        intent.getStringExtra(Intent.EXTRA_TEXT), extraStream)
    val now = System.currentTimeMillis()
    if (intentHash == lastIntentHash && (now - lastIntentTime) < 500L) {
      Log.d(TAG, "handleIntent: duplicate intent ignored (hash=$intentHash)")
      return
    }
    lastIntentHash = intentHash
    lastIntentTime = now

    Log.d(TAG,"handleIntent ==>> ${intent.action}, ${intent.type}")
    FSILogger.log(applicationContext, "handleIntent action=${intent.action} type=${intent.type} initial=$initial", TAG)
    when {
      (intent.type?.startsWith("text") != true)
              && (intent.action == Intent.ACTION_SEND
              || intent.action == Intent.ACTION_SEND_MULTIPLE) -> { // Sharing images or videos (with optional caption text)

        val value = mergeSharingArrays(getSharingUris(intent), getSharingText(intent))
        if (initial) initialSharing = value
        latestSharing = value
        Log.d(TAG,"Image/Video : handleIntent ==>> $value")
        eventSinkSharing?.success(value?.toString())
      }
      (intent.type == null || intent.type?.startsWith("text") == true)
              && (intent.action == Intent.ACTION_SEND || intent.action == Intent.ACTION_SEND_MULTIPLE) -> { // Sharing text (with optional file)

        val value = mergeSharingArrays(getSharingText(intent), getSharingUris(intent))
        if (initial) initialSharing = value
        latestSharing = value
        Log.d(TAG,"text : handleIntent ==>> $value")
        value?.let { eventSinkSharing?.success(it.toString()) }

      }
      // Explicit handler for URL intents — produces MediaType.URL.
      // getMediaType() never receives this intent type, so its "url" branch
      // was removed; this is the single authoritative place for URL handling.
      intent.action == Intent.ACTION_VIEW -> { // Opening URL
        val value = JSONArray().put(
          JSONObject()
            .put("value", intent.dataString)
            .put("type", MediaType.URL.ordinal)
        )
        if (value == null) Log.w(TAG,"ACTION_VIEW : handleIntent ==>> value is null, skipping assignment")
        if (initial && value != null) initialSharing = value
        latestSharing = value
        Log.d(TAG,"ACTION_VIEW : handleIntent ==>> $value")
        eventSinkSharing?.success(value?.toString())
      }
      // Explicit handler for web-search intents — produces MediaType.WEB_SEARCH.
      // getMediaType() never receives this intent type, so its "web_search" branch
      // was removed; this is the single authoritative place for web-search handling.
      intent.action == Intent.ACTION_WEB_SEARCH -> {
        val value = JSONArray().put(
          JSONObject()
            .put("value", intent.getStringExtra(SearchManager.QUERY))
            .put("type", MediaType.WEB_SEARCH.ordinal)
        )
        if (value == null) Log.w(TAG,"ACTION_WEB_SEARCH : handleIntent ==>> value is null, skipping assignment")
        if (initial && value != null) initialSharing = value
        latestSharing = value
        Log.d(TAG,"ACTION_WEB_SEARCH : handleIntent ==>> $value")
        eventSinkSharing?.success(value?.toString())
      }
    }
  }

  // Combines multiple sharing arrays (e.g. file uris + caption text) into a single
  // array instead of one overwriting the other, so apps receive every shared item.
  private fun mergeSharingArrays(vararg arrays: JSONArray?): JSONArray? {
    val merged = JSONArray()
    arrays.forEach { array ->
      array?.let {
        for (i in 0 until it.length()) {
          merged.put(it.get(i))
        }
      }
    }
    return if (merged.length() > 0) merged else null
  }

  private fun getSharingUris(intent: Intent?): JSONArray? {
    if (intent == null) return null

    return when (intent.action) {
      Intent.ACTION_SEND -> {
        val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
          intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
          @Suppress("DEPRECATION")
          intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        }
        val path = uri?.let{ MyFileDirectory.getAbsolutePath(applicationContext, it) }
        if (path != null) {
          val type = path?.let { getMediaType(it) }
          val thumbnail = path?.let { getThumbnail(it, type) }
          val duration = getDuration(path, type)

          JSONArray().put(
            JSONObject()
              .put("value", path)
              .put("type", type.ordinal as Int)
              .apply { thumbnail?.let { put("thumbnail", it) } }
              .apply { duration?.let { put("duration", it) } }
          )
        } else null
      }
      Intent.ACTION_SEND_MULTIPLE -> {
        val uris = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
          intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
          @Suppress("DEPRECATION")
          intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
        }
        val value = uris?.mapNotNull { uri ->
          val path = MyFileDirectory.getAbsolutePath(applicationContext, uri)
            ?: return@mapNotNull null
          val type = path?.let { getMediaType(it) }
          val thumbnail = path?.let { getThumbnail(it, type) }
          val duration = getDuration(path, type)
          return@mapNotNull JSONObject()
            .put("value", path)
            .put("type", type.ordinal as Int)
            .apply { thumbnail?.let { put("thumbnail", it) } }
            .apply { duration?.let { put("duration", it) } }
        }?.toList()
        if (value != null) JSONArray(value) else null
      }
      else -> null
    }
  }

 private fun getSharingText(intent: Intent?): JSONArray? {
    if (intent == null) return null

    return when (intent.action) {
      Intent.ACTION_SEND -> {
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)
        if (text != null) {
          val type = getTypeForTextAndUrl(text)
          JSONArray().put(
            JSONObject()
              .put("value", text)
              .put("type", type)
          )
        } else null
      }
      Intent.ACTION_SEND_MULTIPLE -> {
        val textList = intent.getStringArrayListExtra(Intent.EXTRA_TEXT)

        val value = textList?.mapNotNull { text ->
          val path = text
            ?: return@mapNotNull null
          val type = getTypeForTextAndUrl(path)

          return@mapNotNull JSONObject()
            .put("value", path)
            .put("type", type)
        }?.toList()
        if (value != null) JSONArray(value) else null
      }
      else -> null
    }
  }

  // To get type for text and url only
  // It will return MediaType.URL.ordinal if text is valid url other will return MediaType.TEXT.ordinal
  fun getTypeForTextAndUrl( value: String?) : Int
  {
    return if (value == null || !URLUtil.isValidUrl(value)) MediaType.TEXT.ordinal else MediaType.URL.ordinal;
  }

  // Called only for files shared via EXTRA_STREAM (not inline text or URL intents).
  // Text-MIME files (e.g. .txt / "text/plain") are classified as FILE so callers
  // receive a resolvable path rather than a null text payload; inline text is
  // handled by getSharingText() and URL/web-search by handleIntent() directly.
  private fun getMediaType(path: String?): MediaType {
    val mimeType = URLConnection.guessContentTypeFromName(path)
    // NOTE: "url" and "web_search" branches are intentionally absent here.
    // URLConnection.guessContentTypeFromName() only returns standard MIME-type strings
    // (e.g. "image/png", "video/mp4", "text/plain") — it never returns "url" or
    // "web_search" as a prefix.  Those intent types are not file-based and therefore
    // never reach this function; they are routed to the correct MediaType values
    // (MediaType.URL and MediaType.WEB_SEARCH) by the explicit branches in
    // handleIntent() that match Intent.ACTION_VIEW and Intent.ACTION_WEB_SEARCH.
    return when {
      mimeType?.startsWith("image") == true -> MediaType.IMAGE
      mimeType?.startsWith("video") == true -> MediaType.VIDEO
      else -> MediaType.FILE
    }
  }

  private fun getThumbnail(path: String, type: MediaType): String? {
    if (type != MediaType.VIDEO) return null // get video thumbnail only

    val videoFile = File(path)
    val targetFile = File(applicationContext.cacheDir, "${videoFile.name}.png")
    val bitmap = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      try {
        ThumbnailUtils.createVideoThumbnail(videoFile, Size(512, 384), null)
      } catch (e: Exception) {
        null
      }
    } else {
      @Suppress("DEPRECATION")
      ThumbnailUtils.createVideoThumbnail(path, MediaStore.Video.Thumbnails.MINI_KIND)
    } ?: return null
    FileOutputStream(targetFile).use { out ->
      bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
    }
    bitmap.recycle()
    return targetFile.path
  }

  private fun getDuration(path: String, type: MediaType): Long? {
    if (type != MediaType.VIDEO) return null // get duration for video only
    val retriever = MediaMetadataRetriever()
    retriever.setDataSource(path)
    val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
    retriever.release()
    return duration
  }

  enum class MediaType {
    TEXT, URL, IMAGE, VIDEO, FILE, WEB_SEARCH ;
  }

  override fun onNewIntent(intent: Intent): Boolean {
    handleIntent(intent, false)
    return false
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    this.binding = binding
    binding.addOnNewIntentListener(this)
    handleIntent(binding.activity.intent, true)
  }

  override fun onDetachedFromActivityForConfigChanges() {
    binding?.removeOnNewIntentListener(this)
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    this.binding = binding
    binding.addOnNewIntentListener(this)
  }

  override fun onDetachedFromActivity() {
    binding?.removeOnNewIntentListener(this)
  }

  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    Log.d(TAG, "onListen: arguments=$arguments, initialSharing=${initialSharing != null}, latestSharing=${latestSharing != null}")
    if (events == null) return
    when (arguments) {
      "sharing" -> {
        eventSinkSharing = events
        // Deliver any sharing data that arrived while no listener was registered,
        // but only when it is NOT the cold-start intent (initialSharing != null means
        // the cold-start data is still pending and should be retrieved via
        // getInitialSharing() to avoid duplicating it here).
        if (initialSharing == null) {
          latestSharing?.let {
            Log.d(TAG, "onListen: sending cached sharing data, latestSharing=$it")
            eventSinkSharing?.success(it.toString())
            latestSharing = null
          }
        }
      }
    }
  }

  override fun onCancel(arguments: Any?) {
    Log.d(TAG,"onCancel ==>> $arguments")
    when (arguments) {
      "sharing" -> eventSinkSharing = null
    }
  }


}
