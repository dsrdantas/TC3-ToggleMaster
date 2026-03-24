FROM golang:1.23-alpine3.20 AS builder
RUN apk add --no-cache git bash build-base
WORKDIR /app
COPY . .
RUN go mod tidy
RUN CGO_ENABLED=0 GOOS=linux go build -o evaluation-service .
FROM alpine:3.20
RUN apk add --no-cache curl
RUN addgroup -S appgroup && \
    adduser -S appuser -G appgroup -s /sbin/nologin
WORKDIR /app
COPY --from=builder /app/evaluation-service .
RUN chown -R appuser:appgroup /app
USER appuser
EXPOSE 8004
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8004/health || exit 1
CMD ["./evaluation-service"]