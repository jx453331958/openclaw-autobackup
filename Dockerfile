# Build stage
FROM golang:1.25-alpine AS builder

RUN apk add --no-cache gcc musl-dev

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=1 go build -o openclaw-autobackup .

# Runtime stage
FROM alpine:latest

RUN apk add --no-cache rsync git openssh-client tzdata

WORKDIR /app

COPY --from=builder /app/openclaw-autobackup .

VOLUME ["/app/data"]

EXPOSE 3458

CMD ["./openclaw-autobackup"]
