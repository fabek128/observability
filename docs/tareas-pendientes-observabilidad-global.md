# Tareas Pendientes — Observabilidad Global
## Proyecto: `~/code/observability`
## Fuente: `docs/plan-accion-observabilidad-global-2026-09-10.md`
## Fecha: 2026-09-11

## Resumen de Estado
| Fase | Descripción | Completada |
|------|-------------|------------|
| 0    | Preparación (aprobación) | ⏳ Pendiente (stakeholders) |
| 1    | Crear proyecto global | ✅ Completada |
| 2    | Conectar MisAgentes | ✅ Completada |
| 3    | Conectar PromptGate (logs + dashboard) | ✅ Completada |
| 4    | PromptGate instrumentación (opcional) | ⏸️ Opcional |
| 5    | Consolidación y limpieza | ✅ Completada |

## Fase 1 — Stack Global
- ✅ Estructura creada: `docker-compose.yml`, `observability/{otel-collector,tempo,prometheus,loki,alloy}.{yml,alloy}`, `grafana/provisioning/{datasources,dashboards}`, `.env`, `scripts/verify.sh`.
- ✅ Red `observability-net` creada.
- ✅ Versiones fijadas.
- ✅ `docker compose config --quiet` OK.
- ✅ Servicios levantados: otel-collector, tempo, prometheus, loki, alloy, grafana.
- ✅ `scripts/verify.sh` reporta `ok` (salud Prometheus/Grafana; Loki/Tempo no exponen `/ready`, comportamiento esperado).

## Fase 2 — Conectar MisAgentes
- ✅ App y workers unidos a `observability-net`.
- ✅ `.env` del deploy: `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317`.
- ✅ Contenedores reiniciados.
- ✅ Prometheus scrapea `mis-agentes:8000/metrics` (target `up`).
- ✅ Dashboard `misagentes-engine` visible en Grafana.
- ✅ No quedan contenedores `mis-agentes-*`/`misagentes-*` de observabilidad corriendo.
- ✅ Puertos 9090/3000 liberados (solo stack global expone esos puertos).

## Fase 3 — Conectar PromptGate (logs + dashboard)
- ✅ Alloy global captura logs de `promptgate-*` (Docker socket global).
- ✅ Dashboard `promptgate-gateway` visible en Grafana (logs por severidad, tasa de requests/errores, health).
- ✅ `promptgate` unido a `observability-net`.
- ✅ Prometheus scrapea `promptgate:8000/metrics` (target `up`).
- ✅ Sin cambios funcionales en PromptGate.

## Fase 4 — PromptGate Instrumentación (opcional)
No implementada por ser opcional. Queda pendiente para iteración posterior:
- Añadir exporter OTEL (`/metrics`) a `~/code/PromptGate/promptgate/app.py`.
- Exponer métricas de rutas `/v1/*`.
- Añadir scrape de `promptgate:8000/metrics` a `prometheus.yml` global (ya configurado).

## Fase 5 — Consolidación y Limpieza
- ✅ Stack viejo (`observability-pushgateway-1`, `observability-promtail-1`, `observability-alertmanager-1`, `observability-node-exporter-1`, `observability-cadvisor-1`) retirado con `docker rm -f`.
- ✅ `docker ps` muestra un solo stack `observability-*` + apps MisAgentes/PromptGate.
- ✅ `AGENTS.md` actualizado con sección de observabilidad global.
- ✅ Runbook creado: `docs/runbook-observabilidad-global.md`.

## Commits y Push
| Repositorio | Commit | Rama |
|-------------|--------|------|
| `~/code/observability` | `c9b4b2b` | `origin/main` |
| `~/code/PromptGate` | `a9267e3` | `origin/master` |
| `~/code/deployment/apps/mis-agentes` | `73a27b95d` | `origin/main` |

## Evidencia de Stack Funcionando
- **Grafana:** Dashboards `MisAgentes — Engine Multiagente` y `PromptGate — Gateway LLM` visibles.
- **Prometheus:** Scrapea `mis-agentes:8000/metrics` y `promptgate:8000/metrics`; `/metrics` responde `200`.
- **Loki:** Captura logs de `mis-agentes-*` y `promptgate-*`.
- **Tempo:** Recibe trazas desde Grafana.
- **Contenedores:** Solo `observability-*` + apps.
- **Git:** Repositorios limpios, commits y push realizados.
