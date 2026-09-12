# Runbook — Observabilidad Global

Repositorio: `~/code/observability`
Rama: `main`
Compose: `docker-compose.yml`

## Servicios

- `otel-collector`: recibe OTLP en `4317`/`4318` y expone Prometheus en `8889`.
- `prometheus`: `http://localhost:9090`
- `tempo`: `http://localhost:3200`
- `loki`: `http://localhost:3100`
- `alloy`: ingesta logs Docker → Loki
- `grafana`: `http://localhost:3000` (`admin` / `changeme`)

## Arranque y parada

```bash
cd ~/code/observability
docker compose up -d
docker compose down
```

## Verificación

```bash
cd ~/code/observability
bash scripts/verify.sh
```

Checks esperados:

- `docker compose config` válido.
- `otel-collector`, `tempo`, `prometheus`, `loki`, `alloy` y `grafana` en `running`.
- `http://localhost:9090/-/healthy` OK.
- `http://localhost:3000/api/health` OK.
- `http://localhost:3100/ready` y `http://localhost:3200/api/health` pueden no responder si el contenedor no expone esos endpoints HTTP; validar el estado del contenedor y los logs antes de asumir fallo.

## Grafana

- URL: `http://localhost:3000`
- Usuario: `admin`
- Contraseña inicial: `changeme`
- Datasources provisionados: Prometheus, Tempo y Loki.
- Dashboards provisionados:
  - `grafana/provisioning/dashboards/promptgate/promptgate-gateway.json`
  - `grafana/provisioning/dashboards/misagentes/misagentes-engine.json`

Si un dashboard no aparece, revisar:

```bash
docker compose -f docker-compose.yml ps grafana
docker logs observability-grafana-1 --tail 100
```

## Integración MisAgentes

En `~/code/deployment/apps/mis-agentes/docker-compose.yml`, la red `observability-net` está conectada al servicio principal y a los workers. El compose requiere `NATS_AUTH_TOKEN` en el entorno:

```bash
cd ~/code/deployment/apps/mis-agentes
set -a
source .env
set +a
docker compose config --quiet
docker compose up -d
```

Si falla con `NATS_AUTH_TOKEN is missing`, el problema es el entorno de la shell, no la sintaxis del compose.

## Integración PromptGate

En `~/code/PromptGate/docker-compose.yml`, el servicio usa la red `observability-net` y exporta OTLP a `otel-collector:4317`. Validación:

```bash
cd ~/code/PromptGate
docker compose config --quiet
curl -s http://localhost:9000/health
```

## Solución rápida de problemas

- `otel-collector` no recibe datos: revisar logs de `alloy`, `prometheus` y los envs `OTEL_EXPORTER_OTLP_ENDPOINT`.
- No hay métricas en Prometheus: abrir `http://localhost:9090/targets` y revisar jobs caídos.
- No hay logs en Loki: revisar logs de `alloy` y la conexión al socket de Docker.
- No hay traces en Tempo: confirmar que los servicios emiten OTLP a `otel-collector:4317` y que el collector está `running`.
- Si falta una variable en compose, cargar primero `.env` como en la sección de MisAgentes.

## Mantenimiento

```bash
cd ~/code/observability
git pull
bash scripts/verify.sh
docker compose up -d
```

Commit y push de cambios operativos:

```bash
git add .
git commit -m "observability: <cambio>"
git push origin main
```
