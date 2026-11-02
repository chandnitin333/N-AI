FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    WINEARCH=win64 \
    WINEPREFIX=/opt/wine \
    WINEDEBUG=-all

RUN dpkg --add-architecture amd64 \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        nsis \
        unzip \
        wine \
        wine64 \
        xvfb \
    && rm -rf /var/lib/apt/lists/*

COPY requirements-build.txt /tmp/build/requirements-build.txt
COPY requirements.txt /tmp/build/requirements.txt
RUN curl --fail --location --retry 3 \
        https://www.python.org/ftp/python/3.11.9/python-3.11.9-embed-amd64.zip \
        --output /tmp/python-embed.zip \
    && curl --fail --location --retry 3 \
        https://bootstrap.pypa.io/get-pip.py \
        --output /tmp/get-pip.py \
    && mkdir -p /opt/python311 \
    && unzip -q /tmp/python-embed.zip -d /opt/python311 \
    && printf '\nLib\\site-packages\nimport site\n' >> /opt/python311/python311._pth \
    && xvfb-run -a sh -c 'wineboot --init \
        && wine Z:\\opt\\python311\\python.exe Z:\\tmp\\get-pip.py \
        && wine Z:\\opt\\python311\\python.exe -m pip install --no-warn-script-location -r Z:\\tmp\\build\\requirements-build.txt \
        && wine Z:\\opt\\python311\\python.exe -m PyInstaller --version' \
    && rm -f /tmp/python-embed.zip /tmp/get-pip.py \
    && wineserver -w

WORKDIR /workspace
CMD ["bash", "scripts/build_windows_in_container.sh"]
