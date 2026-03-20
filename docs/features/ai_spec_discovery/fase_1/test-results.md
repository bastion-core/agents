# AI Spec Discovery Fase 1 — Resultados de Validacion

**Fecha**: 2026-03-20
**Estado**: PENDIENTE (requiere Gemini CLI instalado para ejecucion manual)

## Tests de Validacion

| # | Test | Descripcion | Status | Notas |
|---|------|------------|--------|-------|
| 1 | Carga de subagents | Ejecutar `gemini` en `gemini/spec-generator/` y verificar que @product y @architect estan disponibles | PENDIENTE | |
| 2 | @product single prompt | Invocar @product con toda la info en un solo prompt -> genera feature.yaml en 1 turno | PENDIENTE | |
| 3 | @product con preguntas | Invocar @product sin stack -> pregunta datos faltantes | PENDIENTE | |
| 4 | @product escritura a disco | Verificar que feature.yaml se escribe al filesystem via write_file | PENDIENTE | |
| 5 | @architect con feature.yaml | Invocar @architect con ruta a feature.yaml -> genera technical.yaml | PENDIENTE | |
| 6 | @architect con repo local | Invocar @architect con ruta a repo local -> explora estructura y refleja patrones | PENDIENTE | |
| 7 | @architect escritura a disco | Verificar que technical.yaml se escribe al filesystem via write_file | PENDIENTE | |
| 8 | Convenciones Python | Spec tecnica para python_fastapi incluye Hexagonal Architecture, Interactor, Repository ABC | PENDIENTE | |
| 9 | Convenciones Next.js | Spec tecnica para nextjs incluye Two-layer Architecture, Either, DataAccess | PENDIENTE | |
| 10 | Convenciones Flutter | Spec tecnica para flutter incluye Clean Architecture 4 capas, BLoC, Result<T> | PENDIENTE | |
| 11 | Compatibilidad feature.yaml | feature.yaml generado es consumible por agente architect de Claude Code | PENDIENTE | |
| 12 | Compatibilidad technical.yaml | technical.yaml generado es consumible por agente architect de Claude Code para tareas | PENDIENTE | |
| 13 | Orquestacion secuencial | Despues de @product, el agente principal sugiere usar @architect | PENDIENTE | |
| 14 | Documentacion README | Nuevo miembro puede instalar y generar primera spec siguiendo el README en <10 min | PENDIENTE | |

## Instrucciones de Ejecucion

Para ejecutar estos tests, necesitas:

1. Gemini CLI instalado y configurado
2. Credenciales GCP validas (ADC o Service Account)
3. Proyecto GCP con Vertex AI habilitado

```bash
cd gemini/spec-generator/
gemini
```

Ejecutar cada test secuencialmente y actualizar la columna "Status" con PASS o FAIL.
