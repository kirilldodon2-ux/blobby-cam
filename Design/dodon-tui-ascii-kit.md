# dodon.one — Blobby Cam TUI ASCII Kit

Reference ASCII assets for the terminal UI. Box-drawing chars (─│┌┐└┘├┤) —
if the target terminal/font doesn't support them, swap for `-`, `|`, `+`.

## 1. Header / splash banner

```
     _           _
  __| | ___   __| | ___  _ __    ___  _ __   ___
 / _` |/ _ \ / _` |/ _ \| '_ \  / _ \| '_ \ / _ \
| (_| | (_) | (_| | (_) | | | || (_) | | | |  __/
 \__,_|\___/ \__,_|\___/|_| |_(_)___/|_| |_|\___|

     ヽ(◕‿◕)ノ         __
                    __/ o\_____.,>     hello from dodon.one!
                    \____________.-'
                    ~~~~~~~~~~~~~~~~~~~
```

## 2. BLOBBY CAM screen

CAMERA states: `IDLE / STARTING / LIVE / DENIED / ERROR`
Progress caption swaps per state, e.g. `installing...`, `connecting...`, `denied.`, `error.`

```
┌──────────────────────────────────────────────────┐
│               B L O B B Y   C A M                │
├──────────────────────────────────────────────────┤
│                                                    │
│               .------------------.                │
│               | o                |                │
│               |      /\    /\    |                │
│               |     /  \  /  \   |                │
│               '------------------'                │
│                                                    │
│  CAMERA:                                    LIVE  │
│                                                    │
│           [●●●●●●○○○○○○○○○○○○○○]  30%             │
│                  installing...                    │
│                                                    │
└──────────────────────────────────────────────────┘
```

## 3. Main menu (GLOBAL + FEATURE WINDOWS)

```
┌──────────────────────────────────────────────────┐
│    D O D O N . O N E   —   M A I N   M E N U      │
├──────────────────────────────────────────────────┤
│── GLOBAL ──────────────────────────────────────── │
│> LIVE                                   OFF / ON  │
│  SHOW ALL                               ON / OFF  │
│  AUTO FOLLOW                            OFF / ON  │
│  MIRROR                                 ON / OFF  │
│  SMOOTHING                             0.00–1.00  │
│  RESET ALL                                 ENTER  │
│                                                    │
│── FEATURE WINDOWS ─────────────────────────────── │
│  LEFT EYE                               ON / OFF  │
│  RIGHT EYE                              ON / OFF  │
│  NOSE                                   ON / OFF  │
│  MOUTH                                  ON / OFF  │
│  LEFT HAND                              ON / OFF  │
│  RIGHT HAND                             ON / OFF  │
│                                                    │
│  SHOW GOOFY UI                          OFF / ON  │
│  QUIT                                             │
└──────────────────────────────────────────────────┘
```

`>` marks the currently selected row (moves with cursor keys).

## 4. Feature detail screen (template)

Title swaps per feature: `FEATURE / LEFT EYE`, `FEATURE / RIGHT HAND`, etc.

```
┌──────────────────────────────────────────────────┐
│                FEATURE / LEFT EYE                 │
├──────────────────────────────────────────────────┤
│  CAMERA:                                    LIVE  │
├──────────────────────────────────────────────────┤
│> ENABLED                                ON / OFF  │
│  WINDOW SIZE               current / ENTER=reset  │
│  WINDOW X                                         │
│  WINDOW Y                                         │
│  CROP ZOOM                                        │
│  PAN X                                            │
│  PAN Y                                            │
│  CROP PADDING                                     │
│  DETECTION                             threshold  │
├──────────────────────────────────────────────────┤
│                    ESC = back                     │
└──────────────────────────────────────────────────┘
```
