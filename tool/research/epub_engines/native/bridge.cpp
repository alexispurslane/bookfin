#include <jni.h>
#include <android/bitmap.h>
#include <cstring>
#include <string>

struct lua_State;
extern "C" {
lua_State* luaL_newstate();
void luaL_openlibs(lua_State* state);
int luaL_loadstring(lua_State* state, const char* code);
int lua_pcall(lua_State* state, int arguments, int results, int error);
const char* lua_tolstring(lua_State* state, int index, size_t* length);
void lua_settop(lua_State* state, int index);
void lua_getfield(lua_State* state, int index, const char* name);
int luaopen_cre(lua_State* state);
}

static lua_State* runtime = nullptr;

extern "C" JNIEXPORT jstring JNICALL
Java_dev_bookfin_bench_epub_KoBridge_evaluate(JNIEnv* environment, jclass, jstring program) {
    if (!runtime) {
        runtime = luaL_newstate();
        if (!runtime) {
            environment->ThrowNew(environment->FindClass("java/lang/IllegalStateException"), "LuaJIT state allocation failed");
            return nullptr;
        }
        luaL_openlibs(runtime);
        luaopen_cre(runtime);
        lua_settop(runtime, 0);
    }
    const char* code = environment->GetStringUTFChars(program, nullptr);
    int status = luaL_loadstring(runtime, code);
    environment->ReleaseStringUTFChars(program, code);
    if (!status) status = lua_pcall(runtime, 0, 1, 0);
    const char* output = lua_tolstring(runtime, -1, nullptr);
    std::string value = output ? output : "";
    lua_settop(runtime, 0);
    if (status) {
        environment->ThrowNew(environment->FindClass("java/lang/IllegalStateException"), value.c_str());
        return nullptr;
    }
    return environment->NewStringUTF(value.c_str());
}

extern "C" JNIEXPORT void JNICALL
Java_dev_bookfin_bench_epub_KoBridge_copyPixels(JNIEnv* environment, jclass, jobject bitmap) {
    AndroidBitmapInfo info;
    if (!runtime || AndroidBitmap_getInfo(environment, bitmap, &info) != ANDROID_BITMAP_RESULT_SUCCESS) {
        environment->ThrowNew(environment->FindClass("java/lang/IllegalStateException"), "No KOReader render buffer");
        return;
    }
    lua_getfield(runtime, -10002, "pixels");
    size_t length = 0;
    const char* pixels = lua_tolstring(runtime, -1, &length);
    if (!pixels || info.format != ANDROID_BITMAP_FORMAT_RGBA_8888 || length != size_t(info.width)*info.height*4) {
        lua_settop(runtime, 0);
        environment->ThrowNew(environment->FindClass("java/lang/IllegalStateException"), "KOReader buffer size or format mismatch");
        return;
    }
    void* target = nullptr;
    if (AndroidBitmap_lockPixels(environment, bitmap, &target) != ANDROID_BITMAP_RESULT_SUCCESS) {
        lua_settop(runtime, 0);
        environment->ThrowNew(environment->FindClass("java/lang/IllegalStateException"), "Could not lock Android bitmap");
        return;
    }
    for (size_t row = 0; row < info.height; ++row) {
        std::memcpy(static_cast<char*>(target) + row*info.stride, pixels + row*info.width*4, info.width*4);
    }
    AndroidBitmap_unlockPixels(environment, bitmap);
    lua_settop(runtime, 0);
}
