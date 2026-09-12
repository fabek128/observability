# Plan de acción — Observabilidad global

**Proyecto:** `~/code/observability`
**Fecha:** 2026-09-10
**Referencia:** `docs/especificacion-observabilidad-global-2026-09-10.md`

Objetivo: **un solo stack de observabilidad** en `~/code/observability`, con MisAgentes y PromptGate inicialmente conectados.

---

## Fase 0 — Preparación (estado actual)

- [x] Inventario de stacks: `mis-agentes-*` (proyecto, prometheus/grafana sin arrancar), `misagentes-*` (stale 7 sem), `observability-*` (path muerto 2 meses).
- [x] Confirmar flujo OTEL de MisAgentes (`OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317`).
- [x] Confirmar que PromptGate **no** expone OTEL ni `/metrics` Prometheus.
- [ ] **Aprobar** esta especificación y el plan.

**Salida:** decisión aprobada + lista de stacks a retirar.

---

## Fase 1 — Crear el proyecto global

**Tareas**
- [ ] Crear estructura `~/code/observability/`:
  - `docker-compose.yml`
  - `observability/{otel-collector.yml,tempo.yml,prometheus.yml,loki.yml,alloy.alloy}`
  - `grafana/provisioning/datasources/*.yaml`
  - `grafana/provisioning/dashboards/*.json`
  - `.env` (puertos, passwords, retención)
  - `scripts/verify.sh` (healthcheck de todos los servicios)
- [ ] Definir red externa estable `observability-net` (bridge, nombre fijo).
- [ ] Versiones fijadas:
  - otel `0.120.0`, tempo `2.7.2`, prometheus `v3.2.1`, loki `3.4.2`, alloy `v1.7.2`, grafana `11.5.2`.

**Criterio de aceptación**
- `docker compose config --quiet` sin errores.
- `docker compose up -d` levanta los 6+ servicios.
- `scripts/verify.sh` reporta todos `ok`.

---

## Fase 2 — Conectar MisAgentes

**Tareas**
- [ ] En el compose del proyecto (`~/code/deployment/apps/mis-agentes`):
  - Unir la app-service (y workers) a `observability-net` (external).
  - Apuntar en `.env` del deploy: `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317` (idéntico; cambia el **destino de red**).
- [ ] Reiniciar contenedores del proyecto (`docker compose up -d`).
- [ ] Verificar trazas: `curl http://prometheus:9090` importado, y consulta a Tempo (`/api/v1/traces` de Grafana) con tráfico real de prueba.
- [ ] Verificar métricas: Prometheus scrapeando `mis-agentes:8000/metrics` (sampleo de un gate).
- [ ] Verificar logs: Loki tiene entradas de `mis-agentes-*`.
- [ ] **Retirar** del compose del proyecto los servicios `otel-collector`, `tempo`, `loki`, `alloy`, `prometheus`, `grafana` (o moverlos a un perfil `legacy`).
- [ ] Detener y borrar contenedores huérfanos: `mis-agentes-prometheus-1`, `mis-agentes-grafana-1`, y el stack `misagentes-*`.
- [ ] Liberar puertos: 9090 (misagentes prometheus), 3000 (misagentes grafana).

**Criterio de aceptación**
- Dashboard `misagentes-engine` en Grafana global muestra runs/latencias.
- Trazas de un run de prueba aparecen en Tempo (explorar desde Grafana).
- No quedan contenedores `mis-agentes-*`/`misagentes-*` de observabilidad corriendo.

---

## Fase 3 — Conectar PromptGate (fase 1: logs + dashboard)

**Tareas**
- [ ] Confirmar que Alloy global captura los logs de `promptgate-*` (Docker socket global).
- [ ] Crear dashboard `promptgate-gateway` con paneles de:
  - logs por severidad (Loki);
  - tasa de requests / errores (Loki query sobre logs de acceso/errores);
  - health del contenedor.
- [ ] Unir `promptgate` a `observability-net` (solo si algún scrape lo requiere; no necesario para logs).

**Criterio de aceptación**
- Dashboard `promptgate-gateway` muestra logs en vivo de `promptgate`, `promptgate-worker`, `promptgate-postgres`.
- Sin cambios funcionales en PromptGate.

---

## Fase 4 — PromptGate fase 2: instrumentación (opcional, posterior)

**Tareas**
- [ ] Añadir exporter OTEL (o `/metrics` prometheus_client) a `~/code/PromptGate/promptgate/app.py`.
- [ ] Exponer métricas de rutas: `/v1/*` requests, latencias, errores, fallbacks.
- [ ] Configurar `OTEL_EXPORTER_OTLP_ENDPOINT` en el compose de PromptGate.
- [ ] Scrape de `promptgate:8000/metrics` añadido a prometheus.yml global.

**Criterio de aceptación**
- Trazas/métricas de PromptGate en Grafana global.
- Dashboard `promptgate-gateway` con métricas reales (latencias, errores).

---

## Fase 5 — Consolidación y limpieza

**Tareas**
- [ ] Retirar stack `observability-*` viejo (`/opt/panchoserver` muerto): `docker compose down` + borrar volumens, previa comprobación de que nada depende.
- [ ] Actualizar `AGENTS.md` de `~/code` con la sección de observabilidad global (path, servicios, cómo conectar un proyecto nuevo).
- [ ] Documento runbook: `docs/runbook-observabilidad.md` (arranque, verificación, resolución de problemas, rotación de password Grafana).
- [ ] Opcional: alertmanager + rutas (email/webhook) y re-adopción de node-exporter/cadvisor para métricas de infra.

**Criterio de aceptación**
- `docker ps` muestra **un solo** stack de observabilidad (`observability-*` nuevo) + apps.
- `AGENTS.md` actualizado y consistente.
- README/runbook operativo.

---

## Riesgos y mitigaciones

| Riesgo | Mitigación |
|---|---|
| Quitar stacks obsoletos rompe algo que aún las usa | Fase 5 exige verificación de dependencias + `AGENTS.md` antes |
| `observability-net` external requiere editar compose de proyectos | Cambio mínimo y reversible; se documenta el contrato en la especificación §5.2/5.3 |
| Grafana sin datos al inicio (espera OTLP) | Verify script marca `ok` solo con datasources conectados; dashboards vacíos son esperables hasta Fase 2 |
| Pérdida de retención histórica al migrar | Aceptado: los stacks viejos no tienen datos valiosos consumibles hoy (prometheus/grafana del proyecto nunca arrancaron) |
| dual-write temporal durante transición | Fases permiten solape: se apunta el proyecto al global y solo después se retiran los locales |

---

## Orden de ejecución sugerido

1. Fase 1 (stack global) → verificación autónoma.
2. Fase 2 (MisAgentes) → primer consumidor real; valida logs + métricas + trazas.
3. Fase 3 (PromptGate logs) → segundo proyecto conectado.
4. Fase 5 (limpieza) → retirada de obsoletos + docs.
5. Fase 4 (PromptGate instrumentación) → iteración opcional siguiente.

**Siguiente paso pendiente de aprobación:** ejecutar Fase 1 (crear `docker-compose.yml` y configs en `~/code/observability`).