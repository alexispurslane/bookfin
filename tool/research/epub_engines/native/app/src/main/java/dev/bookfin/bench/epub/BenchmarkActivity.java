package dev.bookfin.bench.epub;

import android.app.Activity;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.os.SystemClock;
import android.util.Log;
import android.view.Gravity;
import android.view.View;
import android.webkit.JavascriptInterface;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;
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
    private String selectedBook;
    private long requested;
    private boolean busy = true;

    @Override
    public void onCreate(Bundle state) {
        super.onCreate(state);
        evidence = new ProbeEvidence(this);
        selectedBook = getIntent().getData() == null ? "prose" : getIntent().getData().getQueryParameter("book");
        if (selectedBook == null) selectedBook = "prose";
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setGravity(Gravity.CENTER);
        root.setBackgroundColor(Color.rgb(246, 239, 226));
        status = new TextView(this);
        status.setText(BuildConfig.ENGINE + ": " + selectedBook + ". Unverified probe, not benchmark results.");
        root.addView(status);
        LinearLayout actions = new LinearLayout(this);
        for (String operation : new String[]{"page_turn", "section_jump", "font_change", "reopen"}) {
            Button button = new Button(this);
            button.setText(operation.replace('_', ' '));
            button.setTextSize(9);
            button.setOnClickListener(view -> dispatch(operation));
            actions.addView(button, new LinearLayout.LayoutParams(0, 48*getResources().getDisplayMetrics().densityDpi/160, 1));
        }
        root.addView(actions);
        page = new FrameLayout(this);
        float density = getResources().getDisplayMetrics().density;
        root.addView(page, new LinearLayout.LayoutParams(Math.round(360*density), Math.round(640*density)));
        setContentView(root);
        worker.execute(() -> {
            try {
                book = new JSONObject(readAsset("manifest.json")).getJSONObject("books").getJSONObject(selectedBook);
                runOnUiThread(() -> page.post(this::startEngine));
            } catch (Exception error) {
                failed(error);
            }
        });
    }

    private void startEngine() {
        requested = SystemClock.elapsedRealtimeNanos();
        if (BuildConfig.ENGINE.equals("webview")) {
            web = new WebView(this);
            web.setBackgroundColor(Color.rgb(246, 239, 226));
            web.getSettings().setJavaScriptEnabled(true);
            web.getSettings().setAllowFileAccess(false);
            web.getSettings().setAllowContentAccess(false);
            web.getSettings().setCacheMode(android.webkit.WebSettings.LOAD_NO_CACHE);
            web.getSettings().setTextZoom(100);
            web.addJavascriptInterface(new WebProbe(), "Probe");
            web.setWebViewClient(new WebViewClient() {
                @Override
                public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
                    try {
                        Uri uri = request.getUrl();
                        if (!"https".equals(uri.getScheme()) || !"epubbench.invalid".equals(uri.getHost())) {
                            return new WebResourceResponse("text/plain", "UTF-8", 403, "Offline shell", Map.of(), InputStream.nullInputStream());
                        }
                        String path = uri.getPath().substring(1);
                        String mime = path.endsWith("js") ? "text/javascript" : path.endsWith("html") ? "text/html" : path.endsWith("json") ? "application/json" : path.endsWith("ttf") ? "font/ttf" : "application/epub+zip";
                        return new WebResourceResponse(mime, "UTF-8", 200, "OK", Map.of("Access-Control-Allow-Origin", "*", "Cache-Control", "no-store"), getAssets().open(path));
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
                        + ";book_path=" + quote(original.getAbsolutePath())
                        + ";data_path=" + quote(new File(directory, "ko-data").getAbsolutePath())
                        + ";heading=" + quote(book.getJSONObject("target").getString("toc_title"))
                        + ";cre.registerFont(" + quote(new File(directory, "SourceSerif4.ttf").getAbsolutePath()) + ")"
                        + ";cre.initCache(" + quote(cache.getAbsolutePath()) + ",67108864)"
                        + ";cre.initHyphDict(data_path..'/hyph/')\n" + readAsset("ko-probe.lua");
                    KoBridge.evaluate(setup);
                    performKo("open");
                } catch (Exception error) {
                    failed(error);
                }
            });
        }
    }

    private void dispatch(String operation) {
        if (busy) return;
        busy = true;
        requested = SystemClock.elapsedRealtimeNanos();
        status.setText(BuildConfig.ENGINE + ": " + operation + " (unverified probe)");
        if (web != null) web.evaluateJavascript("window.command(" + JSONObject.quote(operation) + ")", null);
        else worker.execute(() -> {
            try { performKo(operation); } catch (Exception error) { failed(error); }
        });
    }

    private void performKo(String operation) throws Exception {
        JSONObject metadata = new JSONObject(KoBridge.evaluate("return perform(" + quote(operation) + ")"));
        metadata.put("engine_ready_ns", SystemClock.elapsedRealtimeNanos());
        Bitmap bitmap = Bitmap.createBitmap(page.getWidth(), page.getHeight(), Bitmap.Config.ARGB_8888);
        KoBridge.copyPixels(bitmap);
        runOnUiThread(() -> {
            Bitmap previous = currentBitmap;
            currentBitmap = bitmap;
            image.setImageBitmap(bitmap);
            page.getViewTreeObserver().registerFrameCommitCallback(() -> capture(metadata));
            page.invalidate();
            if (previous != null) previous.recycle();
        });
    }

    private void capture(JSONObject metadata) {
        try {
            metadata.put("engine", BuildConfig.ENGINE);
            metadata.put("book", selectedBook);
            metadata.put("request_ns", requested);
            metadata.put("book_sha256", book.getString("sha256"));
            metadata.put("expected_section", book.getJSONObject("target").getInt("index"));
            evidence.capture(page, metadata, event -> {
                busy = false;
                status.setText(BuildConfig.ENGINE + ": captured probe. Destination and pixels still need validation.");
            });
        } catch (Exception error) { failed(error); }
    }

    private final class WebProbe {
        @JavascriptInterface
        public void ready(String raw) {
            long ready = SystemClock.elapsedRealtimeNanos();
            runOnUiThread(() -> {
                try {
                    JSONObject metadata = new JSONObject(raw);
                    metadata.put("engine_ready_ns", ready);
                    web.postVisualStateCallback(ready, new WebView.VisualStateCallback() {
                        @Override public void onComplete(long requestId) {
                            page.getViewTreeObserver().registerFrameCommitCallback(() -> capture(metadata));
                            web.invalidate();
                        }
                    });
                } catch (Exception error) { BenchmarkActivity.this.failed(error); }
            });
        }

        @JavascriptInterface
        public void failed(String message) { BenchmarkActivity.this.failed(new IllegalStateException(message)); }
    }

    private static String quote(String value) {
        return "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r") + "\"";
    }

    private String readAsset(String path) throws Exception {
        try (InputStream input = getAssets().open(path)) {
            return new String(input.readAllBytes(), StandardCharsets.UTF_8);
        }
    }

    private void copyAsset(String path, File target) throws Exception {
        try (InputStream input = getAssets().open(path); FileOutputStream output = new FileOutputStream(target)) {
            input.transferTo(output);
        }
    }

    private void copyTree(String path, File target) throws Exception {
        String[] children = getAssets().list(path);
        if (children.length == 0) { copyAsset(path, target); return; }
        target.mkdirs();
        for (String child : children) copyTree(path + "/" + child, new File(target, child));
    }

    private void failed(Exception error) {
        Log.e("EPUB_PROBE", "Probe failed; no benchmark sample", error);
        runOnUiThread(() -> { busy = false; status.setText("Probe failed: " + error); });
    }

    @Override
    public void onDestroy() {
        if (web != null) web.destroy();
        worker.shutdown();
        evidence.close();
        super.onDestroy();
    }
}
