# HCI-GOLF

A golf assistant for Garmin watches. It shows the distance from your saved ball position to the green on the current hole, using mapped course data for Elmwood Park Golf Course.

Current target: **Forerunner 165 (fr165)**, Connect IQ API 5.2.0.

## Features

- **Start screen:** shows the current hole, par, and yardage from the scorecard for holes 1 to 5. UP and DOWN change the hole.
- **Locate ball:** press SELECT at your ball to save your GPS position for that hole.
- **Distance screen:** shows the yardage from the saved ball to the mapped green center, with the hole number and a flag graphic. UP and DOWN change the hole, and BACK returns to the start screen.
- **Saved positions:** each hole's ball position is stored on the watch and kept after the app closes.

## Screen Flow

```
Start (hole 1-5) --SELECT--> Locate ball --SELECT (saves ball)--> Distance
      ^                                                             |
      +-------------------------- BACK -----------------------------+
```

| Button | Start | Locate | Distance |
|---|---|---|---|
| UP / DOWN | Change hole | - | Change hole |
| SELECT | Open locate | Save ball, open distance | - |
| BACK | Exit app | Return to start | Return to start |

## Project Structure

```
HCI-GOLF/
├── manifest.xml              App ID, product (fr165), permissions
├── monkey.jungle             Build configuration
├── resources/
│   ├── resources.xml         Declares the hole01-hole05 JSON resources
│   ├── jsonData/             One compact course file per hole
│   │   ├── hole01.json
│   │   └── ...
│   ├── drawables/
│   ├── layouts/
│   ├── menus/
│   └── strings/
└── source/
    ├── HCI-GOLFApp.mc        App class: GPS, holes, saved balls, scorecard data
    ├── HCI-StartDelegate.mc   Button handling for the start, locate, and distance screens
    ├── HCI_StartHoleView.mc  Start screen
    ├── HCI_LocateBallView.mc Locate screen
    ├── HCI_DistanceView.mc   Distance screen
    └── GolfGeo.mc           Distance and geometry calculations
```

## Course Data

Each hole file in `resources/jsonData/` contains only the features the app uses: tee, green, bunker, water, hazard, and the primary playing line. Paths, pins, and fairways were removed to keep the files small. Coordinates are rounded to 6 decimals (about 0.1 m).

Holes 1 to 5 are included. Holes 6 to 18 have no data yet.

Par and yardage come from the scorecard in `HCI-GOLFApp.mc`. The app shows the scorecard yardage when it's available. If not, it shows an estimate from the mapped playing line, marked with `~`.

## Distance Calculations

`GolfGeo.analyze` measures from the saved ball position to the mapped green:

- **Center:** the mapped green center. This is the number shown on the distance screen.
- **Front and back:** estimated along the tee-to-green axis. Calculated, not yet shown on screen.
- **Water carry:** available in the result, not yet shown.

Distances are straight-line estimates from mapped geometry. They are not the daily pin position, and they don't account for elevation or wind.

## Testing in the Simulator

1. Build and run the `HCI-GOLF` target on fr165.
2. Start screen: confirm `HOLE 1` and the par and yardage line appear. Press UP and DOWN to change holes, and check that they wrap from 5 to 1.
3. Set a simulator position near the hole 1 tee (41.2492834, -96.0099062), then press START.
4. Locate screen: press SELECT. The distance screen should appear with a number.
5. Move the simulator position. The distance should not change until you save a new ball position.
6. Press BACK from the distance screen to return to the start screen.
7. Close and reopen the app. The saved ball should still give a distance on hole 1.

## Known Limitations

- Wind is shown as `-- mph` because the watch has no wind data.
- The locate screen gives no message when there's no GPS fix.
- Re-locating a ball is only possible from the start screen.
- Holes 6 to 18 have no data.
- Only tested in the simulator so far.

## Planned Features

- Front and back yardages on the distance screen
- Club recommendation based on distance
- Club selection
- Recording shots (club, start and end positions, distance)
- Round summary

## Data Sources

- Course geometry: OpenStreetMap, cleaned and exported per hole.
- Par, yardage, and stroke index: Elmwood Park scorecard (holes 1 to 5).


## Compile
```powershell
java -Xms1g -jar "C:\Users\Eduardo\AppData\Roaming\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-9.2.0-2026-06-09-92a1605b2\bin\monkeybrains.jar" -o bin\HCIGOLF.prg -f monkey.jungle -y "C:\Users\Eduardo\OneDrive - University of Nebraska\Fall 2026\CSCI 4250\developer_key" -d fr165 -w
```

## Run compilation
```powershell
& "C:\Users\Eduardo\AppData\Roaming\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-9.2.0-2026-06-09-92a1605b2\bin\monkeydo.bat" "bin\HCIGOLF.prg" fr165   
```