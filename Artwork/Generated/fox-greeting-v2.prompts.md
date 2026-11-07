# Fox greeting v2 generation

Built-in `image_gen.imagegen` was used on 2026-11-08. No API/CLI fallback was used.
Reference images are the original Android `snowfox_baby_sitting.png` and `snowfox_baby_happy2.png` preserved in the watch's `Assets.xcassets/StepMate` catalog.

## Initial prompt

Use case: identity-preserve. Asset type: production 12-frame transparent sprite atlas for a watch pet greeting animation. Reference image 1 is the exact white baby arctic fox identity and neutral sitting pose to preserve. Reference image 2 shows only the intended raised-paw greeting gesture; do not adopt its changed body proportions or wink. Create ONE SQUARE PNG atlas, exactly 4 columns by 3 rows, 12 equal rectangular cells, read left to right then top to bottom. Each cell contains the SAME complete front-facing seated white fox, same scale, same camera, same face, identical blue-black eyes, pink inner ears, soft white/lavender fur shading, identical feet baseline, center, head size and tail placement. Transparent alpha everywhere outside the fox; no background, no ground shadow, no checkerboard, no labels, no borders, no motion lines. The body and head stay completely still across frames; ONLY the paw on the viewer's left gently raises and waves. Sequence: 1 neutral sitting with paw down; 2 paw slightly lifting; 3 paw halfway up; 4 paw at cheek level; 5 paw tilts outward slightly; 6 paw tilts further outward; 7 paw tilts inward; 8 paw tilts further inward; 9 paw returns upright; 10 paw halfway lowering; 11 paw nearly down; 12 neutral sitting identical to frame 1. These must be small consecutive in-between movements forming one smooth greeting, not 12 different poses. Keep both eyes open and the gentle smile identical in every frame. Leave a safe transparent inset of at least 5 percent in every cell. Keep every full fox inside its own cell, including raised paw and ears. Production sprite sheet, not a contact sheet illustration or comic. No text or extra objects.

## Transparency refinement prompt

Use case: background-extraction. Edit target: image 1 is a finished 12-frame fox animation sprite atlas. FIX ONLY THE TRANSPARENCY. Remove every speckled white/gray/black patch in the background and gutters. All space outside the 12 fox silhouettes must be fully clear alpha=0, including the outer border and between cells. No checkerboard or solid background. Preserve every fox, their outlines, exact frame poses, colors, identical body scale, alignment and original 4-column by 3-row layout. Keep the same square canvas. Do not add any marks, shadows, borders or text. The result is a clean transparent PNG atlas ready to overlay on a dark blue game background.

## Selected output and packing

The refinement output is saved as `fox-greeting-v2-source.png`. It retained alpha noise in the gutters, so it is a source artifact, not the texture used directly by either app. `Scripts/prepareGreetingAnimation.swift` separates the 4×3 cells, retains each fox silhouette, aligns eye positions at a common scale, and packs 256×336 transparent frames. The first frame is reused as the final frame to make the return to idle exact.

The resulting 12 frames are stored in both apps' `Assets.xcassets/GreetingV2`. `fox-greeting-v2.gif` is a looping preview on a dark matte with a short idle pause. The apps use the transparent frames at 100ms per frame for a single 1.2s reaction. These generated frames are distinct from the byte-identical Android originals in `AndroidMediaManifest.json`.
