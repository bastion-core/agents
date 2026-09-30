# Clasificación y Enmascaramiento Dinámico de PII en PostgreSQL

Este documento establece las directrices de seguridad para identificar, catalogar y enmascarar Información de Identificación Personal (PII) bajo estándares GDPR / CCPA.

---

## 1. Taxonomía Estándar de PII

| Categoría | Sensibilidad | Ejemplos de Campos | Tratamiento Obligatorio |
|---|---|---|---|
| **Direct PII** | CRÍTICA | DNI/Pasaporte, Email, Tarjeta Crédito, Teléfono | Encriptación en reposo / Hashing con Salt / Enmascaramiento total |
| **Indirect PII** | ALTA | Dirección IP, Fecha Nacimiento, Código Postal | Generalización (ej: solo año o ciudad) / Pseudonimización |
| **Sensitive PII**| CRÍTICA | Datos de salud, biométricos, credenciales | Cifrado a nivel de columna con `pgcrypto` (`pgp_sym_encrypt`) |

---

## 2. Catalogación con `COMMENT ON COLUMN`

Toda columna que contenga datos PII debe incluir un comentario explícito que catalogue la información:

```sql
COMMENT ON COLUMN core.customers.email IS 
'PII: DIRECT - Email personal del cliente. Requiere enmascaramiento parcial en ambientes analíticos.';

COMMENT ON COLUMN core.customers.tax_id IS 
'PII: DIRECT - Número de identificación tributaria (DNI/RUT). Prohibida su exposición en texto plano.';
```

---

## 3. Técnicas de Enmascaramiento en PostgreSQL

### 3.1 Vistas Seguras con Funciones de Enmascaramiento

```sql
-- Función de enmascaramiento de email: j***e@domain.com
CREATE OR REPLACE FUNCTION security.mask_email(email_address TEXT)
RETURNS TEXT AS $$
BEGIN
    IF email_address IS NULL OR position('@' in email_address) = 0 THEN
        RETURN email_address;
    END IF;
    RETURN substr(email_address, 1, 1) || '***' || 
           substr(email_address, position('@' in email_address) - 1);
END;
$$ LANGUAGE plpgsql IMMUTABLE SECURITY DEFINER;

-- Vista pública desidentificada para analistas y reporting
CREATE OR REPLACE VIEW analytics.masked_customers AS
SELECT
    customer_id,
    security.mask_email(email) AS email_masked,
    substr(phone_number, length(phone_number) - 3) AS phone_last_4,
    date_trunc('year', birth_date)::date AS birth_year,
    created_at
FROM core.customers;

-- Asignación de permisos por rol
GRANT SELECT ON analytics.masked_customers TO role_analyst;
REVOKE SELECT ON core.customers FROM role_analyst;
```

### 3.2 Hashing Determinista con Salt (Pseudonimización para Joins)

Para permitir a los analistas realizar joins y agrupaciones sin exponer el valor original:

```sql
-- Hash determinista usando SHA-256 y un salt seguro
CREATE OR REPLACE FUNCTION security.pseudonymize(val TEXT, salt TEXT)
RETURNS TEXT AS $$
BEGIN
    RETURN encode(digest(salt || val, 'sha256'), 'hex');
END;
$$ LANGUAGE plpgsql IMMUTABLE;
```
