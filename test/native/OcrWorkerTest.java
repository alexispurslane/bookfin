import dev.bookfin.bookfin.ocr.OcrWorker;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

public final class OcrWorkerTest {
    static void fatalBoundary(String boundary, Error fatal, boolean closeFails) throws Exception {
        CountDownLatch started = new CountDownLatch(1);
        CountDownLatch release = new CountDownLatch(1);
        AtomicInteger created = new AtomicInteger();
        AtomicInteger closed = new AtomicInteger();
        OcrWorker worker = new OcrWorker(() -> {
            created.incrementAndGet();
            if (boundary.equals("init")) {
                started.countDown();
                require(release.await(5, TimeUnit.SECONDS), "release fatal initialization");
                throw fatal;
            }
            return new OcrWorker.Engine() {
                public String recognize(byte[] bgra, int width, int height) throws Exception {
                    started.countDown();
                    require(release.await(5, TimeUnit.SECONDS), "release fatal operation");
                    if (!boundary.equals("close")) throw fatal;
                    return "before close";
                }
                public void close() {
                    closed.incrementAndGet();
                    if (closeFails || boundary.equals("close")) throw fatal;
                }
            };
        });
        try {
            CompletableFuture<String> operation = worker.recognize(new byte[4], 1, 1);
            require(started.await(5, TimeUnit.SECONDS), "fatal boundary is actually entered");
            CompletableFuture<Void> closing = worker.close();
            require(!closing.isDone(), "fatal close still waits for the admitted operation");
            release.countDown();
            Throwable failure = operation.handle((text, error) -> error).get(2, TimeUnit.SECONDS);
            require(boundary.equals("close") ? failure == null : failure == fatal,
                "fatal operation settles with its original Error, not an ordinary retriable exception");
            Throwable closeFailure = closing.handle((value, error) -> error).get(2, TimeUnit.SECONDS);
            require(closeFailure == fatal, "close reports the fatal boundary failure");
            require(worker.recognize(new byte[4], 1, 1).isCompletedExceptionally(), "fatal worker cannot admit later work");
            require(created.get() == 1, "fatal worker never recreates its engine");
            require(closed.get() == (boundary.equals("init") ? 0 : 1), "fatal cleanup releases once");
        } finally {
            release.countDown();
            worker.close().handle((value, error) -> null).get(2, TimeUnit.SECONDS);
        }
    }
    static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
    public static void main(String[] arguments) throws Exception {
        if (arguments.length == 1) {
            fatalBoundary(arguments[0], new AssertionError("held " + arguments[0]), false);
            return;
        }
        AtomicInteger live = new AtomicInteger();
        CountDownLatch started = new CountDownLatch(1);
        CountDownLatch release = new CountDownLatch(1);
        OcrWorker worker = new OcrWorker(() -> {
            live.incrementAndGet();
            return new OcrWorker.Engine() {
                public String recognize(byte[] bgra, int width, int height) throws Exception {
                    started.countDown();
                    require(release.await(5, TimeUnit.SECONDS), "test must release the native page");
                    require(live.get() == 1, "the page retains its engine until recognition drains");
                    return "recognized source page";
                }
                public void close() { live.decrementAndGet(); }
            };
        });
        CompletableFuture<String> page = worker.recognize(new byte[4], 1, 1);
        if (!started.await(1, TimeUnit.SECONDS)) {
            release.countDown();
            worker.close().get(5, TimeUnit.SECONDS);
            throw new AssertionError("production worker must actually admit recognition");
        }
        require(worker.recognize(new byte[4], 1, 1).isCompletedExceptionally(), "a busy worker must reject another raster");
        AtomicInteger otherOwners = new AtomicInteger();
        OcrWorker other = new OcrWorker(() -> {
            otherOwners.incrementAndGet();
            throw new IllegalStateException("another engine must not start");
        });
        boolean refused = other.recognize(new byte[4], 1, 1)
            .handle((value, error) -> error != null).get(5, TimeUnit.SECONDS);
        other.close().get(5, TimeUnit.SECONDS);
        require(refused && otherOwners.get() == 0, "another worker must not create a parallel process-wide native engine");
        CompletableFuture<Void> closing = worker.close();
        require(!closing.isDone(), "close must wait for active native page work");
        require(worker.recognize(new byte[4], 1, 1).isCompletedExceptionally(), "a closing worker must reject new work");
        require(live.get() == 1, "close must not recycle the active engine");
        release.countDown();
        require(page.get(5, TimeUnit.SECONDS).equals("recognized source page"), "the admitted page must finish without interruption");
        closing.get(5, TimeUnit.SECONDS);
        require(live.get() == 0, "close must release the engine after draining");
        require(worker.close() == closing, "close must be idempotent");
        AtomicInteger attempts = new AtomicInteger();
        OcrWorker retry = new OcrWorker(() -> {
            if (attempts.incrementAndGet() == 1) throw new java.io.IOException("fixture initialization failure");
            return new OcrWorker.Engine() {
                public String recognize(byte[] bgra, int width, int height) { return "retry succeeds"; }
                public void close() {}
            };
        });
        require(retry.recognize(new byte[4], 1, 1).handle((value, error) -> error != null).get(5, TimeUnit.SECONDS), "initialization failure must be reported");
        require(retry.recognize(new byte[4], 1, 1).get(5, TimeUnit.SECONDS).equals("retry succeeds"), "initialization failure must not retain a dead engine owner");
        retry.close().get(5, TimeUnit.SECONDS);
        require(retry.recognize(new byte[3], 1, 1).isCompletedExceptionally(), "invalid raster input must be rejected");
        fatalBoundary("operation", new UnsatisfiedLinkError("held JNI boundary"), false);
        fatalBoundary("init", new OutOfMemoryError("held initialization boundary"), false);
        fatalBoundary("close", new AssertionError("held close invariant"), false);
        fatalBoundary("operation", new AssertionError("held invariant"), true);
        AtomicInteger unsafeAdmissions = new AtomicInteger();
        Error fatal = new UnsatisfiedLinkError("unusable engine");
        OcrWorker unusable = new OcrWorker(() -> {
            unsafeAdmissions.incrementAndGet();
            throw fatal;
        });
        require(unusable.recognize(new byte[4], 1, 1).handle((value, error) -> error).get(2, TimeUnit.SECONDS) == fatal,
            "fatal initialization settles without a caller first requesting close");
        require(unusable.recognize(new byte[4], 1, 1).isCompletedExceptionally(), "fatal shutdown rejects later work on its own");
        require(unusable.close().handle((value, error) -> error).get(2, TimeUnit.SECONDS) == fatal,
            "fatal shutdown remains visible to the document owner");
        require(unsafeAdmissions.get() == 1, "fatal shutdown cannot initialize another engine");
        require(unusable.requiresRestart(), "the channel must distinguish a fatal worker from an ordinary retry");
        OcrWorker afterFatal = new OcrWorker(() -> new OcrWorker.Engine() {
            public String recognize(byte[] bgra, int width, int height) { return "permit released"; }
            public void close() {}
        });
        require(afterFatal.recognize(new byte[4], 1, 1).get(2, TimeUnit.SECONDS).equals("permit released"),
            "fatal cleanup releases the process-wide engine permit");
        afterFatal.close().get(2, TimeUnit.SECONDS);
        AtomicInteger recoveries = new AtomicInteger();
        OcrWorker recoverable = new OcrWorker(() -> new OcrWorker.Engine() {
            public String recognize(byte[] bgra, int width, int height) throws Exception {
                if (recoveries.incrementAndGet() == 1) throw new java.io.IOException("page read failure");
                return "page retry";
            }
            public void close() {}
        });
        require(recoverable.recognize(new byte[4], 1, 1).handle((value, error) -> error).get(2, TimeUnit.SECONDS) instanceof java.io.IOException,
            "ordinary page IO failure is reported unchanged");
        require(!recoverable.requiresRestart(), "safe IO cleanup allows another page");
        require(recoverable.recognize(new byte[4], 1, 1).get(2, TimeUnit.SECONDS).equals("page retry"), "ordinary page IO failure can retry");
        recoverable.close().get(2, TimeUnit.SECONDS);
        java.io.IOException operationFailure = new java.io.IOException("operation failed");
        java.io.IOException cleanupFailure = new java.io.IOException("cleanup failed");
        OcrWorker unsafeCleanup = new OcrWorker(() -> new OcrWorker.Engine() {
            public String recognize(byte[] bgra, int width, int height) throws Exception { throw operationFailure; }
            public void close() throws Exception { throw cleanupFailure; }
        });
        require(unsafeCleanup.recognize(new byte[4], 1, 1).handle((value, error) -> error).get(2, TimeUnit.SECONDS) == operationFailure,
            "cleanup keeps the original failure");
        require(operationFailure.getSuppressed().length == 1 && operationFailure.getSuppressed()[0] == cleanupFailure,
            "cleanup failure is not swallowed");
        require(unsafeCleanup.requiresRestart(), "unsafe cleanup is not an ordinary retriable IO error");
        require(unsafeCleanup.recognize(new byte[4], 1, 1).isCompletedExceptionally(), "unsafe cleanup admits no later operation");
        require(unsafeCleanup.close().handle((value, error) -> error).get(2, TimeUnit.SECONDS) == operationFailure,
            "unsafe cleanup close settles with its failure");
        Error fatalCleanup = new UnsatisfiedLinkError("fatal cleanup");
        java.io.IOException ordinaryFailure = new java.io.IOException("ordinary failure before fatal cleanup");
        OcrWorker fatalDuringCleanup = new OcrWorker(() -> new OcrWorker.Engine() {
            public String recognize(byte[] bgra, int width, int height) throws Exception { throw ordinaryFailure; }
            public void close() { throw fatalCleanup; }
        });
        require(fatalDuringCleanup.recognize(new byte[4], 1, 1).handle((value, error) -> error).get(2, TimeUnit.SECONDS) == fatalCleanup,
            "fatal cleanup is not hidden behind an ordinary retriable operation exception");
        require(fatalCleanup.getSuppressed().length == 1 && fatalCleanup.getSuppressed()[0] == ordinaryFailure,
            "fatal cleanup retains the original operation failure");
        require(fatalDuringCleanup.close().handle((value, error) -> error).get(2, TimeUnit.SECONDS) == fatalCleanup,
            "fatal cleanup close settles without replacing the Error");
        require(fatalDuringCleanup.recognize(new byte[4], 1, 1).isCompletedExceptionally(), "fatal cleanup rejects further work");
        OcrWorker finalPermit = new OcrWorker(() -> new OcrWorker.Engine() {
            public String recognize(byte[] bgra, int width, int height) { return "all permits released"; }
            public void close() {}
        });
        require(finalPermit.recognize(new byte[4], 1, 1).get(2, TimeUnit.SECONDS).equals("all permits released"),
            "ordinary and fatal cleanup failures both release the global engine permit");
        finalPermit.close().get(2, TimeUnit.SECONDS);
        System.out.println("PASS: bounded admission, process-wide permit cleanup, draining close, fatal init/operation/close settlement, preserved invariant Errors, unsafe-worker rejection, and safe IOException retry");
    }
}
