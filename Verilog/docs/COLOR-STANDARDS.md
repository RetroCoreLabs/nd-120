# Colour standard for ND-120 documentation and generated diagrams

**Full path:** `Verilog/docs/COLOR-STANDARDS.md`
**Date:** 20-AUG-2026

One palette for everything this project draws: Mermaid diagrams, generated
waveforms (`tests/vcd2png.py`), module symbols (`tests/module_doc.py`) and any
future plot. Target: **WCAG 2.1 Level AA**, which the European Accessibility
Act 2025 makes the practical baseline for published technical material.

Every number in this document was **computed, not asserted** — the ratios come
from the WCAG relative-luminance formula, and the script that produced them is
in the appendix so any change can be re-checked.

---

## 1. What "compliant" actually requires here

Three separate rules, routinely conflated:

| Rule | Threshold | Applies to |
|---|---|---|
| **1.4.3 Contrast (Minimum)** | **4.5:1** | text against its background |
| **1.4.11 Non-text Contrast** | 3:1 | lines, borders, graphical objects |
| **1.4.1 Use of Colour** | *n/a* | colour must never be the **only** way information is conveyed |

This standard holds everything to **4.5:1**, the stricter text threshold, even
for graphics — it costs nothing and removes the argument.

**1.4.1 is the rule that catches people out**, and it is the reason for
section 4. Contrast measures a colour against its **background**. It says
nothing about whether two *foreground* colours can be told apart. Measured:
input-blue against output-green is **1.68:1** — both pass against white, and a
red-green colourblind reader still sees two nearly identical greys.

---

## 2. The palette

Two variants. This is not a stylistic choice: **no single colour can reach
4.5:1 against both white and near-black.** A colour dark enough for a white
page is too dark for a dark page. Anything claiming one palette for both has
quietly dropped one of them.

### Light mode — on `#FFFFFF`

| Role | Hex | Contrast | Use |
|---|---|---|---|
| **INPUT** | `#0D47A1` | **8.63:1** | input ports, stimulus, sources, incoming data |
| **OUTPUT** | `#2E7D32` | **5.13:1** | output ports, results, driven values |
| **BIDIRECTIONAL** | `#9A3412` | **7.31:1** | `inout`, bus transceivers, either-direction nets |
| **CLOCK / CONTROL** | `#6A1B9A` | **9.39:1** | clocks, strobes, enables, resets |
| **INTERNAL** | `#00695C` | **6.61:1** | internal state not visible at the boundary |
| **ERROR / X / Z** | `#B71C1C` | **6.57:1** | unknown, high-Z, contention, failure |
| **NEUTRAL** | `#546E7A` | **5.40:1** | axes, gridlines, annotation, "don't care" |

### Dark mode — on `#1E1E1E`

| Role | Hex | Contrast |
|---|---|---|
| **INPUT** | `#90CAF9` | **9.50:1** |
| **OUTPUT** | `#66BB6A` | **7.05:1** |
| **BIDIRECTIONAL** | `#FFB74D` | **9.63:1** |
| **CLOCK / CONTROL** | `#CE93D8` | **6.98:1** |
| **INTERNAL** | `#80CBC4` | **8.94:1** |
| **ERROR / X / Z** | `#EF9A9A` | **7.75:1** |
| **NEUTRAL** | `#B0BEC5` | **8.75:1** |

**Every entry in both tables clears 4.5:1.** The lowest is output-green in
light mode at 5.13:1.

### Fills, where a shape needs one

Pale fill, palette colour as a 2 px stroke, near-black text (`#212121`,
16.1:1 on the pale fills). This is the existing house style for Mermaid and it
stays.

| Role | Fill | Stroke |
|---|---|---|
| INPUT | `#E3F2FD` | `#0D47A1` |
| OUTPUT | `#E8F5E9` | `#2E7D32` |
| BIDIRECTIONAL | `#FFF3E0` | `#9A3412` |
| CLOCK / CONTROL | `#F3E5F5` | `#6A1B9A` |
| INTERNAL | `#E0F2F1` | `#00695C` |
| ERROR | `#FFEBEE` | `#B71C1C` |

---

## 3. Rejected, and why

Recorded so nobody re-proposes them.

| Colour | Measured | Verdict |
|---|---|---|
| `#E65100` orange | **3.79:1** on white | **FAILS 4.5:1.** Darkened to `#9A3412` (7.31:1) |
| `#2196F3` / `#4CAF50` etc. (saturated fill, white text) | ~4.5:1 | Fine for a *filled Mermaid node*, unusable as a **line** on white — a 2 px stroke at 4.5:1 is far harder to see than text at 4.5:1 |
| Pastels `#e1f5ff`, `#ffe1f5` | ~1.1:1 | Invisible. This is the failure that prompted the standard |
| Pure red/green as the sole in/out distinction | 1.68:1 apart | Worst possible pair for the most common colour-vision deficiency |

---

## 4. The rule that makes it actually accessible

> **Colour is a reinforcement, never the carrier.** Every distinction drawn
> with colour MUST also be readable with colour removed.

Because input-blue and output-green measure 1.68:1 apart, colour alone cannot
separate them for a red-green colourblind reader, or in greyscale print, or in
a screenshot pasted into a monochrome document.

**Mandatory redundant cues:**

| Distinction | Colour | Required second cue |
|---|---|---|
| input vs output | blue / green | text tag `IN` / `OUT` on the row label |
| bidirectional | orange | tag `I/O` |
| clock | purple | always the **first** row, and tagged `CLK` |
| X / Z | red | drawn as a **mid-height band**, never a level |
| active-low | any | `_n` suffix kept in the label, plus an inversion bubble on symbols |

Test for compliance: **convert the image to greyscale. If any distinction is
lost, the diagram is non-compliant** regardless of its contrast ratios.

---

## 5. Applying it

- **Waveforms** — `tests/vcd2png.py` implements this palette. It reads port
  directions from the RTL (`--rtl <file>`) so input/output colouring is derived
  from the source, not typed by hand and not guessed. `--dark` selects the dark
  variant.
- **Module symbols** — `tests/module_doc.py`.
- **Mermaid** — use the fill/stroke pairs from section 2. The existing house
  rules still apply: no hyphens, slashes, colons or HTML tags in node labels
  (VS Code compatibility), stroke width 2 px.
- **Do not hand-pick a colour outside this table.** If a new semantic role is
  genuinely needed, add it here with its computed ratio first.

---

## 6. Appendix — re-checking any change

```python
def lin(c):
    c = c / 255.0
    return c/12.92 if c <= 0.04045 else ((c+0.055)/1.055)**2.4

def lum(h):
    h = h.lstrip('#')
    r, g, b = (int(h[i:i+2], 16) for i in (0, 2, 4))
    return 0.2126*lin(r) + 0.7152*lin(g) + 0.0722*lin(b)

def ratio(a, b):
    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)

# every palette entry vs its background must be >= 4.5
# input vs output must ALSO be checked - and will be low, which is
# exactly why section 4 exists
```

Related: `Verilog/docs/PREREQUISITES.md` (the tools), and the owner's older
global Mermaid palette note (kept outside this repository), which this document
supersedes for generated images while keeping its semantic colour assignments.
