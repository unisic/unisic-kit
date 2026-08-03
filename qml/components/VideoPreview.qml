import QtQuick
import QtMultimedia
import Unisic.Kit

// QtMultimedia video surface for the trim editor. Kept in its own file so the
// `import QtMultimedia` is only ever evaluated when the consumer enables video
// playback and a Loader instantiates it — on a box without qt6-qtmultimedia the trim
// window falls back to the slider-only UI instead of erroring on the import.
Item {
    id: root

    // File to preview. player.source is NOT bound to this directly: when the
    // editor is idle in the background we blank the source to release the whole
    // decode pipeline (~150 MB of demuxer/decoder/frame buffers), then reload.
    property url fileUrl
    property bool suspended: false
    property real _resumePos: 0   // ms, restored after a suspend→resume reload

    // Live preview of per-track audio edits: one linear gain per audio track
    // of the file, index-aligned (-1 = muted), mixTrack naming the recording's
    // own ready-made first-track mix. The main player's audio (that mix) is
    // muted and one auxiliary AUDIO-ONLY player per remaining track voices it
    // at its gain - the same "rebuild the mix from the stems" the saved file
    // gets, heard live. Stems at 1.0 sum to exactly what the mix carries, so
    // with a known mix the aux players run from the moment the window opens:
    // an edit is then only an AudioOutput.volume change, with no pipeline
    // spawn (and its load gap) in the middle of playback. Without a known mix
    // (a foreign file) the default sound is the FIRST track alone, not the sum
    // - there the aux players appear only once an edit makes them necessary.
    // Empty gains (the default) keep the single-player behaviour.
    property var trackGains: []
    property int mixTrack: -1
    readonly property bool _editsActive: {
        for (let i = 0; i < trackGains.length; ++i) {
            if (i === mixTrack)
                continue
            const g = trackGains[i]
            if (g !== undefined && (g < 0 || Math.abs(g - 1) > 0.001))
                return true
        }
        return false
    }
    readonly property var _voicedTracks: {
        if (trackGains.length === 0 || (mixTrack < 0 && !_editsActive))
            return []
        const out = []
        for (let i = 0; i < trackGains.length; ++i)
            if (i !== mixTrack)
                out.push(i)
        return out
    }
    function _eachAux(fn) {
        for (let i = 0; i < auxPlayers.count; ++i) {
            const p = auxPlayers.objectAt(i)
            if (p)
                fn(p)
        }
    }

    readonly property real position: player.position        // ms
    readonly property real duration: player.duration         // ms
    readonly property bool playing: player.playbackState === MediaPlayer.PlayingState
    readonly property bool ready: player.mediaStatus === MediaPlayer.LoadedMedia
                                  || player.mediaStatus === MediaPlayer.BufferedMedia
                                  || player.mediaStatus === MediaPlayer.EndOfMedia

    function play() { player.play(); _eachAux(function(p) { p.play() }) }
    function pause() { player.pause(); _eachAux(function(p) { p.pause() }) }
    function togglePlay() { playing ? pause() : play() }
    // ms, clamped; pausing on manual seek keeps the frame steady while scrubbing.
    function seek(ms) {
        const v = Math.max(0, Math.min(ms, player.duration))
        player.setPosition(v)
        _eachAux(function(p) { p.setPosition(v) })
    }

    // Tear the decode pipeline down while the editor sits unused in the
    // background; remember where we were so resume() lands on the same frame.
    function suspend() {
        if (suspended)
            return
        _resumePos = player.position
        suspended = true   // → source binding blanks → media unloads
    }
    function resume() {
        if (!suspended)
            return
        suspended = false  // → source reloads; onMediaStatusChanged re-seeks
    }

    MediaPlayer {
        id: player
        source: root.suspended ? "" : root.fileUrl
        videoOutput: vout
        // Muted while stems are voiced: this player's default track is the mix
        // the stems are replacing, and both at once would double the audio.
        audioOutput: AudioOutput { id: aout; muted: root._voicedTracks.length > 0 }
        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.LoadedMedia && root._resumePos > 0) {
                setPosition(root._resumePos)
                root._resumePos = 0
            }
        }
        // The aux players run their own clocks; a coarse correction on the main
        // clock's ~10 Hz position ticks keeps them inside one video frame-ish
        // without the constant micro-seeks that would audibly stutter.
        onPositionChanged: {
            if (root.playing)
                root._eachAux(function(p) {
                    if (Math.abs(p.position - player.position) > 200)
                        p.setPosition(player.position)
                })
        }
    }

    Instantiator {
        id: auxPlayers
        model: root._voicedTracks
        delegate: MediaPlayer {
            source: root.suspended ? "" : root.fileUrl
            audioOutput: AudioOutput {
                // -1 (muted track) plays at 0 so toggling it back is instant;
                // the volume slider tops at 200% but AudioOutput caps at 1.0,
                // so a boost previews at full volume and only the saved file
                // gets the true gain. The short ramp turns a mute toggle and
                // slider steps into a fade instead of a zipper click.
                volume: {
                    const g = root.trackGains[modelData]
                    return Math.max(0, Math.min(1, g === undefined ? 1 : g))
                }
                Behavior on volume { NumberAnimation { duration: 90 } }
            }
            onMediaStatusChanged: {
                if (mediaStatus === MediaPlayer.LoadedMedia) {
                    activeAudioTrack = modelData
                    setPosition(player.position)
                    if (root.playing)
                        play()
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.mediaBase
        radius: Theme.radiusM
        clip: true
        VideoOutput {
            id: vout
            anchors.fill: parent
            fillMode: VideoOutput.PreserveAspectFit
        }
        // Big centered play/pause hit target over the frame.
        MouseArea {
            anchors.fill: parent
            onClicked: root.togglePlay()

            // Named and pressable through AT-SPI, but deliberately NOT a tab
            // stop and NOT bound to Space: the trim window owns Space as
            // play/pause at window level, and a focusable surface here would
            // steal it. The transport buttons below the frame are the keyboard
            // path.
            Accessible.role: Accessible.Button
            Accessible.name: root.playing ? qsTr("Pause") : qsTr("Play")
            Accessible.onPressAction: root.togglePlay()
        }
    }
}
