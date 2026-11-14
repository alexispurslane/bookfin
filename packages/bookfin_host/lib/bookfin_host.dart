/// Bookfin's Android host channels (`bookfin/media`, `bookfin/media-network`,
/// `bookfin/speech`, `bookfin/device`, `bookfin/power` and `bookfin/ocr`).
/// The Dart side of each channel lives in the app. This package has no Dart
/// API: it exists so that Flutter's generated plugin registrant adds the
/// channels to every engine, including one that the audio service starts
/// before any Activity (t0-wedg).
library;
