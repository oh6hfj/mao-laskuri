# Building a one-file browser game — what was learned here

Notes from building **Mao Laskuri** and **Looking for the Mao**, written so the
next game of this kind can start from the answers instead of rediscovering them.

Most of the value below is in **The traps**. The features were the easy part.

---

## 1. The shape of the thing

One `index.html`. No engine, no framework, no bundler, no build step to *run* it
— only to assemble it. Every asset is inlined as a `data:` URI: images, music,
sound effects, even the webfont subsets. The finished file makes **zero external
requests**.

That single decision pays for itself repeatedly:

- Opens from a USB stick, an email attachment or a phone's Downloads folder
- Works offline and on a plane
- Deploys to GitHub Pages by copying one file
- Publishes as a Claude Artifact unchanged
- Nothing can half-load or 404

**The cost is size.** Base64 inflates binary by ~33%, and browsers must parse
the whole file before anything renders. Budget:

| | |
|---|---|
| Artifact hard ceiling | 16 MB rendered |
| Comfortable | under ~4 MB |
| Noticeably slow on mobile data | above ~6 MB |
| Music, realistically | 1–3 MB (96–128 kbps mono is plenty) |

A 5.5 MB track became a 7.4 MB page and was visibly slow on a phone. Re-encoded
to 2.6 MB it was fine. **Encode audio down before inlining, not after.**

---

## 2. Assembly scripts

Rather than hand-editing base64 into HTML, the page declares empty slots:

```javascript
var MUSIC_SRC = "";
var PING_SRC  = "";
var PANDA_SRC = "";
```

…and a re-runnable script fills them from files in the folder, matched by name.
Drop `gong.mp3` in, run the script, done. Leave it out and the code falls back
to a synthesised version.

Three scripts ended up being the right split:

| Script | Does |
|---|---|
| `inline-music.ps1` | music tracks and every sound effect |
| `inline-fonts.ps1` | fetches Google Fonts CSS, picks the needed subsets, inlines them |
| `inline-image.ps1` | strips image metadata, then inlines |

**Make them idempotent.** Each finds `var X_SRC = "…";` by regex and replaces
whatever is there, so re-running is always safe. That property is what makes
asset iteration painless.

**Guard the auto-detect.** The music picker scans for audio files and takes the
newest — which happily inlined a sound effect as the soundtrack the moment one
was added. Reserved names (`ping`, `panda`, `gong`, `tingsha`, …) are excluded
explicitly.

### Font subsetting

CJK families are served by Google as **~100 unicode-range subsets**. Inlining
all of them adds megabytes. The script parses each `@font-face`, tests its
`unicode-range` against the characters the game actually renders, and keeps only
those. For Latin + a few accents + two CJK glyphs: **26 subsets, 402 KB.**

---

## 3. Audio — where nearly all the pain was

### `AudioContext.resume()` is asynchronous

The single most expensive bug in the project.

```javascript
// WRONG - state is still "suspended" on the next line
if (ctx.state === "suspended") ctx.resume();
return ctx.state === "running";        // always false the first time
```

Everything downstream branched on that `false`, so music never started and the
"tap for sound" button could never work — for weeks it looked like an autoplay
policy problem. Symptom: **sound effects work, music never does**, because
effects check the state at the moment they fire, by which point it has resumed.

Use a ready-gate instead:

```javascript
whenReady: function (cb) {
  if (this.running()) { cb(); return; }
  this.readyQueue.push(cb);
  this.unlock();            // resolves the promise AND listens to onstatechange
}
```

Anything wanting audio queues behind it, and intent is remembered rather than
dropped. Gesture listeners must **not** be `{once:true}` — a refused first
attempt needs a second chance.

### Browsers need a gesture, so design one in

No audio may start before a user gesture. Rather than fight it, make the first
interaction something the game wanted anyway — a Start button, or a click that
begins the intro. It does double duty and the restriction disappears.

Also: keep an explicit fallback affordance ("♪ Tap for sound") whose visibility
tracks the *real* context state, not a one-time check.

### Supplied samples beat synthesis, always

Considerable effort went into a synthesised score — Karplus-Strong plucked
strings, a modelled bamboo flute, procedural reverb, a phrased pentatonic
arrangement. The verdict was "awful rubbish", twice. It was replaced by a
generated MP3 in minutes and the difference was not close.

Keep synthesis for:
- Mechanical noise (the TV static was fine)
- Fallbacks when a file is absent

Not for anything that should sound played by a person.

**A latent bug worth knowing**: a Karplus-Strong loop diverges if the damping
filter's `Q` leaves it above unity gain. `Q` defaults to 1, whose resonant peak
is ~+1.25 dB — so the string grew instead of decaying. Measured output peak was
**1.3 × 10¹⁵**. Set `Q ≤ 0.5` and keep feedback under ~0.985.

### Trim the leading silence off samples

Recorded one-shots often carry room tone before the transient. `ping.mp3` had
**89 ms** of it — every bat hit landed 89 ms after the swing and read
unmistakably as input lag.

Measure the onset once at decode time and start playback there:

```javascript
findOnset: function (buf) {
  var d = buf.getChannelData(0);
  for (var i = 0; i < d.length; i++) {
    if (Math.abs(d[i]) > 0.02) return Math.max(0, i / buf.sampleRate - 0.002);
  }
  return 0;
}
```

Then `source.start(when, offset)`. Latency went from ~98 ms to 9 ms.

### Two different playback paths, on purpose

| | Use | Why |
|---|---|---|
| `AudioBuffer` + `BufferSourceNode` | short effects | overlap freely, start on the exact sample |
| `<audio>` + `MediaElementSource` | music | flat memory regardless of length |

An `<audio>` element cannot overlap itself, so rapid hits would cut each other
off. Conversely `decodeAudioData` on a 4-minute stereo track holds ~70 MB as
float32 — fine on a desktop, not on a phone.

### Crossfading two tracks

Give each track its own element **and its own gain**, both feeding one mixer,
with a master gain above them. Crossfade at the track gains; keep mute,
silencing and ducking on the master, so they apply to whichever is playing.

Watch for interference: a loop-seam softener that adjusted the track gain four
times a second fought the crossfade the whole way through. Only touch a gain
when actually near a seam.

### Decode base64 yourself

`fetch()` on a `data:` URI is refused in some browsers when the page itself came
from `file://` — exactly how someone opens a file you sent them. Use `atob` and
build the `ArrayBuffer` manually; it has no origin rules.

### Every event needs its own sound

Two separate versions of this mistake:

1. The frenzy reward and game over both played the gong — the same sound meaning
   "you are on fire" and "you are dead".
2. The replacement fanfare was six pings pitched 1.0–1.23, which is *exactly* the
   range an ordinary hit uses. It was audible and still unrecognisable, because
   it was made of the sound the game already makes constantly.

**A cue must differ from the ambient texture.** The fix was to accelerate it and
sweep 0.82 → 2.42, well outside the hit range, landing on a different sample.

---

## 4. Canvas art

Everything visual is drawn at runtime — landscape, characters, poster scenes.
No image files except one deliberate screenshot.

- **Seeded PRNG** (`mulberry32`) for anything "random" that must survive a
  resize. A landscape regenerated with fresh randomness on every resize is
  deeply unsettling.
- **Paint expensive backgrounds once** to an offscreen canvas at device
  resolution, then blit per frame.
- **Handle DPR**: set `canvas.width = cssWidth * dpr`, then
  `ctx.setTransform(dpr,0,0,dpr,0,0)` and draw in CSS pixels.
- **Even-odd fill** cuts holes in shapes. An arched bridge only reads as a
  bridge when the arch is a real opening with something bright behind it —
  drawing a deck and two piers and leaving a gap reads as scaffolding.
- **Silhouettes need ground.** Rocks drawn as shapes floating on a background
  look like slabs hovering in mid-air. A soft dark mound underneath fixes it
  more cheaply than any amount of shading.

### Painting elements sized by CSS

A canvas inside a CSS-sized container has **no dimensions at first paint**, so
painting on load silently does nothing. Timers are a guess. Use a
`ResizeObserver` on the container and paint whenever it actually has a size —
that covers first layout, resizes, webfonts arriving and orientation changes in
one mechanism.

---

## 5. The traps

Every one of these was a real bug here.

| Symptom | Cause |
|---|---|
| Music never plays, effects do | `ctx.resume()` is async; code branched on the state immediately after |
| Hits feel laggy | leading silence in the sample, not code latency |
| Game freezes forever, no error | a thrown frame killed the rAF loop — the next frame was scheduled *after* the work |
| Everything dies on a hidden tab | rAF is throttled when not compositing; anything gating progress on it stalls. Use timers for anything that must complete |
| A canvas draws nothing | container had no layout yet, or viewport reported 0×0 |
| Overlay invisible but blocking | fade-in triggered on rAF while the tab was hidden |
| Text vanishes on phones only | a `max-height` media query hiding content; desktop windows are taller |
| Start button unreachable | one tall column on a landscape phone. Two columns use the width that is there |
| Sound effect became the soundtrack | build script auto-detect took the newest audio file |
| Name leaks into a public repo | EXIF/XMP `dc:creator` in a screenshot, then base64'd invisibly into the HTML |

**On hiding content responsively**: if a layout does not fit, take the height out
of the *pictures*. Never the writing. Hiding text on small screens deletes it for
the majority of readers while leaving it intact for whoever wrote it.

---

## 6. Game design notes

What worked, worth keeping:

- **A decoy opening.** The first game pretends to be an unrelated real webpage
  for ten seconds before being hijacked. Nothing else got as strong a reaction.
- **A thing you must NOT hit.** The panda punishes careless swinging and makes
  every target a decision instead of a reflex. Give it a *long*, fixed on-screen
  time that never speeds up — the mistake must be a choice, not a reflex tax.
- **A skill shot.** Hitting an already-struck target in mid-air for 3× is the
  most-praised mechanic here. Make the window *tight*; the value is in it being
  hard.
- **Rewards must escalate visibly.** Points alone are abstract. A streak that
  earns a visible spare life, with its own sound, lands far harder.
- **Freeze the game for a penalty**, and when you do, compensate every absolute
  timestamp on resume — reaction times and difficulty clocks otherwise bill the
  frozen seconds to the player. Suppress input during the freeze too, or it
  becomes a window for accruing misses.
- **Persist a personal best.** A game that forgets you gives no reason to play
  twice. Guard every `localStorage` access — it throws in private windows.

---

## 7. Deployment

**GitHub Pages**: repo → Settings → Pages → Deploy from a branch → `main` /
`/ (root)`. `index.html` at the root serves at the bare URL. Free tier requires a
**public** repo.

**A link beats a file.** Sending HTML over WhatsApp mostly fails: iOS opens
attachments in a previewer that does not run JavaScript. A URL just opens.

**Sibling projects get sibling repos.** Two games in nested folders need the
parent to `.gitignore` the child, or git treats it as an unregistered submodule.

**Commit the generated `index.html`.** It is the deliverable and Pages serves it
directly — the usual "never commit build output" rule does not apply.

**Strip image metadata before publishing.** Redraw onto a fresh `Bitmap` and
re-encode; hand-parsing JPEG marker segments produced a 0-byte file on the first
attempt. Always verify the result still decodes before overwriting.

**Use a privacy commit email** (`user@users.noreply.github.com`) and set it
**per-repo, without `--global`**, so a personal project cannot inherit or
contaminate a work identity.

---

## 8. Windows / PowerShell notes

Specific to this environment, all encountered for real:

- **`&&` does not exist in Windows PowerShell 5.1.** Use `;`. It is a parser
  error, so the whole line fails before anything runs. (It *does* work in cmd.)
- **Variable names are case-insensitive.** `$html` and `$Html` are the same
  variable — reading a file into `$html` silently destroyed the `$Html` path.
- **Hash literal keys are case-insensitive too**: `@{ ".jpg"=…; ".JPG"=… }` is a
  duplicate-key parse error.
- **Do not pipe a native program's stderr** (`2>&1`). PowerShell wraps it as an
  error record and reports failure even on exit code 0 — `git push` looks like it
  failed when it succeeded. Check `$LASTEXITCODE`.
- `[Text.Encoding]::Latin1` does not exist in 5.1; use `GetEncoding(28591)`.
- Write files with `New-Object System.Text.UTF8Encoding($false)` to avoid a BOM.
- No `node`, `python` or `ffmpeg` was available here. A ~20-line
  `System.Net.HttpListener` script is a perfectly good static dev server.

---

## 9. If starting again

1. Decide the size budget first and encode audio to fit it.
2. Build the audio ready-gate before anything else needs sound.
3. Put every asset behind a named slot and write the inline script early.
4. Use `ResizeObserver` for anything canvas-drawn inside a CSS-sized box.
5. Schedule the next animation frame *before* doing the frame's work.
6. Give every game event its own distinguishable sound, and check they differ.
7. Test at 375×667 and in landscape early — not at the end.
8. Strip metadata from any image before it goes near a public repo.
