package dev.bookfin.bookfin.ocr;

import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Semaphore;

public final class OcrWorker {
    public interface Engine {
        String recognize(byte[] bgra, int width, int height) throws Exception;
        void close() throws Exception;
    }
    public interface Factory { Engine create() throws Exception; }
    private static final Semaphore ENGINE_OWNER = new Semaphore(1);
    private final Factory factory;
    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private Engine engine;
    private boolean ownsEngine;
    private boolean busy;
    private CompletableFuture<Void> closing;

    public OcrWorker(Factory factory) { this.factory = factory; }

    public synchronized CompletableFuture<String> recognize(byte[] bgra, int width, int height) {
        CompletableFuture<String> result = new CompletableFuture<>();
        if (closing != null || busy || width < 1 || height < 1 ||
                (long) width * height > 6400000 || (long) width * height * 4 != bgra.length) {
            result.completeExceptionally(new IllegalStateException("Recognition is closed, busy, or has an invalid page."));
            return result;
        }
        busy = true;
        executor.execute(() -> {
            String text = null;
            Exception failure = null;
            try {
                if (engine == null) {
                    if (!ENGINE_OWNER.tryAcquire()) throw new IllegalStateException("Another recognition owner is draining.");
                    ownsEngine = true;
                    engine = factory.create();
                }
                text = engine.recognize(bgra, width, height);
            } catch (Exception error) {
                failure = error;
                try { releaseEngine(); } catch (Exception closeError) { error.addSuppressed(closeError); }
            }
            synchronized (this) { busy = false; }
            if (failure == null) result.complete(text);
            else result.completeExceptionally(failure);
        });
        return result;
    }

    private void releaseEngine() throws Exception {
        try {
            if (engine != null) engine.close();
        } finally {
            engine = null;
            if (ownsEngine) {
                ownsEngine = false;
                ENGINE_OWNER.release();
            }
        }
    }

    public synchronized CompletableFuture<Void> close() {
        if (closing != null) return closing;
        closing = new CompletableFuture<>();
        executor.execute(() -> {
            try {
                releaseEngine();
                closing.complete(null);
            } catch (Exception error) {
                closing.completeExceptionally(error);
            }
        });
        executor.shutdown();
        return closing;
    }
}
