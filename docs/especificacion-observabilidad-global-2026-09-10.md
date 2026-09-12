# Observabilidad global — especificación técnica

**Proyecto:** `~/code/observability`
**Fecha:** 2026-09-10
**Estado:** propuesta; pendiente de aprobación
**Alcance:** un único stack de observabilidad para todos los proyectos de la notebook (inicialmente **MisAgentes** y **PromptGate**), con logs, métricas y trazas centralizadas.

---

## 1. Objetivo

Reemplazar la observabilidad dispersa (un stack por proyecto) por **un solo stack global** en `~/code/observability` que centralice:

- **Logs** de todos los contenedores (vía Docker socket → Alloy → Loki);
- **Métricas** (OTLP → otel-collector → Prometheus; más scrape directo de endpoints `/metrics`);
- **Trazas** (OTLP → otel-collector → Tempo);
- **Visualización** (Grafana con datasources provisionados para Prometheus, Tempo y Loki).

Los proyectos consumidores **no alojan observabilidad propia**: solo apuntan al stack global vía red Docker compartida y variables de entorno.

---

## 2. Estado actual (inventario verificado 2026-09-10)

Hay **tres** instalaciones coexistiendo:

| Stack | Ubicación compose | Estado | Uso real |
|---|---|---|---|
| `mis-agentes-*` | `~/code/deployment/apps/mis-agentes/docker-compose.yml` | nats, otel-collector, tempo, loki, alloy **Up**; prometheus y grafana **Created (nunca arrancaron)** | Es el stack del deploy actual; la UI (prometheus/grafana) **no funciona**. |
| `misagentes-*` | `~/code/MisAgentes/docker-compose.yml` (clon dev, 353 commits atrás) | prometheus y grafana **Up 7 semanas** | Stale, del clon dev; compite por puertos (9090). |
| `observability-*` | `/opt/panchoserver/docker-compose/observability/` (**directorio ya no existe**) | prometheus v3.1, grafana enterprise 12.4, loki, promtail, tempo, alertmanager, pushgateway, node-exporter, cadvisor **Up 2 meses** | Stack central viejo del host; sigue corriendo desde un path muerto. |

Redes Docker existentes: `mis-agentes_default`, `misagentes_default`, `observability`, `traefik-public`, `promptgate-default`, `promptgate_promptgate-network`.

### Flujo actual de telemetría por proyecto

**MisAgentes** (app en puerto 8010, red `mis-agentes_default`):
- `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317` → se envía al otel-collector **del propio proyecto**;
- `prometheus.yml` scrapea `otel-collector:8889` y `mis-agentes:8000`, pero el Prometheus del proyecto está **Created**, o sea, **nadie scrapea**;
- logs vía Alloy local del proyecto → Loki local del proyecto (funciona, pero solo de la red del proyecto).

**PromptGate** (app en puerto 9000, red `promptgate_promptgate-network`):
- **No expone OTEL ni `/metrics` Prometheus**; solo endpoints de negocio `/v1/admin/metrics/*` (200 OK verificado);
- logs: **ningún agente de logs lo cubre hoy** (ni Alloy ni promtail están en su red).

**Conclusión:** la telemetría de MisAgentes produce datos, pero **muere en el collector**: no hay Prometheus/Grafana del proyecto corriendo. El stack `observability-*` viejo recibe solo lo que el host genérico ve (node-exporter, cadvisor), no los traces/métricas de las apps.

---

## 3. Decisiones de diseño

1. **Un solo stack, un solo compose, una sola red.** Todo en `~/code/observability`, con red Docker compartida llamada `observability-net` (nombre estable). Los contenedores de los proyectos se unen a esa red **además** de la suya.
2. **Red compartida por `external`**, no publicación de puertos OTLP al host: los productores alcanzan `otel-collector`, `grafana`, `prometheus`, `loki` por nombre de servicio DNS Docker. Nada de OTLP expuesto a `0.0.0.0`.
3. **otl-collector como único punto de entrada OTLP.** Todos los proyectos emiten a `http://otel-collector:4317` (grpc). Un solo receptor, pipelines únicos.
4. **Prometheus scrapea por red compartida + push del collector.** Targets:
   - `otel-collector:8889` (métricas OTLP ya agregadas);
   - `http://mis-agentes:8000/metrics` (Prometheus client de MisAgentes);
   - futuros `/metrics` de otros proyectos.
5. **Logs centrales vía Alloy (no promtail)** — el stack existente de MisAgentes ya valida Alloy→Loki; se reutiliza la configuración, ahora con alcance global (un solo Alloy leyendo `/var/lib/docker/containers`).
6. **Grafana con provisioning por datasource** (Prometheus, Tempo, Loki) y dashboards por proyecto, versionados en el repo.
7. **Nombres de servicio estables**: `otel-collector`, `prometheus`, `tempo`, `loki`, `alloy`, `grafana` (prefijo del compose global `observability` en el nombre del contenedor: `observability-grafana-1`, etc.).
8. **Retención por defecto**: Prometheus 15d, Loki 168h (7d), Tempo 168h (7d) — conservando los valores ya usados.
9. **Docker socket de solo lectura** para Alloy: bind ro de `/var/run/docker.sock` y `/var/lib/docker/containers` (patrón ya probado en el stack actual).
10. **Migración sin downtime disruptivo**: primero se levanta el stack global, luego se re-apunta cada proyecto (env + red), y al final se **retiran** los stacks obsoletos.

---

## 4. Arquitectura objetivo

```text
┌─────────────────────────────── host ───────────────────────────────┐
│                                                                     │
│  red Docker compartida: observability-net                          │
│                                                                     │
│  ┌─ MisAgentes (compose propio, 8010) ─┐  ┌─ PromptGate (9000) ─┐  │
│  │  app ──OTLP──▶ otel-collector      │  │  app ──OTLP(prox.)─▶ │  │
│  │  app ──/metrics─▶ prometheus       │  │  app                 │  │
│  │  + se une a observability-net      │  │  + se une a obs-net  │  │
│  └────────────────────────────────────┘  └───────────────────────┘  │
│                    │                            │                  │
│                    └──────────────┬─────────────┘                  │
│                                   ▼                                │
│  ┌──────────────── observability-net ────────────────┐              │
│  │  otel-collector ──┬─▶ tempo (traces)              │              │
│  │                   └─▶ prometheus (métricas)       │              │
│  │  alloy ──(docker logs)─▶ loki (logs)              │              │
│  │  prometheus (scrape: collector:8889 + apps)       │              │
│  │  grafana ─ datasources: prometheus, tempo, loki   │              │
│  └───────────────────────────────────────────────────┘              │
│                                                                     │
│  puertos publicados SOLO: grafana (3000), prometheus (9090),        │
│  opcional pushgateway (sondeo), alertmanager (9093)                 │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 5. Componentes y configuración del stack global

### 5.1 Servicios

| Servicio | Imagen (pin) | Función |
|---|---|---|
| `otel-collector` | `otel/opentelemetry-collector-contrib:0.120.0` | Receptor OTLP 4317/4318; pipelines traces→Tempo, metrics→Prometheus |
| `tempo` | `grafana/tempo:2.7.2` | Almacenamiento de trazas |
| `prometheus` | `prom/prometheus:v3.2.1` | Métricas (push OTLP + scrape apps) |
| `loki` | `grafana/loki:3.4.2` | Logs centralizados |
| `alloy` | `grafana/alloy:v1.7.2` | Recolección de logs Docker → Loki |
| `grafana` | `grafana/grafana:11.5.2` | UI + dashboards (provisioning) |
| `alertmanager` *(opcional)* | `prom/alertmanager:v0.27.0` | Alertas desde Prometheus |

### 5.2 Red

```yaml
networks:
  default: {}
  observability-net:
    driver: bridge
    name: observability-net      # nombre estable compartido
```

Los proyectos consumidores declaran en su compose:

```yaml
networks:
  default: {}
  observability-net:
    external: true
    name: observability-net
```

y el servicio de la app se une a **ambas**:

```yaml
services:
  app:
    networks: [default, observability-net]
```

### 5.3 Variables de entorno por proyecto (contrato de conexión)

**MisAgentes** (editar `.env` del deploy):

```env
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317
OTEL_SERVICE_NAME=mis-agentes
OTEL_RESOURCE_ATTRIBUTES=service.namespace=mis-agentes
OTEL_SDK_DISABLED=false
```

**PromptGate** (no escribe OTEL hoy; primera fase: solo logs + dashboard. Fase 2: instrumentación):

- logs capturados automáticamente por Alloy global;
- sin cambios de env iniciales; se agrega `/metrics` Prometheus o exporter OTEL en fase 2 del plan.

### 5.4 otel-collector (config global)

```yaml
receivers:
  otlp:
    protocols:
      grpc: { endpoint: 0.0.0.0:4317 }
      http:  { endpoint: 0.0.0.0:4318 }

exporters:
  otlp/tempo:
    endpoint: tempo:4317
    tls: { insecure: true }
  prometheus:
    endpoint: 0.0.0.0:8889

service:
  pipelines:
    traces:
      receivers: [otlp]
      exporters: [otlp/tempo]
    metrics:
      receivers: [otlp]
      exporters: [prometheus]
```

### 5.5 Prometheus (config global)

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
scrape_configs:
  - job_name: otel-collector
    static_configs:
      - targets: [otel-collector:8889]
  - job_name: mis-agentes
    static_configs:
      - targets: [mis-agentes:8000]
  # fase 2: promptgate cuando exponga /metrics
```

### 5.6 Alloy (config global)

Misma que la validada en MisAgentes: `local.file_match` sobre `/var/lib/docker/containers/*/*-json.log` → `loki.write` a `http://loki:3100/loki/api/v1/push`. Un solo Alloy con Docker socket ro cubre **todos** los contenedores del host (no solo la red del proyecto).

### 5.7 Grafana provisioning

- **Datasources**: Prometheus (`http://prometheus:9090`), Tempo (`http://tempo:3200`), Loki (`http://loki:3100`).
- **Dashboards versionados**: `grafana/provisioning/dashboards/` con al menos:
  - `misagentes-engine` (reusado del actual `grafana-dashboard.json`);
  - `promptgate-gateway` (métricas de rutas/errores, fase 2 cuando haya datos);
  - `system-infra` (node-exporter, cadvisor si se re-adoptan).

---

## 6. Seguridad

- OTLP, Tempo y Loki **no se publican al host**: solo en `observability-net`.
- Puertos publicados: `grafana 3000` y `prometheus 9090` (lectura); si hace falta, bind a `127.0.0.1` o detrás de traefik-public existente.
- Grafana: admin con password desde `.env` (`GRAFANA_ADMIN_PASSWORD`), sin sign-up, anónimo desactivado.
- Docker socket a Alloy en **solo lectura** (bind `:ro`).
- Retención acotada (7-15 días) para limitar superficie y costo de disco.

---

## 7. Migración (alto nivel)

1. **Crear** `~/code/observability` con compose + configs (este repo).
2. **Levantar** el stack global; verificar: `curl prometheus:9090`, `curl grafana:3000/api/health`, datasources OK.
3. **MisAgentes**: unir app a `observability-net`, apuntar `OTEL_EXPORTER_OTLP_ENDPOINT` al collector global, reiniciar contenedores. Quitar/desactivar servicios de observabilidad del compose del proyecto (o dejarlos `profiles: [legacy]`).
4. **PromptGate fase 1**: solo logs (Alloy global ya lo cubre) + dashboard básico.
5. **Retirar** stacks obsoletos: `misagentes-*`, `observability-*` (path muerto), comprobar que ningún recurso las use.
6. **Verificar end-to-end**: generar tráfico en MisAgentes, confirmar trazas en Tempo, métricas en Prometheus, logs en Loki, dashboards en Grafana.

---

## 8. Fuera de alcance (fases posteriores)

- Instrumentación OTEL de PromptGate (emisión de traces/métricas) — plan de acción fase 2.
- Alerting (alertmanager + rutas) — habilitar tras validar dashboards.
- Multitenancy de Grafana por proyecto (orgs/folders). Se escala después.
- Re-adopción de node-exporter/cadvisor del stack viejo (métricas de infra) — opcional.