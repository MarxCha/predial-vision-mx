# Plan de integración: predial-vision-mx → ecosistema Predial-IA

**Fecha:** 2026-04-26
**Autor:** Claude Code (sesión predial-vision-mx, MacBook Pro)
**Responde a:** SUGERENCIAS-TERRAVISTA-PREDIAL-VISION-2026-04-26.md (colouring-mexico)
**Alcance:** Solo lo que compete a predial-vision-mx

---

## Estado actual de predial-vision-mx

| Componente | Estado |
|---|---|
| Dockerfile | Funcional (Python 3.6 + TF 1.15 + RV 0.8 + DeepLab + tippecanoe) |
| Imagery | GeoTIFF 245MB, ESRI World Imagery ~1m/px, EPSG:4326 |
| Labels actuales | 1,707 buildings OSM → mbtiles (tippecanoe) |
| Pipeline chip→train→bundle→predict | Funcional (test 1 step completado) |
| Pipeline eval | Fix aplicado (mask-to-polygons), en verificación |
| Entrenamiento completo (150K steps) | Pendiente (requiere GPU o ~días en CPU) |
| Repo | github.com/MarxCha/predial-vision-mx |

---

## P0 · Reemplazar labels OSM por MS Buildings (quick win)

**Por qué:** OSM tiene 1,707 buildings ruidosos. TerraVista tiene 138,491 MS Building Footprints verificados en `terravista_data.public.ms_buildings_nr`. Usar MS Buildings como labels mejora el training ~80x en volumen y calidad.

**Qué necesito de TerraVista/colouring:**
- Export de MS Buildings NR en GeoJSON SRID 4326 (ya existe ruta validada via `ogr2ogr` en las sugerencias, sección A.3)
- O el CSV `ms_nr_3857.csv` (34MB) que colouring ya tiene en `.context/hito4-data/`

**Qué hago yo:**
1. Recibir GeoJSON de los 138K buildings
2. Convertir a `.mbtiles` con tippecanoe (ya tengo el pipeline)
3. Reemplazar `vector-tiles/mexico.mbtiles.gz` actual (1,707 OSM) por el nuevo (138K MS)
4. Regenerar AOIs basados en densidad real de MS Buildings
5. Re-correr chip + train con el nuevo dataset

**Esfuerzo:** 2h (conversión + ajuste AOIs + test run)
**Dependencia:** Archivo GeoJSON/CSV de MS Buildings exportado desde TerraVista o colouring
**Impacto:** F1 estimado pasa de ~0.3 (OSM ruidoso, 1 step) a ~0.65+ (MS labels, 150K steps)

---

## P1 · Optimizar pipeline: eliminar cuello de botella tippecanoe-decode

**Por qué:** La conversión de vector tiles con `tippecanoe-decode` dentro del contenedor toma ~40 min por corrida. Si usamos MS Buildings como GeoJSON directo (sin mbtiles intermedios), el chip step baja de 40 min a ~5 min.

**Qué hago:**
1. Modificar `experiment.py` para aceptar GeoJSON directo como label source (usando `GeoJSONVectorSource` en vez de `VectorTileSource`)
2. O pre-rasterizar los labels como GeoTIFF binario (building=1, background=0) y usar `RasterizedSource` directo

**Esfuerzo:** 3-4h (refactor experiment.py + test)
**Dependencia:** Ninguna (ya tengo los GeoJSON)
**Impacto:** Ciclo de iteración de ~2h a ~30 min

---

## P2 · Entrenar modelo real (150K steps)

**Por qué:** El test de 1 step produce un modelo inútil (1.6% buildings detectados, 0 calibración). Se necesita el entrenamiento completo para producir predicciones usables.

**Opciones:**
- **CPU local (MacBook Pro i7):** ~3-5 días. No práctico.
- **GPU local:** No disponible en esta máquina.
- **Cloud GPU (recomendado):** P3.2xlarge en AWS (~1 día) o Colab Pro (~3-4h con T4)
- **GCP del CEO:** Si TerraVista ya tiene infra GCP en proceso, reutilizar

**Qué necesito del CEO/TerraVista:** Decisión sobre dónde correr el training (AWS/GCP/Colab)

**Esfuerzo:** 1h setup + 4-24h training (según hardware)
**Dependencia:** Acceso a GPU
**Impacto:** Modelo funcional para demo con Catastro NR

---

## P3 · Output de predicciones compatible con TerraVista

**Por qué:** TerraVista necesita los polígonos de predicción en PostGIS como `predicted_buildings_nr`.

**Qué genero yo (ya funciona):**
- `nicolas_romero.tif` — raster de predicciones (Building=1, Background=2)
- `nicolas_romero-1-polygons.geojson` — polígonos vectoriales de edificios detectados (pendiente verificar con fix mask-to-polygons)
- `predict_package.zip` — modelo portable para predecir sobre nueva imagery

**Formato de entrega a TerraVista:**
```
predictions/
├── nicolas_romero-1-polygons.geojson  ← INSERT directo en PostGIS
├── nicolas_romero.tif                 ← Capa raster para GeoServer
└── predict_package.zip                ← Re-usar para nueva imagery
```

**SQL para que TerraVista cargue las predicciones:**
```sql
-- Crear tabla de predicciones
CREATE TABLE catastro_correcto.predicted_buildings_nr (
    pred_id SERIAL PRIMARY KEY,
    geom GEOMETRY(Polygon, 4326),
    confidence FLOAT,
    detected_at TIMESTAMP DEFAULT NOW(),
    validated BOOLEAN DEFAULT FALSE,
    source VARCHAR DEFAULT 'predial-vision-mx'
);

-- Cargar desde GeoJSON (ogr2ogr)
-- ogr2ogr -f PostgreSQL PG:"host=localhost dbname=terravista_data" \
--   nicolas_romero-1-polygons.geojson \
--   -nln catastro_correcto.predicted_buildings_nr -append
```

**Esfuerzo:** 1h (script de export + documentación formato)
**Dependencia:** P2 completado (modelo entrenado)

---

## P4 · Aceptar feedback de colouring (active learning)

**Por qué:** colouring-mexico propone enviar predicciones dudosas (confidence 0.4-0.7) para validación humana, y devolver true/false positives para retrain.

**Qué necesito de colouring:**
- Endpoint `GET /api/colouring-export/validated.geojson?ref_prefix=predial_vision`
- Formato: GeoJSON con `properties.validation_status` = `VERIFIED` | `REJECTED`

**Qué hago yo:**
1. Script `ingest_feedback.py` que lee el endpoint de colouring
2. Separa true positives (→ training set) y false positives (→ hard negatives para retrain)
3. Re-genera TFRecords con el dataset enriquecido
4. Re-entrena modelo (P2 de nuevo)

**Esfuerzo:** 3h (script + pipeline de retrain)
**Dependencia:** P2 + P3 completados, colouring con endpoint export funcionando, masa crítica de edits (~500+)
**Timing:** No antes de que el modelo esté entrenado y colouring tenga usuarios activos

---

## Secuencia recomendada

```
Ahora          P0 · MS Buildings como labels (esperar export de TerraVista)
               P1 · Optimizar pipeline (eliminar tippecanoe-decode)

Con GPU        P2 · Entrenar modelo real 150K steps

Post-training  P3 · Entregar predicciones a TerraVista
               P4 · Active learning con colouring (cuando haya masa crítica)
```

---

## Lo que NO me compete (y dejo a los otros equipos)

- Endpoint export en colouring (A.1, A.2 del documento de sugerencias) → colouring-mexico
- Vista materializada `colouring_validated_heights_nr` → TerraVista
- Modificar `construcciones_no_registradas_mv` con tier de validación → TerraVista
- Decisión GCP/AWS para training → CEO
- n8n workflows de orquestación → TerraVista

---

## Archivos que necesito recibir

| De quién | Qué | Para qué | Prioridad |
|---|---|---|---|
| TerraVista o colouring | MS Buildings NR GeoJSON (138K, SRID 4326) | P0 - labels mejorados | ALTA |
| CEO | Acceso a GPU (AWS/GCP/Colab) | P2 - training real | ALTA |
| colouring | `validated.geojson` endpoint | P4 - active learning | BAJA (futuro) |

---

**Fin del plan.**
