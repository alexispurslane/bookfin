package dev.bookfin.bench.epub;

import android.app.Activity;
import android.graphics.Bitmap;
import android.graphics.Rect;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;
import android.view.Choreographer;
import android.view.PixelCopy;
import android.view.View;
import org.json.JSONObject;
import java.io.File;
import java.io.FileOutputStream;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class ProbeEvidence {
    private final Activity activity;
    private final ExecutorService storage = Executors.newSingleThreadExecutor();
    private JSONObject references = new JSONObject();
    private String referenceDigest = "";
    private int sequence;

    public ProbeEvidence(Activity activity) { this.activity = activity; }

    public void loadReferences() throws Exception {
        File file = new File(activity.getExternalFilesDir(null), "references.json");
        if (file.isFile()) {
            byte[] bytes = Files.readAllBytes(file.toPath());
            references = new JSONObject(new String(bytes, StandardCharsets.UTF_8));
            referenceDigest = digest(bytes);
        }
    }

    public interface Completion { void complete(JSONObject event); }

    public void capture(View surface, JSONObject metadata, Completion completion) {
        int[] position = new int[2];
        surface.getLocationInWindow(position);
        capture(new Rect(position[0], position[1], position[0] + surface.getWidth(), position[1] + surface.getHeight()), metadata, completion);
    }

    public void capture(Rect rect, JSONObject metadata, Completion completion) {
        captureAttempt(rect, metadata, completion, sequence++, 1, SystemClock.elapsedRealtimeNanos());
    }

    private void captureAttempt(Rect rect, JSONObject metadata, Completion completion, int ordinal, int attempt, long began) {
        Bitmap bitmap = Bitmap.createBitmap(rect.width(), rect.height(), Bitmap.Config.ARGB_8888);
        long copying = SystemClock.elapsedRealtimeNanos();
        PixelCopy.request(activity.getWindow(), rect, bitmap, code -> {
            long captured = SystemClock.elapsedRealtimeNanos();
            storage.execute(() -> {
                try {
                    JSONObject event = new JSONObject(metadata.toString());
                    String key = event.getString("engine") + "/" + event.getString("book") + "/" + event.getString("case");
                    JSONObject reference = references.optJSONObject(key);
                    ByteBuffer pixels = ByteBuffer.allocate(bitmap.getByteCount());
                    bitmap.copyPixelsToBuffer(pixels);
                    String hash = digest(pixels.array());
                    boolean calibration = event.getString("run_id").startsWith("calibration-");
                    boolean matched = reference != null && hash.equals(reference.getString("capture_sha256"));
                    if (!calibration && !matched && captured - began < 10_000_000_000L) {
                        activity.runOnUiThread(() -> Choreographer.getInstance().postFrameCallback(frame ->
                            captureAttempt(rect, metadata, completion, ordinal, attempt + 1, began)));
                        return;
                    }
                    event.put("pixel_copy_code", code);
                    event.put("end_ns", captured);
                    event.put("copy_start_ns", copying);
                    event.put("copy_duration_ns", captured - copying);
                    event.put("capture_attempts", attempt);
                    event.put("clock", "android_elapsed_realtime_ns");
                    event.put("boundary", "request_to_reference_window_copy");
                    event.put("window_copy_verified", code == PixelCopy.SUCCESS && matched && !calibration);
                    event.put("physical_display_verified", false);
                    event.put("process_id", android.os.Process.myPid());
                    event.put("capture_sha256", hash);
                    event.put("reference_manifest_sha256", referenceDigest);
                    event.put("reference_run_id", reference == null ? JSONObject.NULL : reference.opt("run_id"));
                    event.put("reference_sha256", reference == null ? JSONObject.NULL : reference.opt("capture_sha256"));
                    event.put("width_px", bitmap.getWidth());
                    event.put("height_px", bitmap.getHeight());
                    event.put("paper_rgb", bitmap.getPixel(0, 0) & 0xffffff);
                    if (event.has("cache_file")) {
                        File cacheFile = new File(event.getString("cache_file"));
                        event.put("cache_file_exists", cacheFile.isFile());
                        event.put("cache_file_bytes", cacheFile.length());
                    }
                    if (!calibration && !matched) event.put("error", "Window copy did not match the independent reference");
                    if (code != PixelCopy.SUCCESS) event.put("error", "PixelCopy error " + code);
                    File directory = new File(activity.getExternalFilesDir(null), "runs/" + event.getString("run_id"));
                    directory.mkdirs();
                    if (calibration || event.has("error") || event.optInt("round") == 0) {
                        File picture = new File(directory, ordinal + ".png");
                        try (FileOutputStream output = new FileOutputStream(picture)) {
                            bitmap.compress(Bitmap.CompressFormat.PNG, 100, output);
                        }
                        event.put("capture_path", picture.getAbsolutePath());
                    }
                    try (FileOutputStream output = new FileOutputStream(new File(directory, ordinal + ".json"))) {
                        output.write(event.toString(2).getBytes(StandardCharsets.UTF_8));
                    }
                    Log.i("EPUB_PROBE", event.toString());
                    activity.runOnUiThread(() -> completion.complete(event));
                } catch (Exception error) {
                    Log.e("EPUB_PROBE", "capture failed", error);
                    activity.runOnUiThread(() -> completion.complete(new JSONObject()));
                } finally { bitmap.recycle(); }
            });
        }, new Handler(Looper.getMainLooper()));
    }

    private static String digest(byte[] bytes) throws Exception {
        StringBuilder text = new StringBuilder();
        for (byte value : MessageDigest.getInstance("SHA-256").digest(bytes)) text.append(String.format("%02x", value & 255));
        return text.toString();
    }

    public void close() { storage.shutdown(); }
}
