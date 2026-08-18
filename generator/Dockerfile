FROM python:3.12-slim

RUN pip install --no-cache-dir psycopg2-binary==2.9.9

WORKDIR /opt/generator
COPY generate_flatfile.py generate_manifest.py ./

CMD ["sh", "-c", "python generate_flatfile.py && python generate_manifest.py"]
