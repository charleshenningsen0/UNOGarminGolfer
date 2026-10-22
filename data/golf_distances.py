#!/usr/bin/env python3
"""
Calculate distances from a GPS position to a selected golf hole's features.

Examples:
    py golf_distances.py --model course_model.json --hole 1 --lat 41.2511 --lon -96.0072
    py golf_distances.py --model course_model.json --hole 1 --lat 41.2511 --lon -96.0072 --radius 500
    py golf_distances.py --model course_model.json --hole 1 --lat 41.2511 --lon -96.0072 --unit meters
    py golf_distances.py --model course_model.json --hole 1 --lat 41.2511 --lon -96.0072 --all-features
    py golf_distances.py --model course_model.json --hole 1 --lat 41.2511 --lon -96.0072 --json

No third-party packages are required.

Notes:
- Distances are horizontal ground distances.
- Polygon distances are zero when the golfer is inside the polygon.
- Green front/back estimates prefer the mapped primary playing line, then a mapped tee.
- Green distances are estimates based on mapped geometry, not the daily pin.
- Walking paths are excluded from the nearby-features report.
"""

import argparse
import json
import math
from pathlib import Path
from typing import Any, Iterable

EARTH_RADIUS_M = 6_371_008.8
METERS_PER_YARD = 0.9144
METERS_PER_FOOT = 0.3048


def compass_direction(bearing_degrees: float) -> str:
    """Convert a true-north bearing into one of eight compass directions."""
    directions = (
        "North", "Northeast", "East", "Southeast",
        "South", "Southwest", "West", "Northwest",
    )
    normalized = bearing_degrees % 360.0
    index = int((normalized + 22.5) // 45.0) % 8
    return directions[index]


def initial_bearing_degrees(
    lat1: float, lon1: float, lat2: float, lon2: float
) -> float:
    """Return the initial bearing from point 1 to point 2, clockwise from true north."""
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_lon = math.radians(lon2 - lon1)
    y = math.sin(delta_lon) * math.cos(phi2)
    x = (
        math.cos(phi1) * math.sin(phi2)
        - math.sin(phi1) * math.cos(phi2) * math.cos(delta_lon)
    )
    return (math.degrees(math.atan2(y, x)) + 360.0) % 360.0


def haversine_m(
    lat1: float, lon1: float, lat2: float, lon2: float
) -> float:
    """Calculate great-circle distance in meters."""
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    d_phi = math.radians(lat2 - lat1)
    d_lam = math.radians(lon2 - lon1)

    a = (
        math.sin(d_phi / 2) ** 2
        + math.cos(phi1)
        * math.cos(phi2)
        * math.sin(d_lam / 2) ** 2
    )

    return 2 * EARTH_RADIUS_M * math.asin(
        min(1.0, math.sqrt(a))
    )


def valid_coordinate_pair(value: Any) -> tuple[float, float] | None:
    """Convert GeoJSON [longitude, latitude] to (latitude, longitude)."""
    if (
        isinstance(value, (list, tuple))
        and len(value) >= 2
        and isinstance(value[0], (int, float))
        and isinstance(value[1], (int, float))
    ):
        lon, lat = float(value[0]), float(value[1])

        if -90 <= lat <= 90 and -180 <= lon <= 180:
            return lat, lon

    return None


def ring_points(ring: Any) -> list[tuple[float, float]]:
    """Extract valid latitude/longitude points from a coordinate ring."""
    points = []

    if isinstance(ring, list):
        for coordinate in ring:
            point = valid_coordinate_pair(coordinate)

            if point:
                points.append(point)

    return points


def geometry_rings(
    geometry: dict[str, Any] | None,
) -> list[list[tuple[float, float]]]:
    """Collect coordinate sequences from common GeoJSON geometry types."""
    if not isinstance(geometry, dict):
        return []

    kind = geometry.get("type")
    coordinates = geometry.get("coordinates")
    rings = []

    if kind == "Polygon" and isinstance(coordinates, list):
        for ring in coordinates:
            points = ring_points(ring)

            if len(points) >= 3:
                rings.append(points)

    elif kind == "MultiPolygon" and isinstance(coordinates, list):
        for polygon in coordinates:
            if not isinstance(polygon, list):
                continue

            for ring in polygon:
                points = ring_points(ring)

                if len(points) >= 3:
                    rings.append(points)

    elif kind == "LineString" and isinstance(coordinates, list):
        points = ring_points(coordinates)

        if len(points) >= 2:
            rings.append(points)

    elif kind == "MultiLineString" and isinstance(coordinates, list):
        for line in coordinates:
            points = ring_points(line)

            if len(points) >= 2:
                rings.append(points)

    elif kind == "Point":
        point = valid_coordinate_pair(coordinates)

        if point:
            rings.append([point])

    elif kind == "MultiPoint" and isinstance(coordinates, list):
        points = [
            point
            for point in (
                valid_coordinate_pair(coordinate)
                for coordinate in coordinates
            )
            if point
        ]

        if points:
            rings.append(points)

    return rings


def polygon_outer_rings(
    geometry: dict[str, Any] | None,
) -> list[list[tuple[float, float]]]:
    """Return only the outer boundary of each polygon."""
    if not isinstance(geometry, dict):
        return []

    kind = geometry.get("type")
    coordinates = geometry.get("coordinates")
    result = []

    if kind == "Polygon" and isinstance(coordinates, list):
        if coordinates:
            points = ring_points(coordinates[0])

            if len(points) >= 3:
                result.append(points)

    elif kind == "MultiPolygon" and isinstance(coordinates, list):
        for polygon in coordinates:
            if not isinstance(polygon, list) or not polygon:
                continue

            points = ring_points(polygon[0])

            if len(points) >= 3:
                result.append(points)

    return result


def local_xy_m(
    lat: float,
    lon: float,
    origin_lat: float,
    origin_lon: float,
) -> tuple[float, float]:
    """Approximate local east/north coordinates in meters."""
    mean_lat = math.radians((lat + origin_lat) / 2.0)

    x = (
        math.radians(lon - origin_lon)
        * EARTH_RADIUS_M
        * math.cos(mean_lat)
    )
    y = math.radians(lat - origin_lat) * EARTH_RADIUS_M

    return x, y


def point_segment_distance_xy(
    px: float,
    py: float,
    ax: float,
    ay: float,
    bx: float,
    by: float,
) -> tuple[float, float]:
    """Return point-to-segment distance and the closest segment fraction."""
    dx, dy = bx - ax, by - ay
    length_squared = dx * dx + dy * dy

    if length_squared == 0:
        return math.hypot(px - ax, py - ay), 0.0

    t = ((px - ax) * dx + (py - ay) * dy) / length_squared
    t = max(0.0, min(1.0, t))

    closest_x = ax + t * dx
    closest_y = ay + t * dy

    return math.hypot(px - closest_x, py - closest_y), t


def point_in_ring_xy(
    px: float,
    py: float,
    ring_xy: list[tuple[float, float]],
) -> bool:
    """Determine whether a point is inside a ring using ray casting."""
    inside = False
    j = len(ring_xy) - 1

    for i, (xi, yi) in enumerate(ring_xy):
        xj, yj = ring_xy[j]

        crosses = ((yi > py) != (yj > py)) and (
            px < (xj - xi) * (py - yi) / ((yj - yi) or 1e-15) + xi
        )

        if crosses:
            inside = not inside

        j = i

    return inside


def point_in_polygon_xy(
    px: float,
    py: float,
    rings_xy: list[list[tuple[float, float]]],
) -> bool:
    """Check whether a point is inside a polygon, excluding its holes."""
    if not rings_xy or not point_in_ring_xy(px, py, rings_xy[0]):
        return False

    return not any(
        point_in_ring_xy(px, py, ring)
        for ring in rings_xy[1:]
    )


def rep_point(
    feature: dict[str, Any],
) -> tuple[float, float] | None:
    """Read a feature's representative point, if available."""
    point = feature.get("representative_point") or {}

    try:
        lat = float(point["latitude"])
        lon = float(point["longitude"])

        if -90 <= lat <= 90 and -180 <= lon <= 180:
            return lat, lon

    except (KeyError, TypeError, ValueError):
        pass

    return None


def feature_anchor(
    feature: dict[str, Any],
) -> tuple[float, float] | None:
    """Get a representative location, preferring a point inside polygons."""
    geometry = feature.get("geometry")
    point = rep_point(feature)
    outer_rings = polygon_outer_rings(geometry)

    if point and outer_rings:
        # Source representative points can be stale or fall outside the
        # polygon. Accept them only if they are actually inside the geometry.
        rings_xy = [
            [
                local_xy_m(lat, lon, point[0], point[1])
                for lat, lon in ring
            ]
            for ring in geometry_rings(geometry)
        ]
        if point_in_polygon_xy(0.0, 0.0, rings_xy):
            return point
    elif point:
        return point

    if outer_rings:
        # Compute the polygon centroid in a local meter-based coordinate
        # system instead of averaging latitude/longitude vertices.
        origin_lat = sum(lat for lat, _ in outer_rings[0]) / len(outer_rings[0])
        origin_lon = sum(lon for _, lon in outer_rings[0]) / len(outer_rings[0])
        ring_xy = [
            local_xy_m(lat, lon, origin_lat, origin_lon)
            for lat, lon in outer_rings[0]
        ]

        twice_area = 0.0
        centroid_x_sum = 0.0
        centroid_y_sum = 0.0
        for index, (x1, y1) in enumerate(ring_xy):
            x2, y2 = ring_xy[(index + 1) % len(ring_xy)]
            cross = x1 * y2 - x2 * y1
            twice_area += cross
            centroid_x_sum += (x1 + x2) * cross
            centroid_y_sum += (y1 + y2) * cross

        if abs(twice_area) > 1e-9:
            centroid_x = centroid_x_sum / (3.0 * twice_area)
            centroid_y = centroid_y_sum / (3.0 * twice_area)
            centroid = local_xy_to_latlon(
                centroid_x, centroid_y, origin_lat, origin_lon
            )
            rings_xy = [
                [
                    local_xy_m(lat, lon, origin_lat, origin_lon)
                    for lat, lon in ring
                ]
                for ring in geometry_rings(geometry)
            ]
            if point_in_polygon_xy(centroid_x, centroid_y, rings_xy):
                return centroid

        # Fallback for unusual/concave polygons whose centroid is outside.
        points = [point for ring in outer_rings for point in ring]
    else:
        rings = geometry_rings(geometry)
        points = [point for ring in rings for point in ring]

    if not points:
        return point

    return (
        sum(lat for lat, _ in points) / len(points),
        sum(lon for _, lon in points) / len(points),
    )


def distance_to_geometry_m(
    lat: float,
    lon: float,
    geometry: dict[str, Any] | None,
) -> tuple[float | None, tuple[float, float] | None]:
    """
    Return (distance_m, nearest_lat_lon).

    Polygon distances are zero when the position is inside the polygon.
    Otherwise, the distance is to the closest mapped boundary.
    """
    if not isinstance(geometry, dict):
        return None, None

    kind = geometry.get("type")
    rings = geometry_rings(geometry)

    if not rings:
        return None, None

    rings_xy = [
        [
            local_xy_m(point_lat, point_lon, lat, lon)
            for point_lat, point_lon in ring
        ]
        for ring in rings
    ]

    if kind == "Polygon":
        if point_in_polygon_xy(0.0, 0.0, rings_xy):
            return 0.0, (lat, lon)

    elif kind == "MultiPolygon":
        coordinates = geometry.get("coordinates") or []

        for polygon in coordinates:
            if not isinstance(polygon, list):
                continue

            polygon_rings = []

            for ring in polygon:
                points = ring_points(ring)

                if len(points) >= 3:
                    polygon_rings.append([
                        local_xy_m(point_lat, point_lon, lat, lon)
                        for point_lat, point_lon in points
                    ])

            if point_in_polygon_xy(0.0, 0.0, polygon_rings):
                return 0.0, (lat, lon)

    best_distance = float("inf")
    best_xy = None
    is_closed = kind in ("Polygon", "MultiPolygon")

    for ring in rings_xy:
        if len(ring) == 1:
            distance = math.hypot(ring[0][0], ring[0][1])

            if distance < best_distance:
                best_distance = distance
                best_xy = ring[0]

            continue

        segments: Iterable[
            tuple[tuple[float, float], tuple[float, float]]
        ]

        if is_closed:
            segments = zip(ring, ring[1:] + ring[:1])
        else:
            segments = zip(ring, ring[1:])

        for (ax, ay), (bx, by) in segments:
            distance, fraction = point_segment_distance_xy(
                0.0, 0.0, ax, ay, bx, by
            )

            if distance < best_distance:
                best_distance = distance
                best_xy = (
                    ax + fraction * (bx - ax),
                    ay + fraction * (by - ay),
                )

    if best_xy is None:
        return None, None

    nearest_lat = lat + math.degrees(best_xy[1] / EARTH_RADIUS_M)
    cos_lat = math.cos(math.radians(lat))

    if abs(cos_lat) < 1e-12:
        nearest_lon = lon
    else:
        nearest_lon = lon + math.degrees(
            best_xy[0] / (EARTH_RADIUS_M * cos_lat)
        )

    return best_distance, (nearest_lat, nearest_lon)


def classify_feature(feature: dict[str, Any]) -> str:
    """Refine feature categories using the available source metadata."""
    props = feature.get("properties") or {}

    values = [
        feature.get("category", ""),
        feature.get("name", ""),
        feature.get("feature_id", ""),
        props.get("category", ""),
        props.get("name", ""),
        props.get("ref", ""),
        props.get("feature_id", ""),
        props.get("osm_id", ""),
        props.get("layer", ""),
        props.get("golf", ""),
        props.get("leisure", ""),
        props.get("natural", ""),
        props.get("landuse", ""),
        props.get("water", ""),
        props.get("waterway", ""),
        props.get("hazard", ""),
        props.get("highway", ""),
    ]

    metadata = " ".join(str(value) for value in values).lower()
    category = str(feature.get("category") or "").lower()

    # A primary hole line describes the playing direction, not an obstacle.
    if (
        str(props.get("layer", "")).lower() == "hole"
        and str(props.get("playing_line", "")).lower() == "primary"
    ):
        return "playing_line"

    # Pins are mapped as point features and may be stored under the source
    # category "other". Recognize them from their layer or feature ID.
    if (
        str(props.get("layer", "")).lower() == "pin"
        or str(props.get("feature_id", "")).lower().startswith("pin-")
        or str(feature.get("feature_id", "")).lower().startswith("pin-")
        or str(feature.get("name", "")).lower().startswith("pin-")
    ):
        return "pin"

    # Identify paths first so they do not get reported as useful golf features.
    if any(term in metadata for term in (
        "path-osm",
        "pathway",
        "footway",
        "walkway",
        "pedestrian",
        "walking path",
        "golf cart path",
        "cart path",
        "track-osm",
    )):
        return "path"

    # Common feature ID prefixes.
    if any(term in metadata for term in (
        "bunker",
        "sand trap",
    )):
        return "bunker"

    if any(term in metadata for term in (
        "water hazard",
        "water-hazard",
        "waterway",
        "pond",
        "lake",
        "river",
        "stream",
        "water-osm",
    )):
        return "water"

    if any(term in metadata for term in (
        "hazard",
        "out-of-bounds",
        "out of bounds",
    )):
        return "hazard"

    if "fairway" in metadata:
        return "fairway"

    if "putting green" in metadata or "green-osm" in metadata:
        return "green"

    if "teeing ground" in metadata or "tee-osm" in metadata:
        return "tee"

    # Preserve an existing recognized category if metadata is inconclusive.
    if category in (
        "green",
        "tee",
        "fairway",
        "bunker",
        "water",
        "hazard",
        "pin",
        "other",
        "path",
        "playing_line",
    ):
        return category

    return "other"


def get_hole_features(
    model: dict[str, Any],
    hole_number: int,
) -> list[dict[str, Any]]:
    """Return the features associated with the requested hole."""
    for hole in model.get("holes", []):
        try:
            number = int(hole.get("hole_number"))
        except (TypeError, ValueError):
            continue

        if number != hole_number:
            continue

        features_by_category = hole.get("features_by_category") or {}
        result = []

        for category, features in features_by_category.items():
            if not isinstance(features, list):
                continue

            for feature in features:
                if not isinstance(feature, dict):
                    continue

                copied = dict(feature)
                copied.setdefault("category", category)
                copied["category"] = classify_feature(copied)
                result.append(copied)

        return result

    return []


def feature_name(feature: dict[str, Any]) -> str:
    """Return a readable feature name or identifier."""
    props = feature.get("properties") or {}

    for key in ("name", "ref", "feature_id", "osm_id"):
        value = props.get(key)

        if value:
            return str(value)

    for key in ("name", "feature_id", "id"):
        value = feature.get(key)

        if value is not None:
            return str(value)

    return f"{feature.get('category', 'feature')} #?"


def distance_m_from_unit(distance: float, unit: str) -> float:
    """Convert a distance in the selected display unit to meters."""
    if unit == "meters":
        return distance
    if unit == "feet":
        return distance * 0.3048
    return distance * 0.9144


def distance_value(meters: float, unit: str) -> float:
    """Convert meters to the selected output unit."""
    if unit == "yards":
        return meters / METERS_PER_YARD

    if unit == "feet":
        return meters / METERS_PER_FOOT

    return meters


def round_distance(value: float) -> float:
    return round(value, 1)


def choose_playing_line_tee(
    features: list[dict[str, Any]],
    green: dict[str, Any],
) -> tuple[float, float] | None:
    """Find the tee-side endpoint of the mapped primary playing line."""
    green_anchor = feature_anchor(green)

    if green_anchor is None:
        return None

    candidates = []

    for feature in features:
        props = feature.get("properties") or {}
        if (
            str(props.get("layer", "")).lower() != "hole"
            or str(props.get("playing_line", "")).lower() != "primary"
        ):
            continue

        points = [
            point
            for ring in geometry_rings(feature.get("geometry"))
            for point in ring
        ]
        if len(points) < 2:
            continue

        # The endpoint closest to the green anchor is the green-side endpoint.
        first, last = points[0], points[-1]
        first_to_green = haversine_m(
            first[0], first[1], green_anchor[0], green_anchor[1]
        )
        last_to_green = haversine_m(
            last[0], last[1], green_anchor[0], green_anchor[1]
        )
        tee_endpoint = last if first_to_green < last_to_green else first
        # Prefer the line whose green-side endpoint best matches this green.
        candidates.append((min(first_to_green, last_to_green), tee_endpoint))

    if not candidates:
        return None

    candidates.sort(key=lambda item: item[0])
    return candidates[0][1]


def choose_tee(
    features: list[dict[str, Any]],
    green: dict[str, Any],
) -> tuple[float, float] | None:
    """
    Choose the mapped tee anchor nearest to the green anchor.

    This is a practical approximation when a hole has multiple tee boxes.
    """
    green_anchor = feature_anchor(green)

    if green_anchor is None:
        return None

    tees = []

    for feature in features:
        if feature.get("category") != "tee":
            continue

        anchor = feature_anchor(feature)

        if anchor:
            distance = haversine_m(
                anchor[0], anchor[1],
                green_anchor[0], green_anchor[1],
            )
            tees.append((distance, anchor))

    if not tees:
        return None

    tees.sort(key=lambda item: item[0])
    return tees[0][1]


def local_xy_to_latlon(
    x: float,
    y: float,
    origin_lat: float,
    origin_lon: float,
) -> tuple[float, float]:
    """Convert local east/north meters back to latitude/longitude."""
    lat = origin_lat + math.degrees(y / EARTH_RADIUS_M)
    cos_lat = math.cos(math.radians(origin_lat))
    if abs(cos_lat) < 1e-12:
        lon = origin_lon
    else:
        lon = origin_lon + math.degrees(
            x / (EARTH_RADIUS_M * cos_lat)
        )
    return lat, lon


def green_measurements(
    golfer_lat: float,
    golfer_lon: float,
    green: dict[str, Any],
    features: list[dict[str, Any]],
) -> dict[str, Any]:
    """
    Estimate green front, center, and back along the mapped playing direction.

    Front and back are the outer-boundary vertices with the minimum and
    maximum projection onto the tee-to-green axis. The center point is placed
    halfway between those projections while retaining the green anchor's
    lateral offset from the axis. Distances are direct horizontal distances.
    """
    geometry = green.get("geometry")
    outer_rings = polygon_outer_rings(geometry)
    points = [point for ring in outer_rings for point in ring]

    if not points:
        points = [
            point
            for ring in geometry_rings(geometry)
            for point in ring
        ]

    if not points:
        return {
            "front": None,
            "center": None,
            "back": None,
            "front_point": None,
            "center_point": None,
            "back_point": None,
            "direction_method": "unavailable",
        }

    green_anchor = feature_anchor(green)

    if green_anchor is None:
        green_anchor = (
            sum(lat for lat, _ in points) / len(points),
            sum(lon for _, lon in points) / len(points),
        )

    center_distance = haversine_m(
        golfer_lat,
        golfer_lon,
        green_anchor[0],
        green_anchor[1],
    )

    # Prefer the explicit primary playing line when the course map provides it.
    tee_anchor = choose_playing_line_tee(features, green)
    direction_method = "playing_line_axis_estimate"

    if tee_anchor is None:
        tee_anchor = choose_tee(features, green)
        direction_method = "tee_to_green_axis_estimate"

    # Without a mapped direction, use the nearest boundary and farthest vertex.
    if tee_anchor is None:
        nearest_distance, nearest_point = distance_to_geometry_m(
            golfer_lat, golfer_lon, geometry
        )

        if nearest_distance is None:
            nearest_distance = center_distance

        farthest_point = max(
            points,
            key=lambda point: haversine_m(
                golfer_lat, golfer_lon, point[0], point[1]
            ),
        )

        back_distance = haversine_m(
            golfer_lat,
            golfer_lon,
            farthest_point[0],
            farthest_point[1],
        )

        return {
            "front": nearest_distance,
            "center": center_distance,
            "back": back_distance,
            "front_point": nearest_point,
            "center_point": green_anchor,
            "back_point": farthest_point,
            "direction_method": "fallback_without_mapped_tee",
        }

    # Express the tee, green anchor, and boundary vertices in local meters.
    tee_x, tee_y = 0.0, 0.0
    green_x, green_y = local_xy_m(
        green_anchor[0], green_anchor[1],
        tee_anchor[0], tee_anchor[1],
    )

    axis_length = math.hypot(green_x - tee_x, green_y - tee_y)

    if axis_length < 0.01:
        nearest_distance, nearest_point = distance_to_geometry_m(
            golfer_lat, golfer_lon, geometry
        )

        if nearest_distance is None:
            nearest_distance = center_distance

        farthest_point = max(
            points,
            key=lambda point: haversine_m(
                golfer_lat, golfer_lon, point[0], point[1]
            ),
        )

        return {
            "front": nearest_distance,
            "center": center_distance,
            "back": haversine_m(
                golfer_lat, golfer_lon,
                farthest_point[0], farthest_point[1],
            ),
            "front_point": nearest_point,
            "center_point": green_anchor,
            "back_point": farthest_point,
            "direction_method": "fallback_invalid_tee_to_green_axis",
        }

    axis_x = (green_x - tee_x) / axis_length
    axis_y = (green_y - tee_y) / axis_length

    def point_xy(point: tuple[float, float]) -> tuple[float, float]:
        return local_xy_m(
            point[0], point[1], tee_anchor[0], tee_anchor[1]
        )

    def projection(point: tuple[float, float]) -> float:
        x, y = point_xy(point)
        return x * axis_x + y * axis_y

    # The minimum projection is the tee-side edge; maximum is the back edge.
    front_point = min(points, key=projection)
    back_point = max(points, key=projection)
    front_projection = projection(front_point)
    back_projection = projection(back_point)

    # Find where a cross-section perpendicular to the playing axis at the
    # midpoint of the green's projected front-to-back span intersects the
    # polygon. The midpoint of those intersections stays on the green for
    # ordinary, non-multipart green polygons, unlike offsetting an external
    # or inaccurate representative point.
    center_projection = (front_projection + back_projection) / 2.0
    lateral_intersections = []

    for ring in outer_rings:
        ring_xy = [point_xy(point) for point in ring]
        for index, (x1, y1) in enumerate(ring_xy):
            x2, y2 = ring_xy[(index + 1) % len(ring_xy)]
            projection1 = x1 * axis_x + y1 * axis_y
            projection2 = x2 * axis_x + y2 * axis_y
            lateral1 = -x1 * axis_y + y1 * axis_x
            lateral2 = -x2 * axis_y + y2 * axis_x

            # Include a vertex exactly on the cross-section and interpolate
            # each edge that crosses it.
            if abs(projection1 - center_projection) < 1e-7:
                lateral_intersections.append(lateral1)

            if (
                (projection1 < center_projection < projection2)
                or (projection2 < center_projection < projection1)
            ):
                fraction = (
                    (center_projection - projection1)
                    / (projection2 - projection1)
                )
                lateral_intersections.append(
                    lateral1 + fraction * (lateral2 - lateral1)
                )

    if len(lateral_intersections) >= 2:
        center_lateral = (
            min(lateral_intersections) + max(lateral_intersections)
        ) / 2.0
    else:
        # Defensive fallback if the polygon is degenerate or the cross-section
        # does not intersect it as expected.
        anchor_x, anchor_y = point_xy(green_anchor)
        center_lateral = -anchor_x * axis_y + anchor_y * axis_x

    center_x = center_projection * axis_x - center_lateral * axis_y
    center_y = center_projection * axis_y + center_lateral * axis_x
    center_point = local_xy_to_latlon(
        center_x, center_y, tee_anchor[0], tee_anchor[1]
    )

    front_distance = haversine_m(
        golfer_lat, golfer_lon,
        front_point[0], front_point[1],
    )
    center_distance = haversine_m(
        golfer_lat, golfer_lon,
        center_point[0], center_point[1],
    )
    back_distance = haversine_m(
        golfer_lat, golfer_lon,
        back_point[0], back_point[1],
    )

    return {
        "front": front_distance,
        "center": center_distance,
        "back": back_distance,
        "front_point": front_point,
        "center_point": center_point,
        "back_point": back_point,
        "direction_method": direction_method,
    }



def ray_polygon_intersections_m(
    origin_lat: float,
    origin_lon: float,
    target_lat: float,
    target_lon: float,
    geometry: dict[str, Any] | None,
) -> list[float]:
    """Return distances along the golfer-to-target ray where it crosses polygon boundaries.

    Distances are meters from the golfer. Coordinates are projected into a local
    east/north plane, which is sufficiently accurate for a single golf hole.
    """
    if not isinstance(geometry, dict) or geometry.get("type") not in ("Polygon", "MultiPolygon"):
        return []

    target_x, target_y = local_xy_m(target_lat, target_lon, origin_lat, origin_lon)
    ray_length = math.hypot(target_x, target_y)
    if ray_length < 0.01:
        return []

    dx, dy = target_x / ray_length, target_y / ray_length
    intersections: list[float] = []

    for ring in geometry_rings(geometry):
        ring_xy = [local_xy_m(lat, lon, origin_lat, origin_lon) for lat, lon in ring]
        if len(ring_xy) < 2:
            continue
        for index, (ax, ay) in enumerate(ring_xy):
            bx, by = ring_xy[(index + 1) % len(ring_xy)]
            sx, sy = bx - ax, by - ay
            # Solve t * ray + origin = A + u * edge.
            denom = dx * sy - dy * sx
            if abs(denom) < 1e-9:
                continue
            t = (ax * sy - ay * sx) / denom
            u = (ax * dy - ay * dx) / denom
            if t >= -0.01 and -1e-9 <= u <= 1.0 + 1e-9:
                intersections.append(max(0.0, t))

    intersections.sort()
    deduped: list[float] = []
    for distance in intersections:
        if not deduped or abs(distance - deduped[-1]) > 0.25:
            deduped.append(distance)
    return deduped

def water_carry_measurement(
    golfer_lat: float,
    golfer_lon: float,
    target: tuple[float, float] | None,
    water_feature: dict[str, Any],
    unit: str = "yards",
) -> dict[str, Any] | None:
    """Estimate near/far water edges along a straight shot toward the green center."""
    if target is None:
        return None
    geometry = water_feature.get("geometry")
    target_distance = haversine_m(golfer_lat, golfer_lon, target[0], target[1])
    if target_distance < 1.0:
        return None

    intersections = ray_polygon_intersections_m(
        golfer_lat, golfer_lon, target[0], target[1], geometry
    )
    # Ignore intersections beyond the green center: they are not between the
    # golfer and the target. A small tolerance handles projection differences.
    intersections = [d for d in intersections if d <= target_distance + 1.0]
    rings = geometry_rings(geometry)
    rings_xy = [
        [local_xy_m(lat, lon, golfer_lat, golfer_lon) for lat, lon in ring]
        for ring in rings
    ]
    starts_in_water = (geometry or {}).get("type") == "Polygon" and point_in_polygon_xy(0.0, 0.0, rings_xy)
    if (geometry or {}).get("type") == "MultiPolygon":
        for polygon in (geometry or {}).get("coordinates", []):
            poly_rings = []
            for ring in polygon:
                pts = ring_points(ring)
                if len(pts) >= 3:
                    poly_rings.append([local_xy_m(lat, lon, golfer_lat, golfer_lon) for lat, lon in pts])
            if point_in_polygon_xy(0.0, 0.0, poly_rings):
                starts_in_water = True
                break

    if not intersections and not starts_in_water:
        return None

    if starts_in_water:
        near_m = 0.0
        far_m = intersections[0] if intersections else None
    else:
        # A normal crossing has entry and exit intersections. Odd counts can
        # occur at vertices, so pair sequentially and use the final crossing
        # as the exit only when a complete pair is available.
        if len(intersections) < 2:
            return None
        near_m, far_m = intersections[0], intersections[1]

    if far_m is None:
        return None

    return {
        "near_edge_distance": round_distance(distance_value(near_m, unit)),
        "far_edge_distance": round_distance(distance_value(far_m, unit)),
        "water_width_along_shot": round_distance(distance_value(max(0.0, far_m - near_m), unit)),
        "required_carry_to_clear": round_distance(distance_value(far_m, unit)),
        "unit": unit,
        "direction": "straight line from current GPS position toward mapped green center",
        "target": {"latitude": round(target[0], 7), "longitude": round(target[1], 7)},
        "verified": (water_feature.get("properties") or {}).get("verified"),
        "note": "Geometric estimate only. Required carry is measured from the current GPS position to the far water edge along the green-center line; actual shot direction, elevation, wind, and safety margin are not included.",
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Calculate distances from a GPS position to a golf hole's "
            "green and mapped course features."
        )
    )

    parser.add_argument(
        "--model",
        default="course_model.json",
        help="Course model JSON file",
    )
    parser.add_argument(
        "--hole",
        type=int,
        required=True,
        help="Hole number (1-18)",
    )
    parser.add_argument(
        "--lat",
        type=float,
        required=True,
        help="Current GPS latitude",
    )
    parser.add_argument(
        "--lon",
        type=float,
        required=True,
        help="Current GPS longitude",
    )
    parser.add_argument(
        "--radius",
        type=float,
        default=200.0,
        help=(
            "Include non-green features within this distance, "
            "in the selected unit (default: 200)"
        ),
    )
    parser.add_argument(
        "--unit",
        choices=("yards", "meters", "feet"),
        default="yards",
        help="Output distance unit (default: yards)",
    )
    parser.add_argument(
        "--bearing",
        type=float,
        default=None,
        help=(
            "Optional shot bearing in degrees clockwise from true north "
            "(0=north, 90=east, 180=south, 270=west). Overrides the "
            "default line toward the green center for water-carry calculations."
        ),
    )
    parser.add_argument(
        "--shot-distance",
        type=float,
        default=None,
        help=(
            "Maximum distance to evaluate along --bearing, in the selected unit. "
            "Defaults to the distance to the green center when available, "
            "otherwise 300 yards."
        ),
    )
    parser.add_argument(
        "--all-features",
        action="store_true",
        help="Show all mapped non-path features on the selected hole",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Print machine-readable JSON instead of a human-readable report",
    )

    args = parser.parse_args()

    if not 1 <= args.hole <= 18:
        parser.error("--hole must be between 1 and 18")

    if not -90 <= args.lat <= 90:
        parser.error("--lat must be between -90 and 90")

    if not -180 <= args.lon <= 180:
        parser.error("--lon must be between -180 and 180")

    if args.radius < 0:
        parser.error("--radius cannot be negative")

    if args.bearing is not None and not 0 <= args.bearing < 360:
        parser.error("--bearing must be >= 0 and < 360 degrees")

    if args.shot_distance is not None and args.shot_distance <= 0:
        parser.error("--shot-distance must be greater than 0")

    if args.shot_distance is not None and args.bearing is None:
        parser.error("--shot-distance requires --bearing")

    model_path = Path(args.model)

    if not model_path.is_file():
        parser.error(f"Model file not found: {model_path}")

    try:
        with model_path.open("r", encoding="utf-8") as file:
            model = json.load(file)
    except json.JSONDecodeError as exc:
        parser.error(f"Model file is not valid JSON: {exc}")
    except OSError as exc:
        parser.error(f"Could not read model file: {exc}")

    features = get_hole_features(model, args.hole)

    if not features:
        parser.error(
            f"No features are associated with hole {args.hole}. "
            "This hole may be missing from the current dataset."
        )

    measured = []

    for feature in features:
        category = classify_feature(feature)

        # Paths and playing-direction lines are not obstacles to report.
        if category in ("path", "playing_line"):
            continue

        geometry = feature.get("geometry")
        distance_m, nearest = distance_to_geometry_m(
            args.lat, args.lon, geometry
        )

        # Fall back to a representative point if geometry is unavailable.
        if distance_m is None:
            point = feature_anchor(feature)

            if point is None:
                continue

            distance_m = haversine_m(
                args.lat, args.lon, point[0], point[1]
            )
            nearest = point

        props = feature.get("properties") or {}
        geometry_type = (geometry or {}).get("type")
        geometry_role = props.get("geometry_role")
        is_reference_point = (
            category in ("water", "hazard")
            and geometry_type == "Point"
            and (
                geometry_role == "reference_point_only_not_water_boundary"
                or props.get("source") == "osm_reference_point"
            )
        )
        is_verified = props.get("verified")

        item = {
            "id": feature.get("id"),
            "name": feature_name(feature),
            "category": category,
            "distance": round_distance(
                distance_value(distance_m, args.unit)
            ),
            "distance_type": (
                "distance_to_reference_point_not_hazard_edge"
                if is_reference_point
                else "distance_to_mapped_geometry"
                if geometry_type in ("Polygon", "MultiPolygon", "LineString", "MultiLineString")
                else "distance_to_mapped_point"
            ),
            "verified": is_verified,
            "distance_note": (
                "Reference-point distance only; this is NOT the distance to the water edge."
                if is_reference_point
                else "Distance is to the nearest mapped water boundary; the boundary is unverified."
                if category == "water"
                and geometry_type in ("Polygon", "MultiPolygon")
                and is_verified is False
                else "Feature is marked unverified in the source data."
                if is_verified is False and category in ("water", "hazard", "bunker")
                else None
            ),
            "unit": args.unit,
            "nearest_point": (
                {
                    "latitude": round(nearest[0], 7),
                    "longitude": round(nearest[1], 7),
                }
                if nearest else None
            ),
            "distance_method": (
                "inside_or_nearest_polygon_boundary"
                if (geometry or {}).get("type")
                in ("Polygon", "MultiPolygon")
                else "nearest_geometry_or_representative_point"
            ),
        }

        measured.append(item)

    greens = [
        feature for feature in features
        if classify_feature(feature) == "green"
    ]

    green_result = None

    if greens:
        # Prefer the green closest to the golfer.
        green_candidates = []

        for green in greens:
            distance_m, _ = distance_to_geometry_m(
                args.lat, args.lon, green.get("geometry")
            )

            if distance_m is None:
                anchor = feature_anchor(green)

                if anchor:
                    distance_m = haversine_m(
                        args.lat, args.lon, anchor[0], anchor[1]
                    )

            if distance_m is not None:
                green_candidates.append((distance_m, green))

        if green_candidates:
            _, selected_green = min(
                green_candidates, key=lambda item: item[0]
            )

            measurements = green_measurements(
                args.lat,
                args.lon,
                selected_green,
                features,
            )

            green_distance_m, nearest_green_point = distance_to_geometry_m(
                args.lat, args.lon, selected_green.get("geometry")
            )

            if green_distance_m is None:
                green_distance_m = measurements["front"]

            green_result = {
                "id": selected_green.get("id"),
                "name": feature_name(selected_green),
                "category": "green",
                # Retain the nearest polygon-boundary distance separately.
                "distance": (
                    round_distance(
                        distance_value(green_distance_m, args.unit)
                    )
                    if green_distance_m is not None else None
                ),
                "front": (
                    round_distance(
                        distance_value(measurements["front"], args.unit)
                    )
                    if measurements["front"] is not None else None
                ),
                "center": (
                    round_distance(
                        distance_value(measurements["center"], args.unit)
                    )
                    if measurements["center"] is not None else None
                ),
                "back": (
                    round_distance(
                        distance_value(measurements["back"], args.unit)
                    )
                    if measurements["back"] is not None else None
                ),
                "nearest_point": (
                    {
                        "latitude": round(nearest_green_point[0], 7),
                        "longitude": round(nearest_green_point[1], 7),
                    }
                    if nearest_green_point else None
                ),
                "front_point": (
                    {
                        "latitude": round(
                            measurements["front_point"][0], 7
                        ),
                        "longitude": round(
                            measurements["front_point"][1], 7
                        ),
                    }
                    if measurements["front_point"] else None
                ),
                "center_point": (
                    {
                        "latitude": round(
                            measurements["center_point"][0], 7
                        ),
                        "longitude": round(
                            measurements["center_point"][1], 7
                        ),
                    }
                    if measurements.get("center_point") else None
                ),
                "back_point": (
                    {
                        "latitude": round(
                            measurements["back_point"][0], 7
                        ),
                        "longitude": round(
                            measurements["back_point"][1], 7
                        ),
                    }
                    if measurements["back_point"] else None
                ),
                "direction_method": measurements["direction_method"],
                "unit": args.unit,
            }

    # Estimate water carry toward the green center by default, or along a
    # user-selected bearing (clockwise from true north).
    water_carries = []
    green_center_point = None
    if green_result and green_result.get("center_point"):
        cp = green_result["center_point"]
        green_center_point = (cp["latitude"], cp["longitude"])

    target_point = green_center_point
    direction_label = "straight line toward green center"

    direction_to_green = None
    if green_center_point is not None:
        bearing_to_green = initial_bearing_degrees(
            args.lat, args.lon, green_center_point[0], green_center_point[1]
        )
        direction_to_green = {
            "label": compass_direction(bearing_to_green),
            "bearing_degrees": round(bearing_to_green, 1),
            "target": "green center",
            "reference": "true north",
        }
        green_result["direction"] = direction_to_green
    if args.bearing is not None:
        if args.shot_distance is not None:
            ray_distance_m = distance_m_from_unit(args.shot_distance, args.unit)
        elif green_center_point is not None:
            ray_distance_m = haversine_m(
                args.lat, args.lon, green_center_point[0], green_center_point[1]
            )
        else:
            ray_distance_m = distance_m_from_unit(300.0, "yards")
        bearing_rad = math.radians(args.bearing)
        east_m = math.sin(bearing_rad) * ray_distance_m
        north_m = math.cos(bearing_rad) * ray_distance_m
        target_lat = args.lat + math.degrees(north_m / EARTH_RADIUS_M)
        cos_lat = max(1e-8, math.cos(math.radians(args.lat)))
        target_lon = args.lon + math.degrees(east_m / (EARTH_RADIUS_M * cos_lat))
        target_point = (target_lat, target_lon)
        direction_label = f"user-selected bearing {args.bearing:g} degrees from true north"

    for feature in features:
        if classify_feature(feature) != "water":
            continue
        carry = water_carry_measurement(
            args.lat, args.lon, target_point, feature, args.unit
        )
        if carry is not None:
            carry["feature_id"] = feature.get("id")
            carry["name"] = feature_name(feature)
            carry["direction"] = direction_label
            carry["note"] = (
                "Geometric estimate only. Distances follow the selected straight-line "
                "direction; actual ball flight, elevation, wind, GPS error, and safety "
                "margin are not included. Required carry is the distance from the "
                "current GPS position to the far mapped water edge along this line."
            )
            water_carries.append(carry)
    water_carries.sort(key=lambda item: item["near_edge_distance"])

    radius = args.radius

    nearby = [
        item for item in measured
        if item["category"] != "green"
        and (
            args.all_features
            or item["distance"] <= radius
        )
    ]

    nearby.sort(key=lambda item: item["distance"])

    result = {
        "course": model.get("course"),
        "hole": args.hole,
        "golfer_position": {
            "latitude": args.lat,
            "longitude": args.lon,
        },
        "unit": args.unit,
        "nearby_radius": radius,
        "green": green_result,
        "direction_to_green": direction_to_green,
        "water_carry_estimates": water_carries,
        "nearby_features": nearby,
        "warnings": [],
    }

    if green_result is None:
        result["warnings"].append(
            "No green geometry is mapped for this hole."
        )

    if not any(item["category"] == "bunker" for item in measured):
        result["warnings"].append(
            "No bunker features are mapped for this hole."
        )

    if not any(
        item["category"] in ("water", "hazard")
        for item in measured
    ):
        result["warnings"].append(
            "No features categorized as water or hazard are mapped "
            "for this hole. Some hazards may still be classified as "
            "'other' because of incomplete source metadata."
        )

    reference_hazards = [
        item for item in measured
        if item["distance_type"] == "distance_to_reference_point_not_hazard_edge"
    ]
    if reference_hazards:
        result["warnings"].append(
            "One or more hazards are represented by reference points only. "
            "Their reported distances are to the marker, NOT to the hazard edge."
        )

    unverified_hazards = [
        item for item in measured
        if item["category"] in ("water", "hazard", "bunker")
        and item.get("verified") is False
        and item not in reference_hazards
    ]
    if unverified_hazards:
        result["warnings"].append(
            "Some mapped hazards/bunkers are marked unverified in the source data. "
            "Treat their locations and distances as approximate."
        )

    if (
        green_result
        and str(green_result.get("direction_method", "")).startswith("fallback")
    ):
        result["warnings"].append(
            "Neither the mapped primary playing line nor a usable mapped tee "
            "was available for the green direction estimate. Front/back values "
            "use a fallback method."
        )

    if args.json:
        print(json.dumps(result, indent=2))
        return 0

    print(f"Course: {result['course'] or 'Unknown'}")
    print(f"Hole: {args.hole}")
    print(f"GPS: {args.lat:.7f}, {args.lon:.7f}")
    print(f"Distances: {args.unit}")
    print()

    print("GREEN")

    if direction_to_green is not None:
        print(
            f"  Direction to green center: {direction_to_green['label']} "
            f"({direction_to_green['bearing_degrees']:.1f}° from true north)"
        )

    if green_result:
        if green_result["front"] is not None:
            print(
                f"  Front (tee-side edge estimate): "
                f"{green_result['front']:.1f} {args.unit}"
            )

        if green_result["center"] is not None:
            print(
                f"  Center (representative point): "
                f"{green_result['center']:.1f} {args.unit}"
            )

        if green_result["back"] is not None:
            print(
                f"  Back (far-side edge estimate): "
                f"{green_result['back']:.1f} {args.unit}"
            )

        if green_result["distance"] is not None:
            print(
                f"  Nearest green boundary: "
                f"{green_result['distance']:.1f} {args.unit}"
            )

        point = green_result.get("nearest_point")

        if point:
            print(
                f"  Nearest point: {point['latitude']:.7f}, "
                f"{point['longitude']:.7f}"
            )

        print(f"  Green: {green_result['name']}")
        print(
            "  Note: front/back prefer the mapped primary playing line, "
            "then the tee-to-green direction. Distances are estimates from mapped "
            "geometry, not the daily pin position."
        )
    else:
        print("  No green geometry found for this hole.")

    print()
    direction_heading = (
        f"bearing {args.bearing:g}° from true north"
        if args.bearing is not None
        else "straight line toward green center"
    )
    print(f"WATER CARRY ({direction_heading}; {args.unit})")
    if not water_carries:
        print("  No water polygon intersects the selected shot line.")
    else:
        for carry in water_carries:
            print(f"  {carry['name']}")
            print(f"    Near edge: {carry['near_edge_distance']:.1f} {args.unit} from current position")
            print(f"    Far edge / minimum carry: {carry['required_carry_to_clear']:.1f} {args.unit} from current position")
            print(f"    Water width along line: {carry['water_width_along_shot']:.1f} {args.unit}")
            print(f"    Note: {carry['note']}")

    print()
    print(f"NEARBY FEATURES (within {radius:g} {args.unit})")

    if not nearby:
        print("  No mapped features within the selected radius.")
    else:
        for item in nearby:
            print(
                f"  {item['distance']:>7.1f} {args.unit} | "
                f"{item['category']:<8} | {item['name']}"
            )
            if item.get("distance_note"):
                print(f"           NOTE: {item['distance_note']}")

    if result["warnings"]:
        print("\nWARNINGS")

        for warning in result["warnings"]:
            print(f"  - {warning}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
