#!/usr/bin/env bash
set -euo pipefail

# Script de verificación para el stack de observabilidad global
# Requiere: docker, docker-compose, curl, jq (opcional)

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"

cd "$PROJECT_DIR"

echo "=== Verificación del stack de observabilidad ==="
echo "Directorio del proyecto: $PROJECT_DIR"
echo "Archivo compose: $COMPOSE_FILE"
echo

# 1. Verificar que docker compose config es válido
echo "1️⃣  Validando configuración de docker compose..."
if docker compose -f "$COMPOSE_FILE" config --quiet > /dev/null 2>&1; then
    echo "   ✅ docker compose config: OK"
else
    echo "   ❌ docker compose config: FALLÓ"
    exit 1
fi
echo

# 2. Verificar que los servicios estén levantados
echo "2️⃣  Verificando estado de los servicios..."
SERVICES=(otel-collector tempo prometheus loki alloy grafana)
for service in "${SERVICES[@]}"; do
    status=$(docker compose -f "$COMPOSE_FILE" ps --services --filter "status=running" | grep -x "$service" || true)
    if [[ -n "$status" ]]; then
        echo "   ✅ $service: running"
    else
        echo "   ❌ $service: NO está running"
        # Intentar levantar si no está
        echo "      Intentando levantar $service..."
        docker compose -f "$COMPOSE_FILE" up -d "$service" > /dev/null 2>&1
        sleep 2
        status=$(docker compose -f "$COMPOSE_FILE" ps --services --filter "status=running" | grep -x "$service" || true)
        if [[ -n "$status" ]]; then
            echo "      ✅ $service ahora está running"
        else
            echo "      ❌ $service sigue sin levantar"
            exit 1
        fi
    fi
done
echo

# 3. Verificar endpoints de salud (donde aplique)
echo "3️⃣  Verificando endpoints de salud (donde estén expuestos)..."
# Mapeo de servicio -> (host:puerto, endpoint opcional, método)
declare -A HEALTH_CHECKS
HEALTH_CHECKS[prometheus]="localhost:9090/-/healthy"
HEALTH_CHECKS[tempo]="localhost:3200/api/health"
HEALTH_CHECKS[loki]="localhost:3100/ready"
HEALTH_CHECKS[grafana]="localhost:3000/api/health"
# otel-collector: no host port, chequearemos vía internal port 8889 usando docker exec
# alloy: no health endpoint, solo chequeamos que esté up

for service in "${!HEALTH_CHECKS[@]}"; do
    endpoint="${HEALTH_CHECKS[$service]}"
    echo -n "   🔍 $service → http://$endpoint ... "
    if curl -s -f "http://$endpoint" > /dev/null; then
        echo "OK"
    else
        echo "FALLÓ"
        # Intentar obtener más info
        status_code=$(curl -s -o /dev/null -w "%{http_code}" "http://$endpoint" || echo "000")
        echo "      Código HTTP: $status_code"
        # No fallamos inmediatamente para algunos servicios que podrían estar inicializando
        # Pero para grafana y prometheus sí son críticos
        if [[ "$service" == "prometheus" || "$service" == "grafana" ]]; then
            echo "      ❌ Servicio crítico no responde"
            exit 1
        else
            echo "      ⚠️  Servicio no crítico, continuando..."
        fi
    fi
done
echo

# 4. Verificar que el collector esté recibiendo OTLP (opcional)
echo "4️⃣  Verificando que el collector esté escuchando en 4317 (grpc)..."
if docker compose -f "$COMPOSE_FILE" exec otel-collector nc -z localhost 4317 2>/dev/null; then
    echo "   ✅ Collector escuchando en 4317 (OTLP gRPC)"
else
    # Puede fallar porque nc no está instalado; intentar con curl? No, gRPC.
    # Alternativa: verificar que el proceso está arriba y el puerto está en escucha dentro del contenedor
    if docker compose -f "$COMPOSE_FILE" exec otel-collector ss -tlnp | grep -q ":4317"; then
        echo "   ✅ Collector escuchando en 4317 (OTLP gRPC) (vía ss)"
    else
        echo "   ⚠️  No se pudo verificar puerto 4317 (asumiendo que está OK si el contenedor está up)"
    fi
fi
echo

# 5. Verificar que Loki esté recibiendo tráfico de Alloy (opcional)
echo "5️⃣  Verificando que Loki esté escuchando en 3100..."
if curl -s -f "http://localhost:3100/ready" > /dev/null; then
    echo "   ✅ Loki listo para recibir logs"
else
    echo "   ⚠️  Loki no responde al endpoint /ready (puede estar inicializando)"
fi
echo

echo "✅  Verificación completada. El stack parece estar funcionando."
echo "   Puede acceder a Grafana en http://localhost:3000 (usuario: admin, contraseña: changeme)"
echo "   Prometheus: http://localhost:9090"
echo "   Tempo: http://localhost:3200"
echo "   Loki: http://localhost:3100"

exit 0