package dev.bookfin.bench.epub;

import static org.junit.Assert.*;
import android.app.Activity;
import android.app.Instrumentation;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.os.SystemClock;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;
import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;

@RunWith(AndroidJUnit4.class)
public final class EngineWorkloadTest {
    @Test public void selectedBookWorkloadReachesEveryRequestedDestination() throws Exception {
        Instrumentation instrumentation = InstrumentationRegistry.getInstrumentation();
        Bundle arguments = InstrumentationRegistry.getArguments();
        Context context = instrumentation.getTargetContext();
        String selected = arguments.getString("book", "prose");
        String run = arguments.getString("run", "calibration-test");
        String round = arguments.getString("round", "-1");
        boolean calibration = run.startsWith("calibration-");
        JSONObject manifest = new JSONObject(new String(context.getAssets().open("manifest.json").readAllBytes(), StandardCharsets.UTF_8));
        JSONObject book = manifest.getJSONObject("books").getJSONObject(selected);
        JSONArray steps = manifest.getJSONArray("workload");
        File directory = new File(context.getExternalFilesDir(null), "runs/" + run);
        assertFalse("Run ids must be independent; previous evidence exists", directory.exists());
        Intent intent = context.getPackageManager().getLaunchIntentForPackage(context.getPackageName());
        assertNotNull("The release shell has a launch Activity", intent);
        intent.setData(Uri.parse("epubbench://run?book=" + selected + "&run=" + run + "&round=" + round));
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
        Activity activity = instrumentation.startActivitySync(intent);
        try {
            long deadline = SystemClock.elapsedRealtime() + 300_000;
            while (!new File(directory, "DONE").exists()) {
                File error = new File(directory, "ERROR");
                if (error.isFile()) fail("Real shell workload failed: " + new String(Files.readAllBytes(error.toPath()), StandardCharsets.UTF_8));
                assertTrue("The real shell workload did not finish within 300 seconds", SystemClock.elapsedRealtime() < deadline);
                Thread.sleep(100);
            }
            JSONObject previous = null;
            for (int sequence = 0; sequence < steps.length(); sequence++) {
                JSONObject step = steps.getJSONObject(sequence);
                File file = new File(directory, sequence + ".json");
                assertTrue("The shell must retain every operation, not only successful timings", file.isFile());
                JSONObject row = new JSONObject(new String(Files.readAllBytes(file.toPath()), StandardCharsets.UTF_8));
                assertEquals(step.getString("operation"), row.getString("operation"));
                assertEquals(step.getString("case"), row.getString("case"));
                assertEquals(book.getString("sha256"), row.getString("book_sha256"));
                assertEquals("PixelCopy must succeed", 0, row.getInt("pixel_copy_code"));
                assertEquals("The window must use the requested cream paper", 0xf6efe2, row.getInt("paper_rgb"));
                assertFalse("The renderer must produce actual page text", row.getString("visible_text").isBlank());
                assertTrue(row.getLong("start_ns") <= row.getLong("engine_ready_ns"));
                assertTrue(row.getLong("engine_ready_ns") < row.getLong("end_ns"));
                assertEquals(row.getString("id"), row.getString("preparation_event_id"));
                assertEquals(step.getString("operation"), row.getString("preparation_operation"));
                assertTrue("The engine receives a request after the shell dispatches it", row.getLong("start_ns") <= row.getLong("engine_start_ns"));
                assertTrue("The engine starts before its operation returns", row.getLong("engine_start_ns") <= row.getLong("operation_returned_ns"));
                if (step.getBoolean("measured")) {
                    assertTrue("The engine draws the page after it receives the request", row.getLong("engine_start_ns") < row.getLong("drawn_ns"));
                    assertTrue("The page is drawn before the window copy", row.getLong("drawn_ns") <= row.getLong("end_ns"));
                    assertFalse(row.getString("drawn_scope").isEmpty());
                }
                if (row.getString("engine").equals("koreader")) assertTrue("KOReader repeats its page draw after timing", row.getLong("redraw_duration_ns") > 0);
                if (row.getString("engine").equals("webview")) assertTrue("WebView records the images it awaited for the shown page", row.has("page_images"));
                if (row.getString("engine").equals("webview")) {
                    long shellDrawn = row.optLong("shell_drawn_ns", 0);
                    assertTrue("The WebView shell draws its own page before it reports ready, as the Flutter shell does",
                        shellDrawn > 0 && shellDrawn <= row.getLong("shell_ready_ns"));
                    long frameStart = row.optLong("frame_start_ns", 0);
                    assertTrue("WebView reports the start of the first frame after preparation, before the page is drawn",
                        row.getLong("preparation_ns") <= frameStart && frameStart < row.getLong("drawn_ns"));
                    assertTrue("WebView reports the vsync of the page's frame and of the next frame",
                        row.optLong("frame_vsync_ns", 0) > 0 && row.optLong("next_frame_vsync_ns", 0) > row.getLong("frame_vsync_ns"));
                }
                assertTrue(row.getLong("operation_returned_ns") <= row.getLong("preparation_ns"));
                assertTrue(row.getLong("preparation_ns") <= row.getLong("engine_ready_ns"));
                assertFalse(row.getJSONObject("phase_clock").getString("source").isEmpty());
                assertEquals(step.getString("case").equals("target20") ? 20 : 18, row.getInt("text_size_css_px"));
                int target = book.getJSONObject("target").getInt("index");
                String pageCase = step.getString("case");
                if (row.has("spine_index")) {
                    assertEquals("The requested source section must be shown", target + (pageCase.equals("after_crossing18") ? 1 : 0), row.getInt("spine_index"));
                } else {
                    int page = row.getInt("page");
                    int first = row.getInt("selected_heading_page");
                    int next = row.getInt("following_heading_page");
                    assertTrue("KOReader page must lie in the selected chapter", pageCase.equals("after_crossing18") ? page == next : page >= first && page < next);
                    if (pageCase.equals("target18") || pageCase.equals("target20")) assertEquals(first, page);
                }
                if (step.getString("operation").equals("page_turn")) {
                    assertNotEquals("A page turn must change its source location", previous.getString("location"), row.getString("location"));
                    assertNotEquals("A stale page is not a completed page turn", previous.getString("capture_sha256"), row.getString("capture_sha256"));
                }
                if (pageCase.equals("before_crossing18")) {
                    if (row.has("section_last_page")) assertTrue("Crossing preparation must show the last page", row.getBoolean("section_last_page"));
                    if (row.has("displayed")) assertEquals(row.getJSONObject("displayed").getInt("total"), row.getJSONObject("displayed").getInt("page"));
                    if (row.has("page")) assertEquals(row.getInt("following_heading_page") - 1, row.getInt("page"));
                }
                if (step.getString("operation").equals("chapter_crossing")) {
                    assertEquals("prepare_crossing", previous.getString("operation"));
                    assertNotEquals(previous.getString("location"), row.getString("location"));
                    if (row.has("page")) assertEquals(previous.getInt("page") + 1, row.getInt("page"));
                }
                if (step.getString("operation").equals("font_change")) {
                    assertEquals("prepare_target", previous.getString("operation"));
                    assertEquals(18, previous.getInt("text_size_css_px"));
                    assertNotEquals(previous.getString("capture_sha256"), row.getString("capture_sha256"));
                }
                if (!calibration) {
                    assertFalse("No operation may silently fail", row.has("error"));
                    assertTrue("Independent calibrated pixels must match", row.getBoolean("window_copy_verified"));
                    assertEquals(row.getString("reference_sha256"), row.getString("capture_sha256"));
                    assertNotEquals(run, row.getString("reference_run_id"));
                }
                previous = row;
            }
        } finally { instrumentation.runOnMainSync(activity::finish); }
    }
}
