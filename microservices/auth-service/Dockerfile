FROM golang:1.23-alpine3.20 AS builder
WORKDIR /app
COPY . .
RUN go mod tidy
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o auth-service .
FROM alpine:3.20
WORKDIR /app
RUN apk add --no-cache curl
RUN addgroup -S appgroup && \
    adduser -S appuser -G appgroup -s /sbin/nologin
COPY --from=builder /app/auth-service .
RUN chown -R appuser:appgroup /app
USER appuser
EXPOSE 8001
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8001/health || exit 1
CMD ["./auth-service"]
