import dev.bookfin.bookfin.ocr.OcrWorker;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

public final class OcrWorkerTest {
    static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
    public static void main(String[] arguments) throws Exception {
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
        System.out.println("PASS: production worker bounds admission, prevents parallel engine owners, rejects closing work, drains, releases exactly once, and retries initialization failure");
    }
}
