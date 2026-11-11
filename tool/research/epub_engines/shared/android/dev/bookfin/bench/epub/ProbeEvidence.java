package dev.bookfin.bench.epub;

import android.app.Activity;
import android.graphics.Bitmap;
import android.graphics.Rect;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;
import android.view.PixelCopy;
import android.view.View;
import org.json.JSONObject;
import java.io.File;
import java.io.FileOutputStream;
import java.nio.ByteBuffer;
import java.security.MessageDigest;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class ProbeEvidence {
    private final Activity activity;
    private final ExecutorService storage = Executors.newSingleThreadExecutor();
    private int sequence;

    public ProbeEvidence(Activity activity) {
        this.activity = activity;
    }

    public interface Completion {
        void complete(JSONObject event);
    }

    public void capture(View surface, JSONObject metadata, Completion completion) {
        int[] position = new int[2];
        surface.getLocationInWindow(position);
        Rect rect = new Rect(position[0], position[1], position[0] + surface.getWidth(), position[1] + surface.getHeight());
        capture(rect, metadata, completion);
    }

    public void capture(Rect rect, JSONObject metadata, Completion completion) {
        Bitmap bitmap = Bitmap.createBitmap(rect.width(), rect.height(), Bitmap.Config.ARGB_8888);
        int ordinal = sequence++;
        PixelCopy.request(activity.getWindow(), rect, bitmap, code -> {
            long captured = SystemClock.elapsedRealtimeNanos();
            storage.execute(() -> {
                try {
                    JSONObject event = new JSONObject(metadata.toString());
                    event.put("kind", "unverified_probe");
                    event.put("pixel_copy_code", code);
                    event.put("capture_complete_ns", captured);
                    event.put("clock", "android_elapsed_realtime_ns");
                    event.put("presentation_verified", false);
                    if (code == PixelCopy.SUCCESS) {
                        File directory = new File(activity.getExternalFilesDir(null), "probe");
                        directory.mkdirs();
                        File picture = new File(directory, ordinal + ".png");
                        try (FileOutputStream output = new FileOutputStream(picture)) {
                            bitmap.compress(Bitmap.CompressFormat.PNG, 100, output);
                        }
                        ByteBuffer pixels = ByteBuffer.allocate(bitmap.getByteCount());
                        bitmap.copyPixelsToBuffer(pixels);
                        StringBuilder digest = new StringBuilder();
                        for (byte value : MessageDigest.getInstance("SHA-256").digest(pixels.array())) {
                            digest.append(String.format("%02x", value & 255));
                        }
                        event.put("capture_sha256", digest.toString());
                        event.put("capture_path", picture.getAbsolutePath());
                        event.put("width_px", bitmap.getWidth());
                        event.put("height_px", bitmap.getHeight());
                        try (FileOutputStream output = new FileOutputStream(new File(directory, ordinal + ".json"))) {
                            output.write(event.toString(2).getBytes(java.nio.charset.StandardCharsets.UTF_8));
                        }
                    }
                    Log.i("EPUB_PROBE", event.toString());
                    activity.runOnUiThread(() -> completion.complete(event));
                } catch (Exception error) {
                    Log.e("EPUB_PROBE", "capture failed", error);
                    activity.runOnUiThread(() -> completion.complete(new JSONObject()));
                } finally {
                    bitmap.recycle();
                }
            });
        }, new Handler(Looper.getMainLooper()));
    }

    public void close() {
        storage.shutdown();
    }
}
