# ── Build stage ───────────────────────────────────────────────────────────────
FROM dart:3.11.2 AS build

WORKDIR /app

# Copy the entire repo so the server can resolve the root package (path: ..)
COPY . .

# Fetch server dependencies and compile to a self-contained native binary
RUN cd server && dart pub get
RUN cd server && dart compile exe bin/main.dart -o bin/server

# ── Runtime stage ─────────────────────────────────────────────────────────────
FROM debian:bookworm-slim

COPY --from=build /app/server/bin/server /server

EXPOSE 8080
CMD ["/server"]
