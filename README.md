# LizardMan's ReShade Effects

Custom shader effects for [ReShade](https://reshade.me/).

## Effects

- **modxdither.fx** (work in progress): a deliberately visible, retro-style stripe dither along X or Y, with optional gradient mapping.
- **supermoddither.fx**: a 1-bit modulation dither. Fine lines are bent by the image's brightness so they trace its contours, and grow thicker in bright areas, giving a green-phosphor terminal look.

## Install

Copy the `.fx` files into your game's `reshade-shaders\Shaders` folder, then enable them in the ReShade menu.
