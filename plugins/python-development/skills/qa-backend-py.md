---
name: qa-backend-py
description: Procedimientos de QA para Python backend, incluyendo unit tests, integración y cobertura >90%.
model: sonnet
color: green
---
# QA Backend Python Skill

Estándares y procedimientos para asegurar la calidad en aplicaciones backend Python, enfocados en pruebas unitarias, de integración e ingeniería del caos. El objetivo es certificar entregas con **cobertura de código >90%**.

## Tecnologías de Testing

- **pytest**: Framework principal con soporte async.
- **pytest-asyncio**: Para código async/await.
- **pytest-mock** / **unittest.mock**: Mocking y espionaje (MagicMock, AsyncMock, patch).
- **faker**: Generación de datos realistas.
- **coverage**: Medición y reporte de cobertura.
- **ChaosToolkit**: Experimentos de resiliencia.

## Arquitectura de Pruebas

El proyecto sigue una **estructura de espejo** de `src/`:

```
tests/
├── {domain}/
    ├── application/                   # Tests unitarios para interactores (casos de uso)
    │   ├── {interactor_name}/        # Directorio por archivo de interactor
    │   │   ├── test_{function_name}_from_{class_name}.py
    └── infrastructure/                # Tests de integración para rutas
        └── routes/
            └── v1/
                └── test_{route_name}_route.py
```

### Reglas de Nomenclatura

1. **Directorios**: Crear una carpeta con el nombre exacto del archivo fuente (sin `.py`).
   * Ejemplo: `src/application/interactors/payment_interactor.py` -> `tests/application/interactors/payment_interactor/`
2. **Archivos de Test**: `test_{function_name}_from_{class_name}.py`.
3. **Clases de Test**: PascalCase del nombre del archivo. `TestCalculateTotalFromPaymentProcessor`.
4. **Funciones de Test**: `test_should_{comportamiento_esperado}_when_{condicion}`.
5. **Un Archivo por Función**: Crear un archivo de test independiente por cada método público (excepto `__init__`).

## Estrategias de Testing

### 1. Pruebas Unitarias (Application & Domain)
- **Aislar** la lógica de negocio.
- **Sin conexiones** a BD o APIs externas (usar Mocks).
- Seguir el patrón **AAA** (Arrange-Act-Assert).
- **Async**: Usar `@pytest.mark.asyncio` y `AsyncMock`.

### 2. Pruebas de Integración (Infrastructure)
- Probar rutas HTTP y persistencia.
- **Obligatorio**: Heredar de `PytestBaseIntegrationTest`.
- Implementar `configure_setup` y `configure_teardown` para gestión de datos.
- Probar: Éxito (2xx), Errores Cliente (4xx), Auth (401/403) y BD.

### 3. Ingeniería del Caos (Opcional)
- Implementar para flujos críticos (pagos, alta disponibilidad).
- Definir `steady-state-hypothesis` y acciones de inyección de fallo (latencia, caídas de BD).

## Gestión de Datos
- Usar **Faker** para datos realistas.
- Utilizar **Mock Entity Factories** de `tests/mocks/entities/`.
- Limpiar datos en `configure_teardown` en orden inverso de dependencias.

## Requerimientos de Cobertura
- **Objetivo**: >90% total.
- **Rutas Críticas**: 100% (Pagos, Auth, Cálculos financieros).
- **Lógica de Negocio**: >95%.
- **Infraestructura**: >85%.

## Flujo de Trabajo
1. Analizar el código fuente e identificar métodos y casos de borde.
2. Crear la estructura de directorios y archivos de test.
3. Escribir tests en orden: Happy path -> Errores de validación -> Errores de negocio -> Excepciones -> Casos de borde.
4. Ejecutar con `pytest --cov=src` y revisar líneas faltantes.
