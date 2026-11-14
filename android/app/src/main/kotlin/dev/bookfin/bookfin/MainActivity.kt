package dev.bookfin.bookfin

import com.ryanheise.audioservice.AudioServiceActivity

// The Activity owns no channel and no listener. Under audio_service one
// cached Flutter engine outlives each Activity, and the audio service can
// make that engine before any Activity, for a media button or the system's
// resume player. So every channel belongs to the bookfin_host plugin
// (packages/bookfin_host), which Flutter's generated registrant adds to each
// engine (t0-wedg). Add a new channel there, never here.
class MainActivity : AudioServiceActivity()
