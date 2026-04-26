#!/bin/bash
set -e

#############################################################################
# Setup script for Building Detection demo - Nicolás Romero, Estado de México
#
# This script:
# 1. Installs required tools (osmium, tippecanoe, gdal)
# 2. Downloads OSM building data and converts to .mbtiles
# 3. Downloads satellite imagery (ESRI World Imagery tiles → GeoTIFF)
# 4. Generates AOI files based on building density
# 5. Configures the experiment for Nicolás Romero
#############################################################################

# === Configuration ===
export IDB_DATA_DIR="${IDB_DATA_DIR:-$HOME/building-detection-data}"
BBOX_WEST=-99.36
BBOX_EAST=-99.26
BBOX_SOUTH=19.56
BBOX_NORTH=19.64
CITY="nicolas-romero"
ZOOM=17  # ~1.2m/pixel at this latitude

echo "=================================================="
echo "Building Detection - Nicolás Romero Setup"
echo "=================================================="
echo "Data dir: ${IDB_DATA_DIR}"
echo "BBox: ${BBOX_WEST},${BBOX_SOUTH},${BBOX_EAST},${BBOX_NORTH}"
echo ""

# === Step 0: Create directory structure ===
echo "[0/5] Creating directory structure..."
mkdir -p "${IDB_DATA_DIR}/input/${CITY}/imagery"
mkdir -p "${IDB_DATA_DIR}/input/${CITY}/aois"
mkdir -p "${IDB_DATA_DIR}/input/vector-tiles"
mkdir -p "${IDB_DATA_DIR}/rv"

# === Step 1: Install dependencies ===
echo "[1/5] Installing dependencies..."

if ! command -v osmium &> /dev/null; then
    echo "  Installing osmium-tool..."
    brew install osmium-tool
fi

if ! command -v tippecanoe &> /dev/null; then
    echo "  Installing tippecanoe..."
    brew install tippecanoe
fi

if ! command -v gdal_translate &> /dev/null; then
    echo "  Installing GDAL..."
    brew install gdal
fi

if ! command -v python3 &> /dev/null; then
    echo "  Installing python3..."
    brew install python3
fi

# Python dependencies for imagery download
pip3 install --quiet requests numpy 2>/dev/null || pip install --quiet requests numpy 2>/dev/null

echo "  All dependencies installed."

# === Step 2: Download OSM building data ===
echo "[2/5] Downloading OSM building data via Overpass API..."

OVERPASS_QUERY="[out:json][timeout:120];
(
  way[building](${BBOX_SOUTH},${BBOX_WEST},${BBOX_NORTH},${BBOX_EAST});
  relation[building](${BBOX_SOUTH},${BBOX_WEST},${BBOX_NORTH},${BBOX_EAST});
);
out geom;"

BUILDINGS_JSON="${IDB_DATA_DIR}/input/${CITY}/osm_buildings_raw.json"
BUILDINGS_GEOJSON="${IDB_DATA_DIR}/input/${CITY}/buildings.geojson"

if [ ! -f "${BUILDINGS_GEOJSON}" ]; then
    echo "  Querying Overpass API..."
    curl -s 'https://overpass-api.de/api/interpreter' \
        --data-urlencode "data=${OVERPASS_QUERY}" \
        -o "${BUILDINGS_JSON}"

    BUILDING_COUNT=$(python3 -c "
import json
with open('${BUILDINGS_JSON}') as f:
    data = json.load(f)
elements = data.get('elements', [])
print(len(elements))
")
    echo "  Found ${BUILDING_COUNT} buildings in OSM."

    # Convert Overpass JSON to GeoJSON
    echo "  Converting to GeoJSON..."
    python3 << 'PYEOF'
import json
import sys

input_path = sys.argv[1] if len(sys.argv) > 1 else "${BUILDINGS_JSON}"
output_path = sys.argv[2] if len(sys.argv) > 2 else "${BUILDINGS_GEOJSON}"

with open("${BUILDINGS_JSON}") as f:
    data = json.load(f)

features = []
for el in data.get("elements", []):
    if el["type"] == "way" and "geometry" in el:
        coords = [[pt["lon"], pt["lat"]] for pt in el["geometry"]]
        # Close the ring if needed
        if coords[0] != coords[-1]:
            coords.append(coords[0])
        feature = {
            "type": "Feature",
            "properties": {
                "@id": f"way/{el['id']}",
                "building": el.get("tags", {}).get("building", "yes")
            },
            "geometry": {
                "type": "Polygon",
                "coordinates": [coords]
            }
        }
        features.append(feature)

geojson = {
    "type": "FeatureCollection",
    "features": features
}

with open("${BUILDINGS_GEOJSON}", "w") as f:
    json.dump(geojson, f)

print(f"  Converted {len(features)} building polygons to GeoJSON")
PYEOF
else
    echo "  buildings.geojson already exists, skipping."
fi

# === Step 3: Convert to MBTiles ===
echo "[3/5] Converting buildings to vector tiles (.mbtiles)..."

MBTILES_PATH="${IDB_DATA_DIR}/input/vector-tiles/mexico.mbtiles"

if [ ! -f "${MBTILES_PATH}" ]; then
    tippecanoe \
        --output="${MBTILES_PATH}" \
        --layer=osm \
        --minimum-zoom=12 \
        --maximum-zoom=14 \
        --no-feature-limit \
        --no-tile-size-limit \
        --force \
        "${BUILDINGS_GEOJSON}"
    echo "  Created ${MBTILES_PATH}"
else
    echo "  mexico.mbtiles already exists, skipping."
fi

# Note: Raster Vision expects .mbtiles.gz
if [ ! -f "${MBTILES_PATH}.gz" ]; then
    echo "  Compressing to .mbtiles.gz..."
    gzip -k "${MBTILES_PATH}"
fi

# === Step 4: Download satellite imagery ===
echo "[4/5] Downloading satellite imagery (ESRI World Imagery)..."

IMAGERY_PATH="${IDB_DATA_DIR}/input/${CITY}/imagery/${CITY}.tif"

if [ ! -f "${IMAGERY_PATH}" ]; then
    python3 << 'PYEOF'
import math
import os
import struct
import urllib.request
import json

# Configuration
bbox_west, bbox_south, bbox_east, bbox_north = -99.36, 19.56, -99.26, 19.64
zoom = 17
output_dir = os.path.expanduser("${IDB_DATA_DIR}/input/nicolas-romero/imagery")
tiles_dir = os.path.join(output_dir, "tiles")
os.makedirs(tiles_dir, exist_ok=True)

def lat_lon_to_tile(lat, lon, zoom):
    n = 2 ** zoom
    x = int((lon + 180.0) / 360.0 * n)
    lat_rad = math.radians(lat)
    y = int((1.0 - math.log(math.tan(lat_rad) + 1.0/math.cos(lat_rad)) / math.pi) / 2.0 * n)
    return x, y

# Calculate tile range
x_min, y_min = lat_lon_to_tile(bbox_north, bbox_west, zoom)
x_max, y_max = lat_lon_to_tile(bbox_south, bbox_east, zoom)

total_tiles = (x_max - x_min + 1) * (y_max - y_min + 1)
print(f"  Tile range: x={x_min}-{x_max}, y={y_min}-{y_max} ({total_tiles} tiles at zoom {zoom})")

if total_tiles > 5000:
    print(f"  WARNING: {total_tiles} tiles is a lot. Consider reducing bbox or zoom level.")

# Download tiles
downloaded = 0
failed = 0
for y in range(y_min, y_max + 1):
    for x in range(x_min, x_max + 1):
        tile_path = os.path.join(tiles_dir, f"{zoom}_{x}_{y}.jpg")
        if os.path.exists(tile_path) and os.path.getsize(tile_path) > 100:
            downloaded += 1
            continue
        # ESRI World Imagery tile URL
        url = f"https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{zoom}/{y}/{x}"
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "BuildingDetection/1.0"})
            with urllib.request.urlopen(req, timeout=30) as resp:
                with open(tile_path, "wb") as f:
                    f.write(resp.read())
            downloaded += 1
        except Exception as e:
            failed += 1
            if failed <= 3:
                print(f"  Failed tile {x},{y}: {e}")

    # Progress
    row_done = (y - y_min + 1) * (x_max - x_min + 1)
    pct = row_done / total_tiles * 100
    if (y - y_min) % 10 == 0:
        print(f"  Progress: {pct:.0f}% ({downloaded} downloaded, {failed} failed)")

print(f"  Download complete: {downloaded} tiles, {failed} failed")

# Save tile info for GDAL merge
info = {
    "zoom": zoom,
    "x_min": x_min, "x_max": x_max,
    "y_min": y_min, "y_max": y_max,
    "bbox": [bbox_west, bbox_south, bbox_east, bbox_north],
    "tiles_dir": tiles_dir
}
with open(os.path.join(output_dir, "tiles_info.json"), "w") as f:
    json.dump(info, f, indent=2)

print("  Tile info saved. Run gdal_merge to create GeoTIFF.")
PYEOF

    # Now merge tiles into GeoTIFF using GDAL
    echo "  Merging tiles into GeoTIFF with GDAL..."
    python3 << 'PYEOF'
import json
import math
import subprocess
import os

output_dir = os.path.expanduser("${IDB_DATA_DIR}/input/nicolas-romero/imagery")
info_path = os.path.join(output_dir, "tiles_info.json")

with open(info_path) as f:
    info = json.load(f)

zoom = info["zoom"]
x_min, x_max = info["x_min"], info["x_max"]
y_min, y_max = info["y_min"], info["y_max"]
tiles_dir = info["tiles_dir"]
n = 2 ** zoom

def tile_to_lat_lon(x, y, zoom):
    n = 2 ** zoom
    lon = x / n * 360.0 - 180.0
    lat_rad = math.atan(math.sinh(math.pi * (1 - 2 * y / n)))
    lat = math.degrees(lat_rad)
    return lat, lon

# Create a VRT for each tile with proper georeferencing
vrt_entries = []
tile_files = []

for y in range(y_min, y_max + 1):
    for x in range(x_min, x_max + 1):
        tile_path = os.path.join(tiles_dir, f"{zoom}_{x}_{y}.jpg")
        if not os.path.exists(tile_path) or os.path.getsize(tile_path) < 100:
            continue

        # Calculate bounds for this tile
        lat_top, lon_left = tile_to_lat_lon(x, y, zoom)
        lat_bottom, lon_right = tile_to_lat_lon(x + 1, y + 1, zoom)

        # Create individual GeoTIFF with world file
        tfw_path = tile_path.replace(".jpg", ".jgw")
        pixel_width = (lon_right - lon_left) / 256
        pixel_height = (lat_bottom - lat_top) / 256  # negative

        with open(tfw_path, "w") as f:
            f.write(f"{pixel_width}\n")
            f.write("0.0\n")
            f.write("0.0\n")
            f.write(f"{pixel_height}\n")
            f.write(f"{lon_left + pixel_width/2}\n")
            f.write(f"{lat_top + pixel_height/2}\n")

        tile_files.append(tile_path)

print(f"  Created world files for {len(tile_files)} tiles")
print(f"  Merging with gdal_merge.py...")

# Use gdal_merge to combine all tiles
output_tif = os.path.join(output_dir, "nicolas-romero.tif")

# Write file list
filelist_path = os.path.join(output_dir, "tile_list.txt")
with open(filelist_path, "w") as f:
    for tp in tile_files:
        f.write(tp + "\n")

cmd = [
    "gdal_merge.py",
    "-o", output_tif,
    "-of", "GTiff",
    "-co", "COMPRESS=LZW",
    "-co", "TILED=YES",
    "-a_srs", "EPSG:4326",
    "--optfile", filelist_path
]

result = subprocess.run(cmd, capture_output=True, text=True)
if result.returncode == 0:
    print(f"  SUCCESS: Created {output_tif}")
    # Get file size
    size_mb = os.path.getsize(output_tif) / (1024*1024)
    print(f"  File size: {size_mb:.1f} MB")
else:
    print(f"  gdal_merge failed: {result.stderr}")
    print("  Trying alternative method with gdalbuildvrt...")
    vrt_path = os.path.join(output_dir, "tiles.vrt")
    cmd2 = ["gdalbuildvrt", "-input_file_list", filelist_path, vrt_path]
    result2 = subprocess.run(cmd2, capture_output=True, text=True)
    if result2.returncode == 0:
        cmd3 = ["gdal_translate", "-of", "GTiff", "-co", "COMPRESS=LZW",
                 "-co", "TILED=YES", vrt_path, output_tif]
        result3 = subprocess.run(cmd3, capture_output=True, text=True)
        if result3.returncode == 0:
            size_mb = os.path.getsize(output_tif) / (1024*1024)
            print(f"  SUCCESS (via VRT): Created {output_tif} ({size_mb:.1f} MB)")
        else:
            print(f"  gdal_translate failed: {result3.stderr}")
    else:
        print(f"  gdalbuildvrt failed: {result2.stderr}")
PYEOF
else
    echo "  Imagery already exists, skipping."
fi

# === Step 5: Generate AOI GeoJSON files ===
echo "[5/5] Generating AOI files..."

python3 << 'PYEOF'
import json
import os

aoi_dir = os.path.expanduser("${IDB_DATA_DIR}/input/nicolas-romero/aois")
os.makedirs(aoi_dir, exist_ok=True)

# Nicolás Romero urban areas - training and validation AOIs
# These cover the denser urban areas where OSM has better building coverage
aois = {
    "train-aoi1.geojson": {
        "name": "Centro Urbano - Train 1",
        "coords": [[-99.335, 19.595], [-99.315, 19.595], [-99.315, 19.580], [-99.335, 19.580], [-99.335, 19.595]]
    },
    "train-aoi2.geojson": {
        "name": "Zona Oriente - Train 2",
        "coords": [[-99.310, 19.590], [-99.290, 19.590], [-99.290, 19.575], [-99.310, 19.575], [-99.310, 19.590]]
    },
    "val-aoi1.geojson": {
        "name": "Zona Sur - Validation",
        "coords": [[-99.325, 19.575], [-99.305, 19.575], [-99.305, 19.560], [-99.325, 19.560], [-99.325, 19.575]]
    }
}

for filename, aoi in aois.items():
    geojson = {
        "type": "FeatureCollection",
        "features": [{
            "type": "Feature",
            "properties": {"name": aoi["name"]},
            "geometry": {
                "type": "Polygon",
                "coordinates": [aoi["coords"]]
            }
        }]
    }
    path = os.path.join(aoi_dir, filename)
    with open(path, "w") as f:
        json.dump(geojson, f, indent=2)
    print(f"  Created {filename}: {aoi['name']}")

print("  AOIs created.")
PYEOF

echo ""
echo "=================================================="
echo "Setup complete!"
echo "=================================================="
echo ""
echo "Data directory: ${IDB_DATA_DIR}"
echo ""
echo "Next steps:"
echo "  1. Open Docker Desktop"
echo "  2. export IDB_DATA_DIR=${IDB_DATA_DIR}"
echo "  3. cd $(dirname "$0")/.."
echo "  4. ./scripts/console"
echo "  5. rastervision run local -e idb.experiment -a test True"
echo ""
