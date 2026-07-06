FROM python:3.12-slim

WORKDIR /app

COPY coordinator/requirements.txt coordinator/
RUN pip install --no-cache-dir -r coordinator/requirements.txt

COPY . .

RUN cp android-node/index.html coordinator/static/mobile.html

EXPOSE 8081

VOLUME ["/app/vm/images", "/app/vm/logs"]

HEALTHCHECK --interval=15s --timeout=5s --retries=3 \
  CMD python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8081/api/health')" || exit 1

CMD ["python3", "coordinator/server.py"]
