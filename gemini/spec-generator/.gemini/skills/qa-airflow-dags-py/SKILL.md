# QA Airflow DAGs Skill

Estándares y procedimientos para asegurar la calidad en proyectos de Apache Airflow con Python. Este skill define una arquitectura de pruebas rigurosa que debe seguirse incluso si el repositorio actual presenta desviaciones.

## Tecnologías de Testing

- **Apache Airflow**: Para DagBag testing e integridad de orquestación.
- **pytest**: Framework principal de pruebas.
- **unittest.mock / pytest-mock**: Para el aislamiento de tareas y servicios externos.

## Arquitectura de Pruebas Obligatoria

### 1. Pruebas de Integración (Integridad de DAGs)
Validan que el DAG sea parseable, no tenga ciclos y cumpla con los metadatos requeridos (tags, owner, catchup).

- **Ubicación**: `tests/dags/{folder_dag_name}/test_{dag_id}.py`
- **Patrón**: Utilizar `DagBag` para verificar `import_errors`.

### 2. Pruebas Unitarias (Lógica por Capas)
Toda la lógica de procesamiento debe estar desacoplada del DAG y probada unitariamente. Los tests deben organizarse obligatoriamente siguiendo la estructura de capas del pipeline.

- **Ubicación**: `tests/scripts/python/{folder_dag_name}/{layer}/{file_name}/test_{function_name}_from_{class_name}.py`
- **Capas Definidas**:
  * `extraction`: Lógica de obtención de datos y adaptadores.
  * `transformation`: Lógica de limpieza, agregación y cálculo de métricas.
  * `load`: Lógica de persistencia y carga en destino.
  * `orchestration`: Lógica de soporte a la ejecución (runtime, sensores).
  * `common`: Utilidades compartidas y manejo de excepciones.

## Patrón de Diseño: AAA (Arrange-Act-Assert)

Todos los tests deben seguir obligatoriamente la estructura **AAA** para garantizar legibilidad y mantenibilidad:

1.  **Arrange (Organizar)**: Configurar el entorno, instanciar objetos y preparar Mocks.
2.  **Act (Actuar)**: Ejecutar la función o método que se está probando.
3.  **Assert (Afirmar)**: Verificar que el resultado obtenido es el esperado y que las interacciones con los mocks fueron correctas.

### Ejemplo con Patrón AAA:
```python
def test_should_calculate_sum_when_valid_input(self):
    # Arrange
    data = [10, 20, 30]
    expected_result = 60
    calculator = MetricsCalculator()

    # Act
    result = calculator.sum_values(data)

    # Assert
    assert result == expected_result
```

## Reglas de Nomenclatura
- **Archivo**: `test_{function_name}_from_{class_name}.py`
- **Clase**: `Test{FunctionName}From{ClassName}`
- **Función**: `test_should_{expected_behavior}_when_{condition}`

## Requerimientos de Calidad
- **Aislamiento**: No se permiten conexiones reales a BD o APIs en tests unitarios.
- **Cobertura**: >90% en capas de `transformation` y `extraction`.
- **Integridad**: 100% de los DAGs deben pasar el test de carga.
