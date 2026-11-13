// A real, controllable FFI block. Native entry and exit are observable even
// after Dart abandons the isolate, so teardown never guesses with a delay.
#include <pthread.h>

static pthread_mutex_t mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t changed = PTHREAD_COND_INITIALIZER;
static int entered;
static int finished;
static int released;

int hang(void) {
  pthread_mutex_lock(&mutex);
  entered++;
  while (!released) pthread_cond_wait(&changed, &mutex);
  finished++;
  pthread_mutex_unlock(&mutex);
  return 99;
}

int entries(void) {
  pthread_mutex_lock(&mutex);
  int result = entered;
  pthread_mutex_unlock(&mutex);
  return result;
}

int exits(void) {
  pthread_mutex_lock(&mutex);
  int result = finished;
  pthread_mutex_unlock(&mutex);
  return result;
}

void release(void) {
  pthread_mutex_lock(&mutex);
  released = 1;
  pthread_cond_broadcast(&changed);
  pthread_mutex_unlock(&mutex);
}
