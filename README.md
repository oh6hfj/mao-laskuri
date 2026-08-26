# Mao Laskuri

A browser game that begins by pretending to be someone else's homepage.

**Play it:** https://oh6hfj.github.io/mao-laskuri/

---

## What it is

It opens as a Finnish ballistics page — a minute-of-angle conversion table for
rifle shooters, complete with a moose target. Click anywhere and ten seconds
later the transmission is taken over: the heading trades an **O** for an **A**,
the picture tears, the signal collapses into static, and you are somewhere else
entirely with a ping-pong bat in your hand.

The whole joke is that pun. **MOA → MAO.**

Then it is whack-a-Mao. Smack them as they rise from behind the rocks; the game
counts hits, accuracy and reaction time in milliseconds. Three that get away and
it is over, and your score is entered on the Wall of Shame among the dictators
of all time.

**Do not hit the panda.** Pandas are endangered. Hitting one halves your score,
and the panda has something to say about it.

## How to run it

Open `index.html`. That is all — no server, no build step, no dependencies.

Everything is inlined into that single file as data URIs: the background image,
the music, both sound effects, and the webfont subsets. It makes **zero external
requests**, so it works from a USB stick, from an email attachment, or offline on
a plane.

## Layout

| | |
|---|---|
| `index.html` | The game. Self-contained, ~4.3 MB. |
| `aloituskuva.JPG` | The screenshot of the real page that gets hijacked. |
| `Little Itch-Scratching Mountain Song.mp3` | Background music. |
| `ping.mp3` | Bat impact. |
| `panda.mp3` | The panda's reprisal. |
| `inline-music.ps1` | Re-inlines the audio into `index.html`. |
| `inline-fonts.ps1` | Re-inlines the webfont subsets. |

`index.html` is generated but committed on purpose — it is the deliverable, and
GitHub Pages serves it directly.

### Swapping an asset

Drop a replacement in the folder and re-run the build:

```powershell
./inline-music.ps1        # picks up the music, ping.* and panda.*
./inline-fonts.ps1        # only needed if the typefaces change
```

`inline-music.ps1` refuses anything that would push the file past the size a
browser is happy to parse, and warns well before that.

## Under the hood

No engine, no framework, no bundler. One HTML file with a `<canvas>`.

- The **landscape** is generated at runtime — layered ridges, drifting mist,
  pines, the whole ink-wash scene is drawn from a seeded PRNG, so it is crisp at
  any resolution instead of being a fixed-size image.
- **Mao and the panda** are hand-plotted vector cartoons, drawn with canvas
  paths rather than sprites, so they scale cleanly and can squash and spin.
- The **signal loss** is a real analogue-television pastiche: noise generated
  per frame at reduced resolution and upscaled with nearest-neighbour sampling,
  plus torn scan bands, a rolling bright bar and chroma bleed.
- **Sound effects** are decoded once into `AudioBuffer`s so hits can overlap
  during a combo, with the leading silence of each sample measured and trimmed —
  `ping.mp3` had 89 ms of it, which read as input lag before it was skipped.
- Nothing plays until you click, because browsers require a gesture before any
  audio. The opening page is silent by design, so that click does double duty.

## Credits

The hijacked page is the real MOA Laskuri from
[kase.fi/~artola](https://kase.fi/~artola/trapsivut/MoaLaskuri/moa) — the pun was
sitting there waiting.

Music generated with [Suno](https://suno.com). Bat and panda sounds from free
sound libraries.

The panda's line is a nod to the Egyptian *Panda Cheese* commercials, in which a
panda calmly destroys your kitchen when you decline the cheese. Never say no to
Panda.

## A note on the Wall of Shame

The high-score table lists historical dictators with invented scores. The scores
are fiction; the reputations are not. It is satire, and the figures on it are
long dead.
