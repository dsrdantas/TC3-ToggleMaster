FROM python:3.12-alpine3.20 AS builder
WORKDIR /app
RUN apk add --no-cache \
    gcc \
    musl-dev \
    postgresql-dev \
    libffi-dev
COPY requirements.txt .
RUN pip install --upgrade pip && \
    pip install --prefix=/usr/local --no-cache-dir -r requirements.txt
FROM python:3.12-alpine3.20
WORKDIR /app
RUN apk add --no-cache \
    curl \
    postgresql-libs
ENV PYTHONPATH="/usr/local/lib/python3.12/site-packages"
COPY --from=builder /usr/local /usr/local
COPY . .
RUN addgroup -S appgroup && \
    adduser -S appuser -G appgroup -s /sbin/nologin && \
    chown -R appuser:appgroup /app

USER appuser
EXPOSE 8002
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8002/health || exit 1
CMD ["gunicorn", "--bind", "0.0.0.0:8002", "app:app"]ess