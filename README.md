# Golf Distances

A Python script that calculates distances from a GPS location to golf course features using course data stored in JSON format. This tool is part of the HCI-GOLF project, which aims to develop a golf assistant for Garmin watches.

## Requirements

- Python 3
- `golf_distances.py`
- `course_model.json`

## Usage

Run the script from the project directory using PowerShell:

```powershell
py .\golf_distances.py --model .\course_model.json --hole 1 --lat 41.2511 --lon -96.0072 --radius 500
```

Arguments:

- `--model`: Path to the course data JSON file.
- `--hole`: Hole number to test.
- `--lat`: Latitude of the simulated location.
- `--lon`: Longitude of the simulated location.
- `--radius`: Search radius in yards for nearby course features.

## Testing

You can test the script by entering different GPS coordinates and hole numbers. The script calculates distances to the green and nearby mapped course features, depending on the available course data.

To test another location, change the `--lat` and `--lon` values. You can also adjust the search radius to find features farther away.

## Current Status

This is a work in progress. The distance calculations currently run in Python on a computer, using processed golf course data. Further testing and development are needed before integrating the functionality into the Garmin watch application.

