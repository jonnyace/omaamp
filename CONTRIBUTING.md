# Contributing to OmaAmp

OmaAmp is a desktop presentation plugin on top of cliamp. Keep that boundary
visible in every change:

- cliamp owns audio decoding, playback, queue semantics, spectrum production,
  and terminal themes;
- OmaAmp owns the Quickshell player, Omarchy integration, skin compatibility,
  theme conversion, and controls exposed through MPRIS or cliamp's documented
  interfaces;
- do not add a second audio engine, private queue model, or decorative control
  for behavior cliamp cannot perform. Add the capability to cliamp first, then
  expose it here.

Skin archives are untrusted input. Decode or normalize them in the standalone
helper/player process, never inside the long-running omarchy-shell process.
Keep member and archive limits in every extraction path.

Run the regression suite before committing:

```bash
python3 -m unittest discover -s tools -v
```
