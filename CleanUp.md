cd D:\_GitHub\WhisperFusion

# Complete cleanup
docker compose down -v
docker builder prune -a -f
docker rmi whisperfusion:latest
Remove-Item -Recurse -Force "D:\_GitHub\WhisperFusion\docker\scratch-space\models\*" -ErrorAction SilentlyContinue

# Build with uv
docker compose build --no-cache --progress=plain

# Start and monitor
docker compose up -d
docker compose logs -f whisperfusion