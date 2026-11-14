package dev.bookfin.bookfin.ocr;

import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Semaphore;

public final class OcrWorker {
    public interface Engine {
        int[] layout(byte[] bgra, int width, int height) throws Exception;
        String recognize(byte[] bgra, int width, int height) throws Exception;
        String recognizeKept() throws Exception;
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
    private Throwable terminalFailure;

    public OcrWorker(Factory factory) { this.factory = factory; }

    public synchronized boolean requiresRestart() { return terminalFailure != null; }

    /**
     * Runs the layout pass on the page [bgra] of [width] by [height] pixels
     * and gives its layout record. The engine keeps the page for
     * [recognizeKept].
     */
    public synchronized CompletableFuture<int[]> layout(byte[] bgra, int width, int height) {
        return run(validPage(bgra, width, height), engine -> engine.layout(bgra, width, height));
    }

    /** Recognizes the page [bgra] of [width] by [height] pixels and gives its hOCR. */
    public synchronized CompletableFuture<String> recognize(byte[] bgra, int width, int height) {
        return run(validPage(bgra, width, height), engine -> engine.recognize(bgra, width, height));
    }

    /**
     * Recognizes the page that the last layout pass kept and gives its hOCR.
     * It fails as an ordinary page failure when no layout pass kept a page.
     */
    public synchronized CompletableFuture<String> recognizeKept() {
        return run(true, Engine::recognizeKept);
    }

    private static boolean validPage(byte[] bgra, int width, int height) {
        return bgra != null && width >= 1 && height >= 1 &&
            (long) width * height <= 6400000 && (long) width * height * 4 == bgra.length;
    }

    private interface Operation<T> { T run(Engine engine) throws Exception; }

    /**
     * Admits one [operation] on the engine, which it creates first if needed.
     * A closing or busy worker, or an invalid page, refuses it.
     */
    private <T> CompletableFuture<T> run(boolean valid, Operation<T> operation) {
        CompletableFuture<T> result = new CompletableFuture<>();
        if (closing != null || busy || !valid) {
            result.completeExceptionally(new IllegalStateException("Recognition is closed, busy, or has an invalid page."));
            return result;
        }
        busy = true;
        executor.execute(() -> {
            T value = null;
            Throwable failure = null;
            boolean unsafe = false;
            try {
                if (engine == null) {
                    if (!ENGINE_OWNER.tryAcquire()) throw new IllegalStateException("Another recognition owner is draining.");
                    ownsEngine = true;
                    engine = factory.create();
                }
                value = operation.run(engine);
            } catch (Throwable error) {
                failure = error;
                unsafe = error instanceof Error;
                try {
                    releaseEngine();
                } catch (Throwable closeError) {
                    failure = retainFailure(error, closeError);
                    unsafe = true;
                }
            } finally {
                synchronized (this) {
                    busy = false;
                    if (unsafe) {
                        terminalFailure = failure;
                        close();
                    }
                }
            }
            if (failure == null) result.complete(value);
            else result.completeExceptionally(failure);
        });
        return result;
    }

    private static Throwable retainFailure(Throwable failure, Throwable cleanup) {
        if (failure == cleanup) return failure;
        if (cleanup instanceof Error && !(failure instanceof Error)) {
            cleanup.addSuppressed(failure);
            return cleanup;
        }
        failure.addSuppressed(cleanup);
        return failure;
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
            Throwable failure = terminalFailure;
            try {
                releaseEngine();
            } catch (Throwable error) {
                failure = failure == null ? error : retainFailure(failure, error);
            }
            if (failure == null) closing.complete(null);
            else closing.completeExceptionally(failure);
        });
        executor.shutdown();
        return closing;
    }
}
