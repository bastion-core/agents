# Examples: Commit Messages

Ejemplos prácticos de cómo aplicar el estándar de mensajes de commit.

### 1. Nueva Funcionalidad (Simple)
**Mensaje:** `feat(auth): add JWT refresh token support`  
**Descripción:** Agregado de soporte para refresh tokens en el módulo de autenticación.

---

### 2. Corrección de Bug (Simple)
**Mensaje:** `fix(api): handle null response in user endpoint`  
**Descripción:** Se maneja el caso donde la respuesta es nula para evitar errores de ejecución.

---

### 3. Corrección con Explicación Detallada (Body)
**Mensaje:**
```text
fix(payments): correct rounding issue in totals

Totals were incorrectly rounded causing mismatch with invoices.
We now use the decimal library for all calculations.
```
**Descripción:** Corrección de redondeo que causaba discrepancias en facturación.

---

### 4. Funcionalidad con Referencia a Issue (Footer)
**Mensaje:**
```text
feat(blog): add multi-language support

Integrates automatic translation using LangChain service.

Closes #45
```
**Descripción:** Soporte multi-idioma con vinculación automática al ticket de seguimiento.

---

### 5. Cambio Disruptivo (Breaking Change)
**Mensaje:**
```text
feat(api): require currency field in payments

BREAKING CHANGE: currency is now mandatory for all payment requests
```
**Descripción:** El campo moneda ahora es obligatorio, rompiendo compatibilidad con requests anteriores.

---

### 6. Otros Tipos
- **Refactor**: `refactor(auth): simplify token validation logic`
- **Mantenimiento**: `chore(ci): update GitHub Actions to Node 20`
- **Documentación**: `docs(readme): update installation instructions`
- **Pruebas**: `test(user): add unit tests for user service`
