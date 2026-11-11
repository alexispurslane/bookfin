package dev.bookfin.bench.epub;

import android.graphics.Bitmap;

public final class KoBridge {
    static {
        System.loadLibrary("luajit");
        System.loadLibrary("koreader-monolibtic");
        System.loadLibrary("epub-bench");
    }

    public static native String evaluate(String program);
    public static native void copyPixels(Bitmap bitmap);
}
