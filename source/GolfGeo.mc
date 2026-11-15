import Toybox.Lang;
import Toybox.Math;

module GolfGeo {

    const EARTH_RADIUS_M = 6371008.8;
    const METERS_PER_YARD = 0.9144;
    const METERS_PER_FOOT = 0.3048;
    const BIG = 1000000000000000.0;

    // ---------------- basic helpers ----------------

    // Index lookup through a helper, so the compiler does not flag it as out of bounds.
    function arrAt(arr, i) {
        return arr[i];
    }

    function absf(v) {
        if (v < 0) { return -v; }
        return v;
    }

    function deg2rad(d) { return d * Math.PI / 180.0; }
    function rad2deg(r) { return r * 180.0 / Math.PI; }
    function hypot(x, y) { return Math.sqrt(x * x + y * y); }

    function dget(d, key) {
        if (d instanceof Lang.Dictionary && d.hasKey(key)) { return d[key]; }
        return null;
    }

    // Category name as a plain string, or "" if missing.
    function catName(f) {
        var c = dget(f, "category");
        if (c == null) { return ""; }
        return c.toString();
    }

    function isCat(f, name) {
        return catName(f).equals(name);
    }

    function toF(v) {
        if (v instanceof Lang.Float || v instanceof Lang.Double
            || v instanceof Lang.Number || v instanceof Lang.Long) {
            return v.toFloat();
        }
        return null;
    }

    function r1(v) { return Math.round(v * 10.0) / 10.0; }

    function toUnit(m, unit) {
        if (unit == "meters") { return m; }
        if (unit == "feet") { return m / METERS_PER_FOOT; }
        return m / METERS_PER_YARD;
    }

    // Formats a value to one decimal place, e.g. 152.3
    function fmt1(v) {
        if (v == null) { return "--"; }
        var n = Math.round(v * 10.0);
        var sign = "";
        if (n < 0) { sign = "-"; n = -n; }
        return sign + (n / 10).toString() + "." + (n % 10).toString();
    }

    function sortNumbers(arr) {
        for (var i = 1; i < arr.size(); i++) {
            var cur = arr[i];
            var j = i - 1;
            while (j >= 0 && arr[j] > cur) { arr[j + 1] = arr[j]; j--; }
            arr[j + 1] = cur;
        }
    }

    function sortByKey(arr, key) {
        for (var i = 1; i < arr.size(); i++) {
            var cur = arr[i];
            var j = i - 1;
            while (j >= 0 && arr[j][key] > cur[key]) { arr[j + 1] = arr[j]; j--; }
            arr[j + 1] = cur;
        }
    }

    // ---------------- geodesy ----------------

    function haversine(lat1, lon1, lat2, lon2) {
        var p1 = deg2rad(lat1);
        var p2 = deg2rad(lat2);
        var s1 = Math.sin(deg2rad(lat2 - lat1) / 2.0);
        var s2 = Math.sin(deg2rad(lon2 - lon1) / 2.0);
        var a = s1 * s1 + Math.cos(p1) * Math.cos(p2) * s2 * s2;
        if (a > 1.0) { a = 1.0; }
        return 2.0 * EARTH_RADIUS_M * Math.asin(Math.sqrt(a));
    }

    function initialBearing(lat1, lon1, lat2, lon2) {
        var p1 = deg2rad(lat1);
        var p2 = deg2rad(lat2);
        var dl = deg2rad(lon2 - lon1);
        var y = Math.sin(dl) * Math.cos(p2);
        var x = Math.cos(p1) * Math.sin(p2) - Math.sin(p1) * Math.cos(p2) * Math.cos(dl);
        var b = rad2deg(Math.atan2(y, x));
        while (b < 0.0) { b += 360.0; }
        return b;
    }

    function compassDirection(b) {
        var names = ["North", "Northeast", "East", "Southeast",
                     "South", "Southwest", "West", "Northwest"];
        var idx = Math.floor((b + 22.5) / 45.0).toNumber() % 8;
        return names[idx];
    }

    // Local east/north meters relative to an origin.
    function localXY(lat, lon, oLat, oLon) {
        var meanLat = deg2rad((lat + oLat) / 2.0);
        return [
            deg2rad(lon - oLon) * EARTH_RADIUS_M * Math.cos(meanLat),
            deg2rad(lat - oLat) * EARTH_RADIUS_M
        ];
    }

    function xyToLatLon(x, y, oLat, oLon) {
        var lat = oLat + rad2deg(y / EARTH_RADIUS_M);
        var c = Math.cos(deg2rad(oLat));
        var lon = oLon;
        if (absf(c) > 0.000000000001) {
            lon = oLon + rad2deg(x / (EARTH_RADIUS_M * c));
        }
        return [lat, lon];
    }

    // ---------------- geometry ----------------

    // GeoJSON [lon, lat] pairs -> array of [lat, lon] points.
    function ringPoints(ring) {
        var pts = [];
        if (ring instanceof Lang.Array) {
            for (var i = 0; i < ring.size(); i++) {
                var c = ring[i];
                if (c instanceof Lang.Array && c.size() >= 2) {
                    var lon = toF(c[0]);
                    var lat = toF(c[1]);
                    if (lon != null && lat != null) { pts.add([lat, lon]); }
                }
            }
        }
        return pts;
    }

    // Every ring of a geometry as arrays of [lat, lon].
    function geometryRings(geom) {
        var out = [];
        var kind = dget(geom, "type");
        var coords = dget(geom, "coordinates");
        if (!(coords instanceof Lang.Array)) { return out; }

        if (kind.equals("Polygon")) {
            for (var i = 0; i < coords.size(); i++) {
                var p = ringPoints(coords[i]);
                if (p.size() >= 3) { out.add(p); }
            }
        } else if (kind.equals("MultiPolygon")) {
            for (var i = 0; i < coords.size(); i++) {
                if (coords[i] instanceof Lang.Array) {
                    for (var k = 0; k < coords[i].size(); k++) {
                        var p2 = ringPoints(coords[i][k]);
                        if (p2.size() >= 3) { out.add(p2); }
                    }
                }
            }
        } else if (kind.equals("LineString")) {
            var l = ringPoints(coords);
            if (l.size() >= 2) { out.add(l); }
        } else if (kind.equals("Point")) {
            out.add(ringPoints([coords]));
        }
        return out;
    }

    // Polygon rings as arrays of [lat, lon] (outer ring first, then holes).
    function ringsFromPoly(poly) {
        var rings = [];
        for (var i = 0; i < poly.size(); i++) {
            var p = ringPoints(poly[i]);
            if (p.size() >= 3) { rings.add(p); }
        }
        return rings;
    }

    function polygonsOf(geom) {
        var out = [];
        var kind = dget(geom, "type");
        var coords = dget(geom, "coordinates");
        if (!(coords instanceof Lang.Array)) { return out; }

        if (kind.equals("Polygon")) {
            out.add(ringsFromPoly(coords));
        } else if (kind.equals("MultiPolygon")) {
            for (var i = 0; i < coords.size(); i++) {
                if (coords[i] instanceof Lang.Array) { out.add(ringsFromPoly(coords[i])); }
            }
        }
        return out;
    }

    // Outer ring of each polygon.
    function outerRings(geom) {
        var out = [];
        var polys = polygonsOf(geom);
        for (var i = 0; i < polys.size(); i++) {
            if (polys[i].size() > 0) { out.add(arrAt(polys[i], 0)); }
        }
        return out;
    }

    function flatten(rings) {
        var out = [];
        for (var i = 0; i < rings.size(); i++) {
            for (var k = 0; k < rings[i].size(); k++) { out.add(rings[i][k]); }
        }
        return out;
    }

    function averagePoint(pts) {
        var la = 0.0;
        var lo = 0.0;
        for (var i = 0; i < pts.size(); i++) {
            la += pts[i][0];
            lo += pts[i][1];
        }
        return [la / pts.size(), lo / pts.size()];
    }

    function ringToXY(ring, oLat, oLon) {
        var out = [];
        for (var i = 0; i < ring.size(); i++) {
            out.add(localXY(ring[i][0], ring[i][1], oLat, oLon));
        }
        return out;
    }

    function ringsToXY(rings, oLat, oLon) {
        var out = [];
        for (var i = 0; i < rings.size(); i++) {
            out.add(ringToXY(rings[i], oLat, oLon));
        }
        return out;
    }

    // ---------------- point in polygon and distance ----------------

    function pointInRingXY(px, py, ring) {
        var inside = false;
        var n = ring.size();
        var j = n - 1;
        for (var i = 0; i < n; i++) {
            var xi = ring[i][0];
            var yi = ring[i][1];
            var xj = ring[j][0];
            var yj = ring[j][1];
            var dy = yj - yi;
            if (dy == 0.0) { dy = 0.000000000000001; }
            if (((yi > py) && (yj <= py)) || ((yj > py) && (yi <= py))) {
                if (px < (xj - xi) * (py - yi) / dy + xi) { inside = !inside; }
            }
            j = i;
        }
        return inside;
    }

    function pointInPolygonXY(px, py, rings) {
        if (rings.size() == 0 || !pointInRingXY(px, py, arrAt(rings, 0))) { return false; }
        for (var i = 1; i < rings.size(); i++) {
            if (pointInRingXY(px, py, rings[i])) { return false; }
        }
        return true;
    }

    function insideGeom(lat, lon, geom) {
        var polys = polygonsOf(geom);
        for (var p = 0; p < polys.size(); p++) {
            if (pointInPolygonXY(0.0, 0.0, ringsToXY(polys[p], lat, lon))) { return true; }
        }
        return false;
    }

    // Returns [distance_m, nearest_lat, nearest_lon], or null if no geometry.
    function nearestOnGeometry(lat, lon, geom) {
        if (insideGeom(lat, lon, geom)) { return [0.0, lat, lon]; }

        var kind = dget(geom, "type");
        var closed = (kind.equals("Polygon") || kind.equals("MultiPolygon"));
        var rings = geometryRings(geom);
        var best = BIG;
        var bx = 0.0;
        var by = 0.0;
        var found = false;

        for (var r = 0; r < rings.size(); r++) {
            var xy = ringToXY(rings[r], lat, lon);
            var n = xy.size();
            if (n == 1) {
                var d0 = hypot(xy[0][0], xy[0][1]);
                if (d0 < best) { best = d0; bx = xy[0][0]; by = xy[0][1]; found = true; }
                continue;
            }
            var segs = n - 1;
            if (closed) { segs = n; }
            for (var s = 0; s < segs; s++) {
                var a = xy[s];
                var b = xy[(s + 1) % n];
                var dx = b[0] - a[0];
                var dy = b[1] - a[1];
                var len2 = dx * dx + dy * dy;
                var t = 0.0;
                if (len2 > 0.0) {
                    t = (-a[0] * dx - a[1] * dy) / len2;
                    if (t < 0.0) { t = 0.0; }
                    if (t > 1.0) { t = 1.0; }
                }
                var cx = a[0] + t * dx;
                var cy = a[1] + t * dy;
                var d = hypot(cx, cy);
                if (d < best) { best = d; bx = cx; by = cy; found = true; }
            }
        }

        if (!found) { return null; }
        var ll = xyToLatLon(bx, by, lat, lon);
        return [best, ll[0], ll[1]];
    }

    // ---------------- anchors ----------------

    function repPoint(f) {
        var rp = dget(f, "representative_point");
        var la = toF(dget(rp, "latitude"));
        var lo = toF(dget(rp, "longitude"));
        if (la == null || lo == null) { return null; }
        return [la, lo];
    }

    // Representative point of a feature, preferring a point inside the polygon.
    function featureAnchor(f) {
        var geom = dget(f, "geometry");
        var rp = repPoint(f);
        var outer = outerRings(geom);

        if (rp != null && (outer.size() == 0 || insideGeom(rp[0], rp[1], geom))) {
            return rp;
        }

        if (outer.size() > 0) {
            // Area centroid of the outer ring, used if it lies inside the polygon.
            var ring0 = arrAt(outer, 0);
            var o = averagePoint(ring0);
            var xy = ringToXY(ring0, o[0], o[1]);
            var n = xy.size();
            var twiceArea = 0.0;
            var sx = 0.0;
            var sy = 0.0;
            for (var i = 0; i < n; i++) {
                var a = xy[i];
                var b = xy[(i + 1) % n];
                var cr = a[0] * b[1] - b[0] * a[1];
                twiceArea += cr;
                sx += (a[0] + b[0]) * cr;
                sy += (a[1] + b[1]) * cr;
            }
            if (absf(twiceArea) > 0.000000001) {
                var c = xyToLatLon(sx / (3.0 * twiceArea), sy / (3.0 * twiceArea), o[0], o[1]);
                if (insideGeom(c[0], c[1], geom)) { return c; }
            }
            return averagePoint(flatten(outer));
        }

        var all = flatten(geometryRings(geom));
        if (all.size() > 0) { return averagePoint(all); }
        return rp;
    }

    // ---------------- playing line ----------------

    // Straight-line length of the primary playing line, in meters, or null.
    function playingLineLengthM(features) {
        for (var i = 0; i < features.size(); i++) {
            var f = features[i];
            if (!isCat(f, "playing_line")) { continue; }
            var pts = flatten(geometryRings(dget(f, "geometry")));
            if (pts.size() < 2) { continue; }
            var a = arrAt(pts, 0);
            var b = arrAt(pts, pts.size() - 1);
            return haversine(a[0], a[1], b[0], b[1]);
        }
        return null;
    }

    // ---------------- green direction ----------------

    // Tee-side endpoint of the primary playing line, nearest the green.
    function choosePlayingLineTee(features, anchor) {
        var best = null;
        var bestD = BIG;
        for (var i = 0; i < features.size(); i++) {
            var f = features[i];
            if (!isCat(f, "playing_line")) { continue; }

            var pts = flatten(geometryRings(dget(f, "geometry")));
            if (pts.size() < 2) { continue; }

            var first = arrAt(pts, 0);
            var last = arrAt(pts, pts.size() - 1);
            var dFirst = haversine(first[0], first[1], anchor[0], anchor[1]);
            var dLast = haversine(last[0], last[1], anchor[0], anchor[1]);

            // The endpoint nearer the green is the green side; the other is the tee side.
            var tee = first;
            var m = dLast;
            if (dFirst < dLast) {
                tee = last;
                m = dFirst;
            }
            if (m < bestD) { bestD = m; best = tee; }
        }
        return best;
    }

    function chooseTee(features, anchor) {
        var best = null;
        var bestD = BIG;
        for (var i = 0; i < features.size(); i++) {
            var f = features[i];
            if (!isCat(f, "tee")) { continue; }
            var a = featureAnchor(f);
            if (a == null) { continue; }
            var d = haversine(a[0], a[1], anchor[0], anchor[1]);
            if (d < bestD) { bestD = d; best = a; }
        }
        return best;
    }

    function fallbackMeasure(gLat, gLon, geom, pts, anchor, centerDist) {
        var front = centerDist;
        var nd = nearestOnGeometry(gLat, gLon, geom);
        if (nd != null) { front = nd[0]; }

        var far = 0.0;
        for (var i = 0; i < pts.size(); i++) {
            var d = haversine(gLat, gLon, pts[i][0], pts[i][1]);
            if (d > far) { far = d; }
        }

        return {
            "front" => front,
            "center" => centerDist,
            "back" => far,
            "center_point" => anchor,
            "method" => "fallback_without_mapped_tee"
        };
    }

    // Front, center, and back along the tee-to-green axis, measured from the golfer.
    function greenMeasurements(gLat, gLon, green, features) {
        var geom = dget(green, "geometry");
        var outer = outerRings(geom);
        var pts = flatten(outer);
        if (pts.size() == 0) { pts = flatten(geometryRings(geom)); }
        if (pts.size() == 0) { return null; }

        var anchor = featureAnchor(green);
        if (anchor == null) { return null; }
        var centerDist = haversine(gLat, gLon, anchor[0], anchor[1]);

        var tee = choosePlayingLineTee(features, anchor);
        var method = "playing_line_axis_estimate";
        if (tee == null) {
            tee = chooseTee(features, anchor);
            method = "tee_to_green_axis_estimate";
        }
        if (tee == null) {
            return fallbackMeasure(gLat, gLon, geom, pts, anchor, centerDist);
        }

        var g = localXY(anchor[0], anchor[1], tee[0], tee[1]);
        var axLen = hypot(g[0], g[1]);
        if (axLen < 0.01) {
            return fallbackMeasure(gLat, gLon, geom, pts, anchor, centerDist);
        }
        var ax = g[0] / axLen;
        var ay = g[1] / axLen;

        // Front = smallest projection on the axis, back = largest.
        var minP = BIG;
        var maxP = -BIG;
        var frontPt = arrAt(pts, 0);
        var backPt = arrAt(pts, 0);
        for (var i = 0; i < pts.size(); i++) {
            var xy = localXY(pts[i][0], pts[i][1], tee[0], tee[1]);
            var p = xy[0] * ax + xy[1] * ay;
            if (p < minP) { minP = p; frontPt = pts[i]; }
            if (p > maxP) { maxP = p; backPt = pts[i]; }
        }

        // Cross-section at the midpoint of the front-to-back span.
        var cp = (minP + maxP) / 2.0;
        var lats = [];
        for (var r = 0; r < outer.size(); r++) {
            var ring = ringToXY(arrAt(outer, r), tee[0], tee[1]);
            var n = ring.size();
            for (var j = 0; j < n; j++) {
                var a = ring[j];
                var b = ring[(j + 1) % n];
                var p1 = a[0] * ax + a[1] * ay;
                var p2 = b[0] * ax + b[1] * ay;
                var l1 = -a[0] * ay + a[1] * ax;
                var l2 = -b[0] * ay + b[1] * ax;
                if (absf(p1 - cp) < 0.0000001) { lats.add(l1); }
                if ((p1 < cp && cp < p2) || (p2 < cp && cp < p1)) {
                    var f = (cp - p1) / (p2 - p1);
                    lats.add(l1 + f * (l2 - l1));
                }
            }
        }

        var cl = 0.0;
        if (lats.size() >= 2) {
            var lo = arrAt(lats, 0);
            var hi = arrAt(lats, 0);
            for (var q = 1; q < lats.size(); q++) {
                if (lats[q] < lo) { lo = lats[q]; }
                if (lats[q] > hi) { hi = lats[q]; }
            }
            cl = (lo + hi) / 2.0;
        } else {
            var ap = localXY(anchor[0], anchor[1], tee[0], tee[1]);
            cl = -ap[0] * ay + ap[1] * ax;
        }

        var cx = cp * ax - cl * ay;
        var cy = cp * ay + cl * ax;
        var cpt = xyToLatLon(cx, cy, tee[0], tee[1]);

        return {
            "front" => haversine(gLat, gLon, frontPt[0], frontPt[1]),
            "center" => haversine(gLat, gLon, cpt[0], cpt[1]),
            "back" => haversine(gLat, gLon, backPt[0], backPt[1]),
            "center_point" => cpt,
            "method" => method
        };
    }

    // ---------------- water carry ----------------

    // Meters along the golfer-to-target ray where it crosses polygon edges.
    function rayHits(oLat, oLon, tLat, tLon, polys) {
        var hits = [];
        var t = localXY(tLat, tLon, oLat, oLon);
        var rl = hypot(t[0], t[1]);
        if (rl < 0.01) { return hits; }
        var dx = t[0] / rl;
        var dy = t[1] / rl;

        for (var p = 0; p < polys.size(); p++) {
            for (var r = 0; r < polys[p].size(); r++) {
                var xy = ringToXY(polys[p][r], oLat, oLon);
                var n = xy.size();
                for (var e = 0; e < n; e++) {
                    var a = xy[e];
                    var b = xy[(e + 1) % n];
                    var sx = b[0] - a[0];
                    var sy = b[1] - a[1];
                    var den = dx * sy - dy * sx;
                    if (absf(den) < 0.000000001) { continue; }
                    var tt = (a[0] * sy - a[1] * sx) / den;
                    var uu = (a[0] * dy - a[1] * dx) / den;
                    if (tt >= -0.01 && uu >= -0.000000001 && uu <= 1.000000001) {
                        if (tt < 0.0) { tt = 0.0; }
                        hits.add(tt);
                    }
                }
            }
        }

        sortNumbers(hits);
        var out = [];
        for (var h = 0; h < hits.size(); h++) {
            if (out.size() == 0 || absf(hits[h] - arrAt(out, out.size() - 1)) > 0.25) {
                out.add(hits[h]);
            }
        }
        return out;
    }

    function waterCarry(gLat, gLon, target, water, unit) {
        var geom = dget(water, "geometry");
        var tDist = haversine(gLat, gLon, target[0], target[1]);
        if (tDist < 1.0) { return null; }

        var all = rayHits(gLat, gLon, target[0], target[1], polygonsOf(geom));
        var hits = [];
        for (var i = 0; i < all.size(); i++) {
            if (all[i] <= tDist + 1.0) { hits.add(all[i]); }
        }

        var near = 0.0;
        var far = 0.0;
        if (insideGeom(gLat, gLon, geom)) {
            if (hits.size() == 0) { return null; }
            far = arrAt(hits, 0);
        } else {
            if (hits.size() < 2) { return null; }
            near = arrAt(hits, 0);
            far = arrAt(hits, 1);
        }

        var width = far - near;
        if (width < 0.0) { width = 0.0; }

        return {
            "near" => r1(toUnit(near, unit)),
            "far" => r1(toUnit(far, unit)),
            "width" => r1(toUnit(width, unit)),
            "verified" => dget(dget(water, "properties"), "verified")
        };
    }

    // ---------------- main analysis ----------------

    // model is one hole file: {"hole_number": n, "features": [...]}
    function analyze(model, lat, lon, radius, unit, showAll) {
        var result = {
            "green" => null,
            "direction" => null,
            "water" => [],
            "nearby" => [],
            "warnings" => []
        };

        var features = dget(model, "features");
        if (!(features instanceof Lang.Array) || features.size() == 0) {
            result["warnings"].add("No mapped features for this hole.");
            return result;
        }

        // Closest green to the golfer.
        var green = null;
        var gBest = BIG;
        for (var i = 0; i < features.size(); i++) {
            var f = features[i];
            if (!isCat(f, "green")) { continue; }
            var nd = nearestOnGeometry(lat, lon, dget(f, "geometry"));
            if (nd != null && nd[0] < gBest) { gBest = nd[0]; green = f; }
        }

        var center = null;
        if (green != null) {
            var m = greenMeasurements(lat, lon, green, features);
            if (m != null) {
                center = m["center_point"];
                result["green"] = {
                    "front" => r1(toUnit(m["front"], unit)),
                    "center" => r1(toUnit(m["center"], unit)),
                    "back" => r1(toUnit(m["back"], unit)),
                    "method" => m["method"]
                };
                var b = initialBearing(lat, lon, center[0], center[1]);
                result["direction"] = {
                    "label" => compassDirection(b),
                    "bearing" => r1(b)
                };
                if (m["method"] == "fallback_without_mapped_tee") {
                    result["warnings"].add("No mapped tee or playing line; front and back are approximate.");
                }
            }
        } else {
            result["warnings"].add("No green is mapped for this hole.");
        }

        // Water carries along the line to the green center.
        if (center != null) {
            for (var w = 0; w < features.size(); w++) {
                var wf = features[w];
                if (!isCat(wf, "water")) { continue; }
                var carry = waterCarry(lat, lon, center, wf, unit);
                if (carry != null) { result["water"].add(carry); }
            }
            sortByKey(result["water"], "near");
        }

        // Nearby non-green features within the radius.
        var nearby = [];
        var anyUnverified = false;
        var anyReferenceOnly = false;
        for (var k = 0; k < features.size(); k++) {
            var f2 = features[k];
            var cat = catName(f2);
            if (cat.equals("green") || cat.equals("playing_line")) { continue; }

            var nd2 = nearestOnGeometry(lat, lon, dget(f2, "geometry"));
            if (nd2 == null) { continue; }
            var dist = r1(toUnit(nd2[0], unit));
            if (!showAll && dist > radius) { continue; }

            var props = dget(f2, "properties");
            var verified = dget(props, "verified");
            if (verified == false && (cat.equals("water") || cat.equals("hazard") || cat.equals("bunker"))) {
                anyUnverified = true;
            }
            if (dget(props, "geometry_role") == "reference_point_only_not_water_boundary") {
                anyReferenceOnly = true;
            }
            nearby.add({ "category" => cat, "distance" => dist, "verified" => verified });
        }
        sortByKey(nearby, "distance");
        result["nearby"] = nearby;

        if (anyUnverified) {
            result["warnings"].add("Some water, hazard, or bunker features are unverified; treat their distances as approximate.");
        }
        if (anyReferenceOnly) {
            result["warnings"].add("Some hazards are reference points only; distances are to the marker, not the edge.");
        }

        return result;
    }
}