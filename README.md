# GRAIN — Geodynamics Research Analogue Information Network

[![DOI](https://zenodo.org/badge/DOI/XX.XXXX/zenodo.XXXXXXX.svg)](https://doi.org/XX.XXXX/zenodo.XXXXXXX)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![MATLAB R2025b](https://img.shields.io/badge/MATLAB-R2025b-orange.svg)](https://www.mathworks.com/)

GRAIN is a MATLAB toolset for turning **analogue (sandbox) tectonic experiments**
into quantitative, reproducible kinematic data. It wraps
[PIVlab](https://github.com/Shrediquette/PIVlab) in a batch pipeline that takes a
folder of time-lapse photographs and carries it all the way to fault-by-fault
measurements: velocity magnitude and shear-strain fields, plot-over-time (POT)
curves, hanging-wall / footwall velocities, net slip, fault geometry, and a
frame-by-frame description table ready for a manuscript.

Every entry point is named `GRAIN*` — `GRAIN0` through `GRAIN5` for the pipeline
steps, plus the standalone tools listed below. The project grew up under the
working name **PAB** (*PIVlab Automasi Batch*); thin `PAB*` aliases are kept so
older scripts still run, and file names written by earlier versions (progress
files, `PAB4_DESC/`, export folders) are deliberately left untouched so existing
data stays readable.

> **Scope of this release.** Source code and documentation only. The photographic
> data, PIV result files (`.mat`) and exported figures from our own experiments are
> **not** included — they are large and are archived separately.

---

## Why it exists

A sandbox run produces hundreds of photographs. Raw PIVlab output is per-frame and
per-pixel; a structural geologist needs per-**fault**, per-**stage** numbers. The
gap between those two is normally bridged by hand, one experiment at a time, and
that is where reproducibility is lost.

GRAIN closes the gap with three ideas:

1. **One experiment = one file.** Photographs are packed into a single self-contained
   `.mat` (images + EXIF timing + stabilisation + masking recipe), so an experiment
   can be moved, archived or re-analysed without dragging thousands of loose files.
2. **Non-destructive corrections.** Frame exclusion, jitter stabilisation and area
   masking are stored as *recipes* alongside the original data, never baked into it.
3. **Every measurement is replayable.** Fault picks, points of interest and
   descriptions live in JSON sidecars next to the data, so a figure in a paper can
   be traced back to the click that produced it.

---

## Requirements

| Requirement | Notes |
|---|---|
| MATLAB **R2025b** | The suite is developed and tested only on R2025b. R2026a is known to hang under `-batch` and to misbehave when picking an ROI at startup. |
| [PIVlab](https://github.com/Shrediquette/PIVlab) | The PIV engine itself. Install it as a MATLAB Add-On; GRAIN calls `piv_FFTmulti`, `PIVlab_preproc` and `PIVlab_postproc`. **Not bundled here.** |
| Image Processing Toolbox | Image handling, masking, CLAHE preprocessing. |
| Computer Vision Toolbox | SURF-based jitter stabilisation (a phase-correlation fallback exists). |
| Parallel Computing Toolbox | Optional. Used to parallelise jitter sweeps and batch production; the code falls back to serial execution when it is absent. |

---

## Quick start

```matlab
cd /path/to/GRAIN
grain_setup          % once per MATLAB session — sets up the path
GRAIN0               % Step 0: pick a ROOT folder of experiments
```

`grain_setup` resolves every path relative to its own location, so the folder can be
renamed or moved freely. It also picks up PIVlab automatically if it is on the
MATLAB path.

---

## The pipeline

```
photographs (JPEG)
      │
   GRAIN0     Step 0 · Quick-PIV screening — drop dead frames (machine stopped)
      │              and flag irregular shutter intervals from EXIF
   GRAINMASK  Area masking on the raw photographs (non-destructive recipe)
      │
   GRAIN1     Step 1 · Jitter/anchor ROI per experiment → produces MAT PREP
      │              (one packed .mat per experiment)
   GRAIN2     Step 2 · Full PIV production → MAT PIV
      │
   GRAIN3     Step 3 · Read-only preview, montage
   GRAIN3a    Step 3a · Assign POT curves to hanging wall / footwall / faults
      │
   GRAIN4     Step 4 · Integrated workstation: labelling, net slip, fault geometry,
      │              fault-plane evolution, description table, exports
   GRAIN5     Fault-first view: one table of faults per PSG line, batch export
```

### Standalone tools

| Tool | Purpose |
|---|---|
| `GRAINMASK` / `GRAINMASK2` | Rectangle and keyframed-polygon masking |
| `GRAINEXPORT` | WYSIWYG catalogue of per-frame velocity-magnitude / shear images |
| `GRAINEDIT` | WYSIWYG editor producing a single publication figure |
| `GRAINAXPOT`, `GRAIN4AXPOT` | Plot-over-time figure editors (graph-paper style) |
| `GRAINAXCAL` | Two-point pixel↔centimetre axis calibration |
| `GRAINLINK` / `GRAINSYNC` | Tie cross-section strain to the map view via fault-scarp reference points |
| `MATPIVEDIT` | QC editor for produced MAT PIV files |
| `GRAINIMAGEDT` | Inter-photo interval (Δt) diagnostics from EXIF |
| `SHEARSTRAINDetector` | Semi-automatic digitisation of shear-strain ridges |

Further documentation, including a visual walkthrough of the workflow, is in
[`docs/`](docs) — start with [`docs/ALUR_KERJA_V2_standalone.html`](docs/ALUR_KERJA_V2_standalone.html)
and [`docs/GLOBAL_CONTEXT.md`](docs/GLOBAL_CONTEXT.md).

---

## Tests

Smoke and regression tests live in [`tests/`](tests) and run headless:

```matlab
grain_setup
set(0,'DefaultFigureVisible','off')   % keep the tests silent
run_parsecheck                        % every file parses
run_all_smoke                         % smoke suite
```

---

## A note on language

The suite was written in Indonesian and its user interface is being migrated to
English module by module. `GRAIN0` and `GRAIN1` are already in English; the remaining
modules still show Indonesian labels. Code comments remain in Indonesian for now.
The translation glossary and per-stage status are tracked in
[`docs/GLOSSARY_ID_EN.md`](docs/GLOSSARY_ID_EN.md).

---

## Citing GRAIN

If GRAIN contributes to work you publish, please cite the archived release — see
[`CITATION.cff`](CITATION.cff), or use the DOI badge at the top of this page.
Please also cite PIVlab itself, since it provides the PIV engine:

> Thielicke, W., & Sonntag, R. (2021). Particle Image Velocimetry for MATLAB:
> Accuracy and enhanced algorithms in PIVlab. *Journal of Open Research Software*,
> 9(1), 12. https://doi.org/10.5334/jors.334

---

## License

GRAIN is released under the **GNU General Public License v3.0 or later**
(see [`LICENSE`](LICENSE)). GPL was chosen because GRAIN builds directly on
PIVlab, which is itself GPL-licensed.
