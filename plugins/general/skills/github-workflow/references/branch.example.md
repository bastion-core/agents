# Examples: Branch Names

Ejemplos prácticos de cómo aplicar el estándar de nombres de rama.

### 1. Nueva Funcionalidad
**Rama:** `feat/jwt-refresh-token`
**Descripción:** Soporte de refresh tokens en el módulo de autenticación. PR a Staging.

---

### 2. Corrección de Bug
**Rama:** `fix/null-user-endpoint`
**Descripción:** Manejo de respuesta nula en el endpoint de usuario. PR a Staging.

---

### 3. Corrección Crítica en Producción
**Rama:** `hotfix/payment-rounding`
**Descripción:** Redondeo incorrecto en totales de pago. PR a Master con template de Hotfix.

---

### 4. Rama con Referencia a Issue
**Rama:** `feat/multi-language-support-45`
**Descripción:** Soporte multi-idioma vinculado al issue #45.

---

### 5. Otros Tipos
- **Refactor**: `refactor/simplify-token-validation`
- **Mantenimiento**: `chore/bump-actions-node-20`
- **Documentación**: `docs/update-install-instructions`
- **Pruebas**: `test/add-user-service-tests`
- **Estilo**: `style/format-payment-module`

---

## Ejemplos Inválidos

| Rama | Problema |
| --- | --- |
| `nueva-funcionalidad-auth` | Sin type y en español. |
| `feat/Add_JWT_Support` | Mayúsculas y guion bajo en lugar de `kebab-case`. |
| `feat/auth/jwt-refresh` | Más de una `/`; sólo se permite un nivel. |
| `fix/bug` | Genérico, no describe el cambio. |
| `feat/add-support-for-the-new-jwt-refresh-token-flow` | Supera los 40 caracteres. |
| `juan/wip` | Nombre de persona y summary sin significado. |
