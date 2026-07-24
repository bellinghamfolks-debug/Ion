# Railway build image for the EnglishNova / DocConverter backend.
#
# It runs the Node server AND bundles the Python conversion engines so both
# conversion modes work in production:
#   - PyMuPDF  -> faithful per-page text extraction (correct Arabic/RTL order,
#                 spacing and real tables) for the accessible mode.
#   - pdf2docx -> layout-preserving PDF -> DOCX for the "professional" mode.
#
# Railway auto-detects this Dockerfile and builds with it instead of Railpack.
# The server entry point and behaviour are unchanged, so EnglishNova is
# unaffected — Python is simply available for the converter.
FROM node:20-bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 python3-venv python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Python deps in an isolated venv, placed first on PATH so the `python3` the
# Node server spawns resolves to this interpreter (with pdf2docx + PyMuPDF).
ENV PATH="/opt/venv/bin:${PATH}"
RUN python3 -m venv /opt/venv
COPY server/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

WORKDIR /app
COPY server/package*.json server/
RUN cd server && (npm ci || npm install)
COPY server server
ENV NODE_ENV=production
CMD ["node", "server/src/index.js"]
