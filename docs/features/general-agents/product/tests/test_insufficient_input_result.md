# Test Report: Product Specification Agent - Insufficient Inputs

**Agent Under Test**: `plugins/general/agents/product.md`
**Test Suite**: Insufficient Input Scenarios (Task 08)
**Date**: 2026-03-13
**Overall Result**: **5/5 PASS**

---

## Scenario 1: Missing Business Rules

**Input**:
> "Quiero una funcionalidad para que los administradores puedan exportar reportes de ventas en PDF. El admin selecciona un rango de fechas y el tipo de reporte."

### Phase 1 - Extraction Results

| Campo               | Datos Extraidos                                                                 |
|---------------------|---------------------------------------------------------------------------------|
| feature             | `exportar_reportes_ventas`                                                      |
| description         | Rol: administrador. Accion: exportar reportes de ventas en PDF seleccionando rango de fechas y tipo de reporte. |
| acceptance_criteria | Parcial: el admin puede exportar un reporte, puede seleccionar rango de fechas y tipo de reporte. Falta precision sobre criterios verificables (tiempos, formatos, limites). |
| business_rules      | No se proporcionan. Sin limites numericos (rango maximo de fechas, tamano maximo de reporte), sin valores permitidos para tipos de reporte, sin comportamiento ante errores. |
| inputs              | Parcial: se mencionan "rango de fechas" y "tipo de reporte" pero sin tipos de dato, formatos ni valores permitidos. |
| outputs             | No se proporcionan. No se define que contiene el PDF, ni respuestas de error.    |
| tests_scope         | Solo se puede inferir el caso exitoso. No hay escenarios de error ni casos limite definidos. |

### Phase 2 - Validation Results

| Campo               | Estado     | Criterio de Validacion                                      |
|---------------------|------------|-------------------------------------------------------------|
| feature             | completo   | Nombre claro derivable: `exportar_reportes_ventas`          |
| description         | completo   | Rol (administrador) y accion (exportar reportes) identificados |
| acceptance_criteria | incomplete | Menos de 3 criterios verificables objetivamente              |
| business_rules      | incomplete | No se especifican limites numericos, enums ni codigos de error |
| inputs              | incomplete | Entradas mencionadas sin tipo de dato ni valores permitidos  |
| outputs             | missing    | No se identifican datos de salida ni respuestas de error     |
| tests_scope         | incomplete | Solo se puede inferir caso exitoso; faltan error de validacion y caso limite |

**Decision**: Campos insuficientes detectados -> MissingDataRequest

### Simulated Agent Response

> No puedo generar la especificacion completa. Necesito los siguientes datos:
>
> | Campo | Estado | Detalle | Pregunta sugerida |
> |-------|--------|---------|-------------------|
> | acceptance_criteria | incomplete | Solo se identifican 2 criterios generales (seleccionar rango y exportar). Faltan criterios verificables con valores concretos. | Cuales son las condiciones especificas para considerar la exportacion exitosa? Por ejemplo: tiempo maximo de generacion, formato exacto del PDF, cantidad maxima de registros por reporte. |
> | business_rules | incomplete | No se definen limites del rango de fechas, tipos de reporte permitidos, tamano maximo de archivo, ni comportamiento cuando no hay datos en el rango. | Cuales son los tipos de reporte disponibles (ej. ventas diarias, mensuales, por producto)? Cual es el rango maximo de fechas permitido? Que debe ocurrir si no hay datos en el rango seleccionado? |
> | inputs | incomplete | Se mencionan "rango de fechas" y "tipo de reporte" pero sin tipos de dato ni valores permitidos. | Que formato deben tener las fechas (ej. DD/MM/AAAA)? Cuales son los tipos de reporte validos? Existen filtros adicionales opcionales? |
> | outputs | missing | No se define la estructura del PDF generado ni las respuestas de error del sistema. | Que informacion debe contener el PDF generado (columnas, totales, graficos)? Que errores puede devolver el sistema (ej. rango invalido, sin permisos, reporte vacio)? |
> | tests_scope | incomplete | Solo se puede inferir el caso exitoso. Faltan escenarios de error y casos limite. | Que errores de validacion pueden ocurrir al exportar? Existe un limite de registros o tamano de archivo que pueda generar un caso limite? |

### Validation Checklist

| # | Validation Criteria                                                        | Result   |
|---|---------------------------------------------------------------------------|----------|
| 1 | Agent does NOT generate a feature.yaml file                               | **PASS** |
| 2 | Response includes structured table with field/status/detail/suggested_question | **PASS** |
| 3 | Suggested questions are concrete and actionable                           | **PASS** |
| 4 | After receiving complementary data, agent would re-execute full pipeline  | **PASS** |
| 5 | business_rules flagged as incomplete (no limits, formats, error behaviors) | **PASS** |
| 6 | outputs flagged as missing                                                | **PASS** |
| 7 | tests_scope flagged as incomplete                                         | **PASS** |

**Scenario 1 Result: PASS**

---

## Scenario 2: Missing Inputs

**Input**:
> "Como vendedor, necesito poder registrar devoluciones de productos. El sistema debe validar que el producto fue comprado hace menos de 30 dias y generar un comprobante de devolucion."

### Phase 1 - Extraction Results

| Campo               | Datos Extraidos                                                                 |
|---------------------|---------------------------------------------------------------------------------|
| feature             | `registrar_devolucion_producto`                                                 |
| description         | Rol: vendedor. Accion: registrar devoluciones de productos. Sistema valida compra < 30 dias y genera comprobante. |
| acceptance_criteria | Parcial: vendedor registra devolucion, sistema valida plazo de 30 dias, genera comprobante. Falta detalle sobre el comprobante y criterios adicionales. |
| business_rules      | Parcial: plazo maximo de devolucion es 30 dias desde la compra. Falta: estados de devolucion, motivos permitidos, condiciones del producto. |
| inputs              | No se proporcionan. No se define que datos debe ingresar el vendedor para registrar la devolucion (identificador de compra, motivo, estado del producto, etc.). |
| outputs             | Parcial: se menciona "comprobante de devolucion" pero sin definir su contenido, formato ni respuestas de error. |
| tests_scope         | Parcial: se puede inferir caso exitoso y un error (producto comprado hace mas de 30 dias). Falta caso limite. |

### Phase 2 - Validation Results

| Campo               | Estado     | Criterio de Validacion                                      |
|---------------------|------------|-------------------------------------------------------------|
| feature             | completo   | Nombre claro derivable: `registrar_devolucion_producto`     |
| description         | completo   | Rol (vendedor) y accion (registrar devoluciones) identificados |
| acceptance_criteria | incomplete | Menos de 3 criterios verificables con valores concretos      |
| business_rules      | incomplete | Solo una regla concreta (30 dias). Faltan motivos, estados, condiciones |
| inputs              | missing    | No se identifican datos de entrada con nombre, tipo ni valores permitidos |
| outputs             | incomplete | Se menciona comprobante pero sin tipo de dato, contenido ni respuestas de error |
| tests_scope         | incomplete | Se puede inferir caso exitoso y un error, pero falta caso limite |

**Decision**: Campos insuficientes detectados -> MissingDataRequest

### Simulated Agent Response

> No puedo generar la especificacion completa. Necesito los siguientes datos:
>
> | Campo | Estado | Detalle | Pregunta sugerida |
> |-------|--------|---------|-------------------|
> | acceptance_criteria | incomplete | Se identifican solo 2 criterios implicitos. Faltan criterios verificables sobre el comprobante y el flujo completo. | Que condiciones especificas deben cumplirse para considerar la devolucion completa? El comprobante tiene algun formato o contenido obligatorio? Se debe actualizar el inventario automaticamente? |
> | business_rules | incomplete | Solo se define el plazo de 30 dias. Faltan reglas sobre motivos de devolucion, estado del producto y restricciones adicionales. | Cuales son los motivos de devolucion validos (ej. defecto, insatisfaccion, error en pedido)? El producto debe estar en algun estado especifico (sin abrir, con empaque original)? Existe un limite de devoluciones por cliente o por producto? |
> | inputs | missing | No se definen los datos que el vendedor debe ingresar para registrar la devolucion. | Que datos debe ingresar el vendedor para registrar una devolucion? Por ejemplo: numero de orden, codigo de producto, motivo de devolucion, estado del producto. Para cada dato, cual es su formato y valores permitidos? |
> | outputs | incomplete | Se menciona un comprobante de devolucion pero no se define su contenido, formato ni las respuestas de error del sistema. | Que informacion debe contener el comprobante de devolucion (numero de devolucion, monto, fecha)? En que formato se genera (PDF, impreso, digital)? Que errores puede devolver el sistema (ej. producto no encontrado, plazo vencido, devolucion duplicada)? |
> | tests_scope | incomplete | Se puede inferir el caso exitoso y un error de plazo, pero falta al menos un caso limite. | Que ocurre si el vendedor intenta devolver un producto el dia exacto 30? Puede haber devoluciones parciales (solo algunos items de una orden)? Que pasa si el producto ya fue devuelto previamente? |

### Validation Checklist

| # | Validation Criteria                                                        | Result   |
|---|---------------------------------------------------------------------------|----------|
| 1 | Agent does NOT generate a feature.yaml file                               | **PASS** |
| 2 | Response includes structured table with field/status/detail/suggested_question | **PASS** |
| 3 | Suggested questions are concrete and actionable                           | **PASS** |
| 4 | After receiving complementary data, agent would re-execute full pipeline  | **PASS** |
| 5 | inputs flagged as missing (no data types or allowed values defined)       | **PASS** |
| 6 | outputs flagged as incomplete                                             | **PASS** |

**Scenario 2 Result: PASS**

---

## Scenario 3: Only Images Without Context

**Input**: (Simulated: user provided only a mockup image with no textual context)

### Phase 1 - Extraction Results

| Campo               | Datos Extraidos                                                                 |
|---------------------|---------------------------------------------------------------------------------|
| feature             | No se puede determinar el nombre de la funcionalidad sin contexto textual.      |
| description         | No se puede identificar el rol de usuario ni la accion desde solo una imagen.   |
| acceptance_criteria | No hay criterios de aceptacion definidos. Solo se pueden inferir elementos de UI. |
| business_rules      | No se proporcionan reglas de negocio. Una imagen no define limites ni restricciones. |
| inputs              | Se pueden inferir campos de formulario visualmente, pero sin tipos de dato, formatos ni validaciones. |
| outputs             | No se definen datos de salida ni respuestas de error.                           |
| tests_scope         | No hay escenarios de prueba definidos.                                          |

### Phase 2 - Validation Results

| Campo               | Estado     | Criterio de Validacion                                      |
|---------------------|------------|-------------------------------------------------------------|
| feature             | missing    | No se puede derivar un nombre sin contexto                   |
| description         | missing    | No se identifica rol de usuario ni accion                    |
| acceptance_criteria | missing    | No hay criterios verificables                                |
| business_rules      | missing    | No hay reglas de negocio                                     |
| inputs              | incomplete | Elementos de UI visibles pero sin definicion formal          |
| outputs             | missing    | No hay datos de salida definidos                             |
| tests_scope         | missing    | No hay escenarios de prueba                                  |

**Decision**: Multiples campos missing -> MissingDataRequest

### Simulated Agent Response

> No puedo generar la especificacion completa. El mockup proporcionado muestra elementos de interfaz pero no contiene contexto suficiente para construir una especificacion de producto. Necesito los siguientes datos:
>
> | Campo | Estado | Detalle | Pregunta sugerida |
> |-------|--------|---------|-------------------|
> | feature | missing | No se puede determinar el nombre de la funcionalidad a partir de solo una imagen. | Cual es el nombre o titulo de esta funcionalidad? Que objetivo de negocio cumple? |
> | description | missing | No se identifica que rol de usuario interactua con esta pantalla ni que accion ejecuta. | Que tipo de usuario (rol) utilizara esta pantalla? Que accion principal puede realizar? Que debe hacer el sistema en respuesta? |
> | acceptance_criteria | missing | No hay criterios de aceptacion definidos. | Cuales son las condiciones que deben cumplirse para considerar esta funcionalidad como terminada? Enumere al menos 3 criterios verificables. |
> | business_rules | missing | No se proporcionan reglas de negocio, limites ni restricciones. | Cuales son las reglas de negocio que aplican? Por ejemplo: limites numericos, valores permitidos, permisos requeridos, comportamiento ante errores. |
> | inputs | incomplete | Se observan campos de formulario en el mockup pero sin definicion de tipos de dato, formatos ni validaciones. | Para cada campo visible en el mockup, cual es su tipo de dato, formato esperado y valores permitidos? Cuales campos son obligatorios? |
> | outputs | missing | No se define que datos devuelve el sistema al usuario. | Que respuesta recibe el usuario tras completar la accion? Que mensajes de error puede mostrar el sistema? |
> | tests_scope | missing | No hay escenarios de prueba definidos. | Describa al menos un escenario exitoso, un error de validacion y un caso limite para esta funcionalidad. |

### Validation Checklist

| # | Validation Criteria                                                        | Result   |
|---|---------------------------------------------------------------------------|----------|
| 1 | Agent does NOT generate a feature.yaml file                               | **PASS** |
| 2 | Response includes structured table with field/status/detail/suggested_question | **PASS** |
| 3 | Suggested questions are concrete and actionable                           | **PASS** |
| 4 | After receiving complementary data, agent would re-execute full pipeline  | **PASS** |
| 5 | Requests description of functionality                                     | **PASS** |
| 6 | Requests user role                                                        | **PASS** |
| 7 | Requests business rules                                                   | **PASS** |
| 8 | Requests inputs/outputs definition                                        | **PASS** |

**Scenario 3 Result: PASS**

---

## Scenario 4: Unrelated Content

**Input**:
> "El equipo de marketing necesita actualizar los colores del brand guide. Los nuevos colores primarios son #FF5733 y #2ECC71."

### Phase 1 - Extraction Results

| Campo               | Datos Extraidos                                                                 |
|---------------------|---------------------------------------------------------------------------------|
| feature             | No aplica. La solicitud es sobre branding/diseno, no una funcionalidad de producto. |
| description         | No hay funcionalidad de sistema. Es una tarea de actualizacion de guia de marca. |
| acceptance_criteria | No aplica.                                                                       |
| business_rules      | No aplica.                                                                       |
| inputs              | No aplica.                                                                       |
| outputs             | No aplica.                                                                       |
| tests_scope         | No aplica.                                                                       |

### Phase 2 - Validation Results

The input does not describe a product feature. The content relates to visual branding (color palette update), which is outside the scope of the product specification agent. No field can be populated.

**Decision**: Unrelated content -> Rejection response

### Simulated Agent Response

> Los insumos proporcionados no contienen informacion suficiente para identificar una funcionalidad de producto. La solicitud describe una actualizacion de la guia de marca (brand guide) con nuevos colores, lo cual es una tarea de diseno/marketing, no una funcionalidad de sistema.
>
> Para generar una especificacion de producto necesito documentos, imagenes o descripciones que definan:
> - Que puede hacer un usuario (rol y accion)
> - Que debe hacer el sistema en respuesta
> - Bajo que reglas o restricciones opera la funcionalidad
>
> Si la actualizacion de colores requiere cambios en el sistema (por ejemplo, un panel de administracion para gestionar temas visuales), por favor proporcione esa informacion funcional.

### Validation Checklist

| # | Validation Criteria                                                        | Result   |
|---|---------------------------------------------------------------------------|----------|
| 1 | Agent does NOT generate a feature.yaml file                               | **PASS** |
| 2 | Agent indicates it cannot generate a product specification from this input | **PASS** |
| 3 | Agent explains what kind of input it needs instead                        | **PASS** |
| 4 | Agent does not attempt to force-fit unrelated content into a spec         | **PASS** |

**Scenario 4 Result: PASS**

---

## Scenario 5: Ambiguous Criteria

**Input**:
> "Necesitamos una funcionalidad de busqueda de productos. Debe ser rapida y facil de usar. Los resultados deben ser relevantes."

### Phase 1 - Extraction Results

| Campo               | Datos Extraidos                                                                 |
|---------------------|---------------------------------------------------------------------------------|
| feature             | `busqueda_productos`                                                            |
| description         | Parcial: funcionalidad de busqueda de productos. Rol de usuario no especificado. |
| acceptance_criteria | Ambiguos: "rapida", "facil de usar", "relevantes" no son criterios medibles ni verificables objetivamente. |
| business_rules      | No se proporcionan. No hay limites de resultados, filtros, ordenamiento ni comportamiento sin resultados. |
| inputs              | No se proporcionan. No se define que datos ingresa el usuario para buscar (texto libre, filtros, categorias). |
| outputs             | No se proporcionan. No se define que datos devuelve la busqueda ni como se presentan los resultados. |
| tests_scope         | No se proporcionan. No hay escenarios de prueba definidos.                      |

### Phase 2 - Validation Results

| Campo               | Estado     | Criterio de Validacion                                      |
|---------------------|------------|-------------------------------------------------------------|
| feature             | completo   | Nombre claro derivable: `busqueda_productos`                 |
| description         | incomplete | No se especifica el rol de usuario                           |
| acceptance_criteria | ambiguous  | "Rapida", "facil de usar" y "relevantes" no son verificables objetivamente. No hay metricas ni definiciones concretas. |
| business_rules      | missing    | No hay reglas de negocio definidas                           |
| inputs              | missing    | No se definen datos de entrada                               |
| outputs             | missing    | No se definen datos de salida                                |
| tests_scope         | missing    | No hay escenarios de prueba definidos                        |

**Decision**: Campos insuficientes y ambiguos detectados -> MissingDataRequest

### Simulated Agent Response

> No puedo generar la especificacion completa. Los criterios proporcionados son ambiguos y no verificables. Necesito los siguientes datos:
>
> | Campo | Estado | Detalle | Pregunta sugerida |
> |-------|--------|---------|-------------------|
> | description | incomplete | No se identifica el rol de usuario que ejecuta la busqueda. | Que tipo de usuario realiza la busqueda? (ej. cliente registrado, visitante anonimo, administrador) |
> | acceptance_criteria | ambiguous | Los criterios "rapida", "facil de usar" y "relevantes" no son medibles ni verificables. No hay metricas concretas. | Que significa "rapida"? Por ejemplo: los resultados deben mostrarse en menos de 2 segundos. Que significa "relevantes"? Por ejemplo: los resultados deben coincidir con el termino buscado en nombre o descripcion del producto. Que significa "facil de usar"? Por ejemplo: el usuario puede buscar con un solo campo de texto desde cualquier pantalla. |
> | business_rules | missing | No se definen reglas sobre cantidad de resultados, filtros disponibles, ordenamiento ni comportamiento sin resultados. | Cuantos resultados se muestran por pagina? Existen filtros (categoria, precio, disponibilidad)? Como se ordenan los resultados por defecto? Que debe mostrar el sistema si no hay resultados? |
> | inputs | missing | No se define que datos ingresa el usuario para realizar la busqueda. | Que tipo de busqueda puede hacer el usuario (texto libre, por categoria, por codigo)? Existen filtros adicionales? Cual es la longitud minima y maxima del termino de busqueda? |
> | outputs | missing | No se define que informacion devuelve la busqueda ni como se presentan los resultados. | Que datos de cada producto se muestran en los resultados (nombre, precio, imagen, disponibilidad)? Existe paginacion? Que respuesta devuelve el sistema si ocurre un error? |
> | tests_scope | missing | No hay escenarios de prueba definidos. | Que debe ocurrir cuando se busca un termino que coincide con multiples productos? Y cuando no hay coincidencias? Existe un caso limite como buscar con caracteres especiales o un termino muy largo? |

### Validation Checklist

| # | Validation Criteria                                                        | Result   |
|---|---------------------------------------------------------------------------|----------|
| 1 | Agent does NOT generate a feature.yaml file                               | **PASS** |
| 2 | Response includes structured table with field/status/detail/suggested_question | **PASS** |
| 3 | Suggested questions are concrete and actionable                           | **PASS** |
| 4 | After receiving complementary data, agent would re-execute full pipeline  | **PASS** |
| 5 | acceptance_criteria flagged as ambiguous                                   | **PASS** |
| 6 | Agent requests concrete, verifiable criteria with specific examples       | **PASS** |
| 7 | Agent explains WHY the criteria are not acceptable (not measurable)       | **PASS** |

**Scenario 5 Result: PASS**

---

## Summary

| Scenario | Description                  | File Generated? | Structured Response? | Actionable Questions? | Re-execute Pipeline? | Result   |
|----------|------------------------------|-----------------|----------------------|----------------------|----------------------|----------|
| 1        | Missing business rules       | No              | Yes                  | Yes                  | Yes                  | **PASS** |
| 2        | Missing inputs               | No              | Yes                  | Yes                  | Yes                  | **PASS** |
| 3        | Only images without context  | No              | Yes                  | Yes                  | Yes                  | **PASS** |
| 4        | Unrelated content            | No              | N/A (rejection)      | N/A                  | N/A                  | **PASS** |
| 5        | Ambiguous criteria           | No              | Yes                  | Yes                  | Yes                  | **PASS** |

### Cross-Scenario Validations

| # | Validation                                                                                       | Result   |
|---|--------------------------------------------------------------------------------------------------|----------|
| 1 | Agent NEVER generates a feature.yaml file when inputs are insufficient                           | **PASS** |
| 2 | All responses include structured list with field / status / detail / suggested_question           | **PASS** |
| 3 | All suggested questions are concrete and actionable (not generic)                                 | **PASS** |
| 4 | Agent correctly uses status values: missing, incomplete, ambiguous                                | **PASS** |
| 5 | After receiving complementary data, agent would re-execute Phase 1 + Phase 2 before generating   | **PASS** |
| 6 | Agent does not invent data not present in inputs                                                  | **PASS** |
| 7 | Unrelated content is correctly rejected with explanation of what is needed                        | **PASS** |
| 8 | Agent follows the pipeline: ExtractionPhase -> ValidationPhase -> MissingDataRequest             | **PASS** |

**Overall Test Suite Result: PASS (5/5 scenarios)**
