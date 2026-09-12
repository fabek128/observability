# Tareas Pendientes — Observabilidad Global

**Proyecto:** `~/code/observability`  
**Fuente:** `docs/plan-accion-observabilidad-global-2026-09-10.md`  
**Fecha:** 2026-09-11  

Este documento lista **todas las tareas que faltan completar** (marcadas `[ ]` en el plan original), agrupadas por fase, con criterios de aceptación y orden de ejecución.

---

## Resumen de Estado

| Fase | Descripción | Tareas totales | Completadas | Pendientes |
|------|-------------|----------------|-------------|------------|
| 0    | Preparación | 4 | 3 | **1** |
| 1    | Crear proyecto global | 8 | 0 | **8** |
| 2    | Conectar MisAgentes | 9 | 0 | **9** |
| 3    | Conectar PromptGate (logs + dashboard) | 5 | 0 | **5** |
| 4    | PromptGate instrumentación (opcional) | 4 | 0 | **4** |
| 5    | Consolidación y limpieza | 4 | 0 | **4** |
| **Total** | | **34** | **3** | **31** |

---

## Fase 0 — Preparación

### Pendiente
- [ ] **Aprobar esta especificación y el plan.**  
  *Acción:* Revisar `docs/especificacion-observabilidad-global-2026-09-10.md` y este plan con los stakeholders. Documentar decisión y lista de stacks a retirar.

---

## Fase 1 — Crear el proyecto global

### Tareas
- [ ] **Crear estructura `~/code/observability/`:**
  - `docker-compose.yml`
  - `observability/{otel-collector.yml,tempo.yml,prometheus.yml,loki.yml,alloy.alloy}`
  - `grafana/provisioning/datasources/*.yaml`
  - `grafana/provisioning/dashboards/*.json`
  - `.env` (puertos, passwords, retención)
  - `scripts/verify.sh` (healthcheck de todos los servicios)

- [ ] **Definir red externa estable `observability-net` (bridge, nombre fijo).**  
  `docker network create observability-net` (si no existe).

- [ ] **Fijar versiones en `docker-compose.yml`:**
  - otel `0.120.0`
  - tempo `2.7.2`
  - prometheus `v3.2.1`
  - loki `3.4.2`
  - alloy `v1.7.2`
  - grafana `11.5.2`

### Criterios de aceptación
1. `docker compose config --quiet` sin errores.
2. `docker compose up -d` levanta los 6+ servicios (otel-collector, tempo, prometheus, loki, alloy, grafana).
3. `scripts/verify.sh` reporta todos `ok` (healthchecks de cada servicio).

---

## Fase 2 — Conectar MisAgentes

### Tareas
- [ ] **En el compose del proyecto (`~/code/deployment/apps/mis-agentes`):**
  - Unir la app-service (y workers) a `observability-net` (external).
  - Apuntar en `.env` del deploy: `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317` (mismo endpoint, cambia el destino de red).

- [ ] **Reiniciar contenedores del proyecto** (`docker compose up -d`).

- [ ] **Verificar trazas:**  
  - `curl http://prometheus:9090` importado.  
  - Consulta a Tempo (`/api/v1/traces` de Grafana) con tráfico real de prueba.

- [ ] **Verificar métricas:** Prometheus scrapeando `mis-agentes:8000/metrics` (sampleo de un gate).

- [ ] **Verificar logs:** Loki tiene entradas de `mis-agentes-*`.

- [ ] **Retirar del compose del proyecto** los servicios `otel-collector`, `tempo`, `loki`, `alloy`, `prometheus`, `grafana` (o moverlos a un perfil `legacy`).

- [ ] **Detener y borrar contenedores huérfanos:** `mis-agentes-prometheus-1`, `mis-agentes-grafana-1`, y el stack `misagentes-*`.

- [ ] **Liberar puertos:** 9090 (misagentes prometheus), 3000 (misagentes grafana).

### Criterios de aceptación
- Dashboard `misagentes-engine` en Grafana global muestra runs/latencias.
- Trazas de un run de prueba aparecen en Tempo (explorar desde Grafana).
- No quedan contenedores `mis-agentes-*`/`misagentes-*` de observabilidad corriendo.

---

## Fase 3 — Conectar PromptGate (fase 1: logs + dashboard)

### Tareas
- [ ] **Confirmar que Alloy global captura los logs de `promptgate-*`** (Docker socket global).

- [ ] **Crear dashboard `promptgate-gateway`** con paneles de:
  - Logs por severidad (Loki).
  - Tasa de requests / errores (Loki query sobre logs de acceso/errores).
  - Health del contenedor.

- [ ] **Unir `promptgate` a `observability-net`** (solo si algún scrape lo requiere; no necesario para logs).

### Criterios de aceptación
- Dashboard `promptgate-gateway` muestra logs en vivo de `promptgate`, `promptgate-worker`, `promptgate-postgres`.
- Sin cambios funcionales en PromptGate.

---

## Fase 4 — PromptGate fase 2: instrumentación (opcional, posterior)

### Tareas
- [ ] **Añadir exporter OTEL (o `/metrics` prometheus_client)** a `~/code/PromptGate/promptgate/app.py`.

- [ ] **Exponer métricas de rutas:** `/v1/*` requests, latencias, errores, fallbacks.

- [ ] **Configurar `OTEL_EXPORTER_OTLP_ENDPOINT`** en el compose de PromptGate (ya presente en `docker-compose.yml` como `PROMPTGATE_OTLP_ENDPOINT`).

- [ ] **Scrape de `promptgate:8000/metrics`** añadido a `prometheus.yml` global.

### Criterios de aceptación
- Trazas/métricas de PromptGate en Grafana global.
- Dashboard `promptgate-gateway` con métricas reales (latencias, errores).

---

## Fase 5 — Consolidación y limpieza

### Tareas
- [ ] **Retirar stack `observability-*` viejo** (`/opt/panchoserver` muerto): `docker compose down` + borrar volúmenes, previa comprobación de que nada depende.

- [ ] **Actualizar `AGENTS.md` de `~/code`** con la sección de observabilidad global (path, servicios, cómo conectar un proyecto nuevo).

- [ ] **Documento runbook:** `docs/runbook-observabilidad.md` (arranque, verificación, resolución de problemas, rotación de password Grafana).

- [ ] **Opcional:** alertmanager + rutas (email/webhook) y re-adopción de node-exporter/cadvisor para métricas de infra.

### Criterios de aceptación
- `docker ps` muestra **un solo** stack de observabilidad (`observability-*` nuevo) + apps.
- `AGENTS.md` actualizado y consistente.
- README/runbook operativo.

---

## Orden de Ejecución Sugerido

1. **Fase 1** (stack global) → verificación autónoma.
2. **Fase 2** (MisAgentes) → primer consumidor real; valida logs + métricas + trazas.
3. **Fase 3** (PromptGate logs) → segundo proyecto conectado.
4. **Fase 5** (limpieza) → retirada de obsoletos + docs.
5. **Fase 4** (PromptGate instrumentación) → iteración opcional siguiente.

---

## Notas Adicionales

- **Fase 0** (aprobación) es bloqueante para iniciar la Fase 1.
- Las fases 2 y 3 pueden solaparse parcialmente (PromptGate logs no requiere cambios en código).
- La Fase 4 es **opcional** y puede posponerse; el plan original la deja para una iteración posterior.
- La Fase 5 depende de que las fases 2 y 3 estén validadas y de que no queden dependencias en los stacks viejos.

---

## Próximos Pasos Inmediatos

1. Obtener aprobación de la Fase 0.
2. Ejecutar tareas de la Fase 1 (crear estructura, configs, red, verify.sh).
3. Validar con `scripts/verify.sh` antes de pasar a Fase 2.