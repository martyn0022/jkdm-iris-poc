FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        gnucobol \
        python3 \
        python3-pip \
        curl \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir flask==3.0.3

WORKDIR /opt/cobol

COPY copybook/ ./copybook/
COPY src/      ./src/
COPY wrapper/  ./wrapper/

# Compile with the copybook directory on the include path.
# -x produces an executable; free-format is NOT used - this is
# fixed-format COBOL, as the real estate would be.
RUN mkdir -p bin && \
    cobc -x -I ./copybook -o bin/DUTYCALC src/DUTYCALC.cbl && \
    cobc -x -I ./copybook -o bin/MANIFEST src/MANIFEST.cbl && \
    chmod +x bin/DUTYCALC bin/MANIFEST

ENV COBOL_BIN=/opt/cobol/bin/DUTYCALC
ENV COBOL_DATA_DIR=/data

EXPOSE 8080

CMD ["python3", "/opt/cobol/wrapper/app.py"]
