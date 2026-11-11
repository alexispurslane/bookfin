package dev.bookfin.bench.epub;

import android.app.Activity;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.os.SystemClock;
import android.util.Log;
import android.view.Gravity;
import android.webkit.JavascriptInterface;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class BenchmarkActivity extends Activity {
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private ProbeEvidence evidence;
    private FrameLayout page;
    private TextView status;
    private WebView web;
    private ImageView image;
    private Bitmap currentBitmap;
    private JSONObject book;
    private JSONArray steps;
    private String selectedBook;
    private String runId;
    private int round;
    private int stepIndex;
    private long requested;
    private long shellReady;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        evidence = new ProbeEvidence(this);
        Uri uri = getIntent().getData();
        selectedBook = uri == null ? "prose" : uri.getQueryParameter("book");
        runId = uri == null ? "calibration-default" : uri.getQueryParameter("run");
        if (selectedBook == null) selectedBook = "prose";
        if (runId == null) runId = "calibration-" + selectedBook;
        if (!runId.matches("[a-zA-Z0-9_-]+")) throw new IllegalArgumentException("Invalid run id");
        round = uri == null || uri.getQueryParameter("round") == null ? -1 : Integer.parseInt(uri.getQueryParameter("round"));
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setGravity(Gravity.CENTER);
        root.setBackgroundColor(Color.rgb(246, 239, 226));
        status = new TextView(this);
        status.setText(BuildConfig.ENGINE + ": preparing isolated shell");
        root.addView(status);
        page = new FrameLayout(this);
        float density = getResources().getDisplayMetrics().density;
        root.addView(page, new LinearLayout.LayoutParams(Math.round(360*density), Math.round(640*density)));
        setContentView(root);
        worker.execute(() -> {
            try {
                evidence.loadReferences();
                JSONObject manifest = new JSONObject(readAsset("manifest.json"));
                book = manifest.getJSONObject("books").getJSONObject(selectedBook);
                steps = manifest.getJSONArray("workload");
                removeTree(new File(getFilesDir(), "fixture"));
                removeTree(new File(getCacheDir(), "crengine"));
                runOnUiThread(() -> page.post(this::startEngine));
            } catch (Exception error) { failed(error); }
        });
    }

    private void startEngine() {
        if (BuildConfig.ENGINE.equals("webview")) {
            web = new WebView(this);
            web.clearCache(true);
            web.setBackgroundColor(Color.rgb(246, 239, 226));
            web.getSettings().setJavaScriptEnabled(true);
            web.getSettings().setAllowFileAccess(false);
            web.getSettings().setAllowContentAccess(false);
            web.getSettings().setCacheMode(android.webkit.WebSettings.LOAD_DEFAULT);
            web.getSettings().setTextZoom(100);
            web.addJavascriptInterface(new WebProbe(), "Probe");
            web.setWebViewClient(new WebViewClient() {
                @Override public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
                    try {
                        Uri uri = request.getUrl();
                        if (!"https".equals(uri.getScheme()) || !"epubbench.invalid".equals(uri.getHost()))
                            return new WebResourceResponse("text/plain", "UTF-8", 403, "Offline shell", Map.of(), InputStream.nullInputStream());
                        String path = uri.getPath().substring(1);
                        String mime = path.endsWith("js") ? "text/javascript" : path.endsWith("html") ? "text/html" : path.endsWith("json") ? "application/json" : path.endsWith("ttf") ? "font/ttf" : "application/epub+zip";
                        return new WebResourceResponse(mime, "UTF-8", 200, "OK", Map.of("Access-Control-Allow-Origin", "*", "Cache-Control", "public, max-age=86400"), getAssets().open(path));
                    } catch (Exception error) {
                        failed(error);
                        return new WebResourceResponse("text/plain", "UTF-8", 404, "Not found", Map.of(), InputStream.nullInputStream());
                    }
                }
            });
            page.addView(web, new FrameLayout.LayoutParams(-1, -1));
            web.loadUrl("https://epubbench.invalid/web/shell.html?book=" + selectedBook);
        } else {
            image = new ImageView(this);
            image.setScaleType(ImageView.ScaleType.FIT_XY);
            page.addView(image, new FrameLayout.LayoutParams(-1, -1));
            worker.execute(() -> {
                try {
                    File directory = new File(getFilesDir(), "fixture");
                    directory.mkdirs();
                    copyAsset("SourceSerif4.ttf", new File(directory, "SourceSerif4.ttf"));
                    File original = new File(directory, book.getString("file"));
                    copyAsset(book.getString("file"), original);
                    copyTree("ko-data", new File(directory, "ko-data"));
                    File cache = new File(getCacheDir(), "crengine");
                    cache.mkdirs();
                    String setup = "width_px=" + page.getWidth() + ";height_px=" + page.getHeight()
                        + ";density=" + getResources().getDisplayMetrics().density
                        + ";book_path=" + luaString(original.getAbsolutePath())
                        + ";data_path=" + luaString(new File(directory, "ko-data").getAbsolutePath())
                        + ";heading=" + luaString(book.getJSONObject("target").getString("toc_title"))
                        + ";next_heading=" + luaString(book.getJSONArray("sections").getJSONObject(book.getJSONObject("target").getInt("index")+1).getString("toc_title"))
                        + ";cre.registerFont(" + luaString(new File(directory, "SourceSerif4.ttf").getAbsolutePath()) + ")"
                        + ";cre.initCache(" + luaString(cache.getAbsolutePath()) + ",67108864)"
                        + ";cre.initHyphDict(data_path..'/hyph/')\n" + readAsset("ko-probe.lua");
                    KoBridge.evaluate(setup);
                    runOnUiThread(this::ready);
                } catch (Exception error) { failed(error); }
            });
        }
    }

    private void ready() { shellReady = SystemClock.elapsedRealtimeNanos(); dispatch(); }

    private static String luaString(String value) {
        String equals = "=";
        while (value.contains("]" + equals + "]")) equals += "=";
        return "[" + equals + "[" + value + "]" + equals + "]";
    }

    private void dispatch() {
        try {
            if (stepIndex == steps.length()) {
                status.setText(BuildConfig.ENGINE + ": complete " + runId);
                File directory = new File(getExternalFilesDir(null), "runs/" + runId);
                worker.execute(() -> {
                    try { new File(directory, "DONE").createNewFile(); }
                    catch (Exception error) { failed(error); }
                });
                return;
            }
            String operation = steps.getJSONObject(stepIndex).getString("operation");
            status.setText(BuildConfig.ENGINE + ": " + operation);
            requested = SystemClock.elapsedRealtimeNanos();
            if (web != null) web.evaluateJavascript("window.command(" + JSONObject.quote(operation) + ")", null);
            else worker.execute(() -> {
                try { performKo(operation); } catch (Exception error) { failed(error); }
            });
        } catch (Exception error) { failed(error); }
    }

    private void performKo(String operation) throws Exception {
        JSONObject metadata = new JSONObject(KoBridge.evaluate("return perform(" + JSONObject.quote(operation) + ")"));
        metadata.put("engine_ready_ns", SystemClock.elapsedRealtimeNanos());
        Bitmap bitmap = Bitmap.createBitmap(page.getWidth(), page.getHeight(), Bitmap.Config.ARGB_8888);
        KoBridge.copyPixels(bitmap);
        runOnUiThread(() -> {
            Bitmap previous = currentBitmap;
            currentBitmap = bitmap;
            image.setImageBitmap(bitmap);
            if (runId.startsWith("calibration-")) {
                page.getViewTreeObserver().registerFrameCommitCallback(() -> capture(metadata));
                page.invalidate();
            } else capture(metadata);
            if (previous != null) previous.recycle();
        });
    }

    private void capture(JSONObject metadata) {
        try {
            JSONObject step = steps.getJSONObject(stepIndex);
            metadata.put("engine", BuildConfig.ENGINE);
            metadata.put("book", selectedBook);
            metadata.put("run_id", runId);
            metadata.put("round", round);
            metadata.put("sequence", stepIndex);
            metadata.put("id", runId + "/" + stepIndex);
            metadata.put("case", step.getString("case"));
            metadata.put("measured", step.getBoolean("measured"));
            metadata.put("warmup", runId.startsWith("calibration-"));
            metadata.put("start_ns", requested);
            metadata.put("shell_ready_ns", shellReady);
            metadata.put("process_start_ns", android.os.Process.getStartElapsedRealtime()*1_000_000L);
            metadata.put("book_sha256", book.getString("sha256"));
            metadata.put("cache", stepIndex == 0 ? "fresh_document" : "warm_document");
            metadata.put("expected_section", book.getJSONObject("target").getInt("index") + (step.getString("case").equals("after_crossing18") ? 1 : 0));
            evidence.capture(page, metadata, event -> { stepIndex++; dispatch(); });
        } catch (Exception error) { failed(error); }
    }

    private final class WebProbe {
        @JavascriptInterface public void shellReady() { runOnUiThread(BenchmarkActivity.this::ready); }
        @JavascriptInterface public void ready(String raw) {
            long ready = SystemClock.elapsedRealtimeNanos();
            runOnUiThread(() -> {
                try {
                    JSONObject metadata = new JSONObject(raw);
                    metadata.put("engine_ready_ns", ready);
                    if (!runId.startsWith("calibration-")) { capture(metadata); return; }
                    web.postVisualStateCallback(ready, new WebView.VisualStateCallback() {
                        @Override public void onComplete(long requestId) {
                            page.getViewTreeObserver().registerFrameCommitCallback(() -> capture(metadata));
                            web.invalidate();
                        }
                    });
                } catch (Exception error) { BenchmarkActivity.this.failed(error); }
            });
        }
        @JavascriptInterface public void failed(String message) { BenchmarkActivity.this.failed(new IllegalStateException(message)); }
    }

    private String readAsset(String path) throws Exception {
        try (InputStream input = getAssets().open(path)) { return new String(input.readAllBytes(), StandardCharsets.UTF_8); }
    }
    private void copyAsset(String path, File target) throws Exception {
        try (InputStream input = getAssets().open(path); FileOutputStream output = new FileOutputStream(target)) { input.transferTo(output); }
    }
    private void copyTree(String path, File target) throws Exception {
        String[] children = getAssets().list(path);
        if (children.length == 0) { copyAsset(path, target); return; }
        target.mkdirs();
        for (String child : children) copyTree(path + "/" + child, new File(target, child));
    }
    private static void removeTree(File file) throws Exception {
        if (!file.exists()) return;
        File[] children = file.listFiles();
        if (children != null) for (File child : children) removeTree(child);
        if (!file.delete()) throw new IllegalStateException("Could not remove benchmark fixture " + file);
    }
    private void failed(Exception error) {
        Log.e("EPUB_PROBE", "Workload failed; no accepted timing", error);
        runOnUiThread(() -> status.setText("Workload failed: " + error));
        worker.execute(() -> {
            try {
                File directory = new File(getExternalFilesDir(null), "runs/" + runId);
                directory.mkdirs();
                java.nio.file.Files.write(new File(directory, "ERROR").toPath(), error.toString().getBytes(StandardCharsets.UTF_8));
            } catch (Exception storageError) { Log.e("EPUB_PROBE", "Could not retain failure", storageError); }
        });
    }
    @Override public void onDestroy() {
        if (web != null) web.destroy();
        worker.shutdown();
        evidence.close();
        super.onDestroy();
    }
}
