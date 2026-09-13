# Especificación — Estructura de Carpetas para Dashboards de Grafana

> **Propósito:** Guía de diseño para organizar los dashboards de Grafana por aplicación.
> **Uso:** Crear, mantener y documentar dashboards dentro del stack observabilidad global.

---

## Estructura base

```
grafana/
├── provisioning/
│   ├── dashboards/           # Carpeta con archivos .json de dashboards
│   │   ├── misagentes/       # Dashboardes de MisAgentes
│   │   │   ├── engine-multiagente.json
│   │   │   └── ...
│   │   └── promptgate/       # Dashboardes de PromptGate
│   │       ├── gateway-llm.json
│   │       └── ...
│   └── datasources/          # Carpeta con archivos .yml de datasources
│       ├── prometheus.yml
│       ├── tempo.yml
│       └── loki.yml
```

---

## Carpeta por app

Cada carpeta de app debe contener **solo** los dashboards asociados a esa aplicación.

### `misagentes/`
- Dashboardes del motor multiagente de MisAgentes.
- Ejemplo: `engine-multiagente.json` (metadatos, uso de CPU, memoria, sesiones).
- **Esquema mínimo:** todo el dashboard debe tener `uid`, `title`, y paneles con métricas de uso del sistema.

### `promptgate/`
- Dashboardes de la gateway LLM de PromptGate.
- Ejemplo: `gateway-llm.json` (tasa de requests, errores, severidad, health).
- **Esquema mínimo:** todo el dashboard debe tener `uid`, `title`, y paneles de latencia, errores y métricas de health.

---

## Reglas de diseño

1. **Carpetas por app:** cada carpeta es independiente y contiene **solo** dashboards de esa app.
2. **Nombres:** `{nombre-app}-{descripcion}.json` (ej. `engine-multiagente.json`).
3. **Autor:** el archivo JSON debe definir `uid`, `title` y `panels` con metas de núcleo.
4. **Sección de datos:** dentro de cada dashboard, definición de paneles con querys, series y opciones de visualización.
5. **Sin duplicados:** no compartes dashboards entre carpetas de app diferentes.

---

## Estructura JSON mínima de un dashboard

```json
{
  "uid": "misagentes-engine",
  "title": "MisAgentes — Engine Multiagente",
  "tags": ["misagentes", "engine"],
  "panels": [
    {
      "type": "stat",
      "title": "Uso de CPU",
      "datasource": "Prometheus",
      "query": "rate(node_cpu_seconds_total{mode='idle'}[5m])"
    }
  ]
}
```

---

## Esquema de nodos

| Nodo | Propósito |
|------|-----------|
| `grafana/provisioning/dashboards/` | Archivos JSON de dashboards (automatizados por script) |
| `grafana/provisioning/datasources/` | Archivos YAML de datasources (Prometheus, Tempo, Loki) |
| `grafana/provisioning/dashboards/misagentes/` | Dashboardes de MisAgentes |
| `grafana/provisioning/dashboards/promptgate/` | Dashboardes de PromptGate |

---

## Checklist

- [ ] Carpeta `misagentes/` creada con `engine-multiagente.json`.
- [ ] Carpeta `promptgate/` creada con `gateway-llm.json`.
- [ ] Dashboard JSON validado (ejecución `grafana-cli dashboards import`).
- [ ] Dashboards visibles en la interfaz de Grafana (API `GET /api/dashboards/uid/{uid}`).
- [ ] Métricas de paneles accesibles y sin errores.