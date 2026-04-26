FROM python:3.6-buster

RUN echo "deb http://archive.debian.org/debian buster main" > /etc/apt/sources.list && \
    echo "deb http://archive.debian.org/debian-security buster/updates main" >> /etc/apt/sources.list

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential libspatialindex-dev gdal-bin libgdal-dev \
    wget git make libsqlite3-dev zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/mapbox/tippecanoe.git /tmp/tippecanoe && \
    cd /tmp/tippecanoe && git checkout 1.34.3 && \
    make -j$(nproc) && make install && rm -rf /tmp/tippecanoe

ENV CPLUS_INCLUDE_PATH=/usr/include/gdal
ENV C_INCLUDE_PATH=/usr/include/gdal
ENV GDAL_DATA=/usr/share/gdal

# Core ML deps
RUN pip install --no-cache-dir tensorflow==1.15.5 protobuf==3.6.1 "scipy<2" "h5py<3"

# Geo deps
RUN pip install --no-cache-dir "shapely<2" rtree "rasterio<1.3" "GDAL==$(gdal-config --version)" pyproj

# Remaining deps
RUN pip install --no-cache-dir "Pillow<9" "click<7" "lxml<5" "imageio<3" "scikit-learn<1" \
    six "matplotlib<3" "networkx<3" everett==0.9 pluginbase==0.7 "supermercado==0.0.5" \
    boto3 tf-slim==1.1.0 "jinja2<3.1" mask-to-polygons

# Install RV --no-deps
RUN pip install --no-cache-dir --no-deps \
    "git+https://github.com/azavea/raster-vision.git@9f38cc9#egg=rastervision"

# Relax RV version pins in metadata
COPY relax_pins.py /tmp/relax_pins.py
RUN python3 /tmp/relax_pins.py

# TF models DeepLab (TF 1.x compatible)
RUN git clone https://github.com/tensorflow/models.git /opt/tf-models && \
    cd /opt/tf-models && git checkout cbbb2ffcde66e646d4a47628ffe2ece2322b64e8 && \
    cd research && \
    export PYTHONPATH=$PYTHONPATH:/opt/tf-models/research:/opt/tf-models/research/slim && \
    python setup.py install || true

ENV PYTHONPATH="${PYTHONPATH}:/opt/tf-models/research:/opt/tf-models/research/slim:/opt/tf-models/research/deeplab"
RUN ln -s /opt/tf-models/research/deeplab /opt/tf-models/deeplab

COPY patch_data_generator.py /tmp/patch_data_generator.py
RUN python3 /tmp/patch_data_generator.py

RUN mkdir -p /opt/src /opt/data
WORKDIR /opt/src
CMD ["/bin/bash"]
