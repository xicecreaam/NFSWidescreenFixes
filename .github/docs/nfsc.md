<p align=center>This Widescreen Fix brings what ThirteenAG added initially (proper widescreen support, corrects HUD and FOV, fixes FMVs and shadows, and includes a range of quality-of-life improvements) but <strong>with the MoviePlaybackFix and DisableMotionblur features back-ported to the january 2022 commit</strong>.</p>

<p align=center><a href="https://github.com/xicecreaam/NFSWidescreenFixes/blob/master/source/NFSCarbon.WidescreenFix/dllmain.cpp">Source code</a> · <a href="https://github.com/xicecreaam/NFSWidescreenFixes/blob/master/data/NFSCarbon.WidescreenFix/scripts/NFSCarbon.WidescreenFix.ini">Default INI</a></p>

***

# Installation

1. Download the `.zip` from this release.
2. Extract the contents directly into the game folder - the same folder as `NFSC.exe`.
3. Optionally edit `NFSCarbon.WidescreenFix.ini` to configure the available options.
4. Launch the game.

***

# 16:9 and 4:3 INI configurations

## 16:9 (2560x1440 • 1920x1080 • 1600x900 • ...)

[MAIN]
ResX = <font color="#4a4a4a">2560, 1920, 1600, ...</font>
ResY = <font color="#4a4a4a">1440, 1080, 900, ...</font>
FixHUD = 1
FixFOV = 1
Scaling = 1
HUDWidescreenMode = 1
FMVWidescreenMode = 1

...

## 4:3 (1440x1080 • 1280x960 • 800x600 • ...)

[MAIN]
ResX = <font color="#4a4a4a">1440, 1280, 800, ...</font>
ResY = <font color="#4a4a4a">1080, 960, 600, ...</font>
FixHUD = 1
FixFOV = 1
Scaling = 1
HUDWidescreenMode = 0
FMVWidescreenMode = 0

...

## *"Custom" resolutions need `WindowedMode` to be enabled otherwise the game won't start.*
