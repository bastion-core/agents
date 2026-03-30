# gemini_initial_config_shell - Technical Solution Proposal

**Date**: 2026-03-28
**Author**: Architecture Team
**Status**: Draft

---

## 1. Solution Overview

### Problem Statement

Los desarrolladores del equipo necesitan autenticarse diariamente con Google Cloud para usar Gemini CLI con Vertex AI. El proceso manual implica ejecutar multiples comandos gcloud en secuencia correcta, recordar roles de IAM especificos y configurar Application Default Credentials con impersonation. Este proceso es propenso a errores, consume tiempo y no es reproducible de forma consistente entre miembros del equipo.

### Proposed Solution

Un script bash unico (`setup-gemini.sh`) que automatiza los 7 pasos del flujo de configuracion de Service Account Impersonation en GCP. El script es idempotente (seguro para re-ejecutar), soporta modo dry-run para previsualizar, modo cleanup para revertir, y utiliza flags nombrados para configuracion flexible.

### Scope

- **In scope**:
  - Creacion automatizada de Service Account dedicado por desarrollador
  - Asignacion de rol minimo (Vertex AI User)
  - Configuracion de Service Account Impersonation
  - Generacion de Application Default Credentials (ADC)
  - Verificacion de acceso a Vertex AI
  - Modo dry-run para previsualizar
  - Modo cleanup para revertir toda la configuracion
  - Validaciones de prerequisitos y manejo de errores
  - Mensajes con colores para feedback visual

- **Out of scope**:
  - Instalacion de gcloud CLI (prerequisito del usuario)
  - Creacion de proyectos GCP
  - Habilitacion automatica de la API de Vertex AI (solo verificacion)
  - Configuracion de Gemini CLI (settings.json, modelos por defecto)
  - CI/CD integration (el script es para uso local de desarrolladores)

---

## 2. Component Architecture

### Component Diagram

```mermaid
graph TB
    subgraph "setup-gemini.sh"
        subgraph "CLI Layer"
            PARSE[Flag Parser<br/>--project, --email, --dev-name,<br/>--region, --dry-run, --cleanup, --help]
            HELP[Help Display]
        end

        subgraph "Validation Layer"
            V_GCLOUD[Validate gcloud CLI]
            V_AUTH[Validate User Auth]
            V_PROJECT[Validate GCP Project]
            V_API[Validate Vertex AI API]
            V_INPUT[Validate Input Flags]
        end

        subgraph "Pipeline Layer"
            P1[Create Service Account]
            P2[Assign Vertex AI Role]
            P3[Grant Impersonation]
            P4[Configure gcloud Default]
            P5[Generate ADC]
            P6[Verify Access]
            P7[Show Summary]
        end

        subgraph "Cleanup Pipeline"
            C1[Unset gcloud Impersonation]
            C2[Revoke Impersonation Binding]
            C3[Revoke Vertex AI Role]
            C4[Delete Service Account]
        end

        subgraph "Utility Layer"
            LOG[Color Logger<br/>info, success, warning, error]
            TRAP[Error Trap Handler]
            DRY[Dry Run Executor]
            IDEM[Idempotency Checker]
        end
    end

    subgraph "External Dependencies"
        GCLOUD[gcloud CLI]
        GCP_IAM[GCP IAM API]
        GCP_VERTEX[Vertex AI API]
    end

    PARSE --> V_GCLOUD
    PARSE --> HELP
    V_GCLOUD --> V_AUTH --> V_PROJECT --> V_API --> V_INPUT
    V_INPUT --> P1 --> P2 --> P3 --> P4 --> P5 --> P6 --> P7

    PARSE -->|--cleanup| C1 --> C2 --> C3 --> C4

    P1 --> IDEM
    P2 --> IDEM
    P3 --> IDEM

    P1 --> GCLOUD
    P2 --> GCLOUD
    P3 --> GCLOUD
    P4 --> GCLOUD
    P5 --> GCLOUD
    P6 --> GCLOUD

    GCLOUD --> GCP_IAM
    GCLOUD --> GCP_VERTEX

    LOG --> P1
    LOG --> P2
    LOG --> P3
    LOG --> P4
    LOG --> P5
    LOG --> P6
    LOG --> P7

    TRAP --> LOG
```

### Components Description

| Component | Responsibility | Layer |
|-----------|---------------|-------|
| Flag Parser | Parsear flags CLI (--project, --email, etc.) y asignar valores por defecto | CLI |
| Help Display | Mostrar documentacion de uso con descripcion de todos los flags | CLI |
| Validate gcloud CLI | Verificar que gcloud esta instalado y accesible en PATH | Validation |
| Validate User Auth | Verificar que el usuario tiene una sesion activa en gcloud | Validation |
| Validate GCP Project | Verificar que el proyecto GCP existe y esta accesible | Validation |
| Validate Vertex AI API | Verificar que aiplatform.googleapis.com esta habilitada | Validation |
| Validate Input Flags | Validar formato de email, longitud de dev-name, region valida | Validation |
| Create Service Account | Crear SA gemini-{dev_name} con verificacion de existencia previa | Pipeline |
| Assign Vertex AI Role | Asignar roles/aiplatform.user al SA con verificacion de binding | Pipeline |
| Grant Impersonation | Asignar roles/iam.serviceAccountTokenCreator al usuario | Pipeline |
| Configure gcloud Default | Establecer impersonation como default en gcloud config | Pipeline |
| Generate ADC | Generar Application Default Credentials con impersonation | Pipeline |
| Verify Access | Ejecutar gcloud ai models list para confirmar acceso | Pipeline |
| Show Summary | Mostrar resumen de configuracion e instrucciones de uso | Pipeline |
| Color Logger | Funciones de logging con colores ANSI (info, success, warning, error) | Utility |
| Error Trap Handler | Capturar errores con trap y mostrar diagnostico | Utility |
| Dry Run Executor | Mostrar comandos sin ejecutarlos cuando --dry-run esta activo | Utility |
| Idempotency Checker | Verificar si un recurso ya existe antes de intentar crearlo | Utility |

---

## 3. Flow Diagrams

### Main Flow (Setup)

```mermaid
flowchart TD
    START([./setup-gemini.sh --project my-project]) --> PARSE_FLAGS{Parse Flags}

    PARSE_FLAGS -->|--help| SHOW_HELP[Mostrar ayuda y salir]
    PARSE_FLAGS -->|--cleanup| CLEANUP_FLOW[Flujo de Cleanup]
    PARSE_FLAGS -->|setup normal| VALIDATE

    subgraph VALIDATE[Validacion de Prerequisitos]
        V1[gcloud instalado?] -->|No| ERR1[Exit code 2:<br/>gcloud CLI no encontrado]
        V1 -->|Si| V2[Usuario autenticado?]
        V2 -->|No| ERR2[Exit code 2:<br/>Ejecutar gcloud auth login]
        V2 -->|Si| V3[Proyecto configurado?]
        V3 -->|No| ERR3[Exit code 2:<br/>Especificar --project]
        V3 -->|Si| V4[Vertex AI API habilitada?]
        V4 -->|No| ERR4[Exit code 2:<br/>Habilitar API manualmente]
        V4 -->|Si| V5[Inputs validos?]
        V5 -->|No| ERR5[Exit code 1:<br/>Flag invalido]
        V5 -->|Si| PIPELINE
    end

    subgraph PIPELINE[Pipeline de Configuracion]
        direction TB
        S1{SA ya existe?}
        S1 -->|Si| S1_SKIP[Warning: SA ya existe, continuando...]
        S1 -->|No| S1_CREATE[Crear Service Account]
        S1_SKIP --> S2
        S1_CREATE --> S2

        S2{Rol Vertex AI<br/>ya asignado?}
        S2 -->|Si| S2_SKIP[Warning: Rol ya asignado, continuando...]
        S2 -->|No| S2_ASSIGN[Asignar roles/aiplatform.user]
        S2_SKIP --> S3
        S2_ASSIGN --> S3

        S3{Permiso impersonation<br/>ya otorgado?}
        S3 -->|Si| S3_SKIP[Warning: Permiso ya otorgado, continuando...]
        S3 -->|No| S3_GRANT[Otorgar serviceAccountTokenCreator]
        S3_SKIP --> S4
        S3_GRANT --> S4

        S4[Configurar gcloud<br/>impersonation default]
        S4 --> S5

        S5[Generar ADC con<br/>impersonation]
        S5 --> S6

        S6{Verificar acceso<br/>a Vertex AI}
        S6 -->|Exito| S7[Mostrar resumen<br/>de configuracion]
        S6 -->|Fallo| ERR6[Exit code 5:<br/>Verificacion fallida,<br/>sugerir --cleanup]
    end

    S7 --> SUCCESS([Exit code 0])
```

### Dry Run Flow

```mermaid
flowchart TD
    START([./setup-gemini.sh --dry-run]) --> PARSE[Parse Flags]
    PARSE --> VALIDATE[Validar prerequisitos]
    VALIDATE --> DRY_HEADER["[DRY RUN] Mostrando comandos que se ejecutarian:"]

    DRY_HEADER --> CMD1["[CMD] gcloud iam service-accounts create gemini-juan<br/>--project=my-project --display-name=Gemini Dev - juan"]
    CMD1 --> CMD2["[CMD] gcloud projects add-iam-policy-binding my-project<br/>--member=serviceAccount:gemini-juan@my-project.iam.gserviceaccount.com<br/>--role=roles/aiplatform.user"]
    CMD2 --> CMD3["[CMD] gcloud iam service-accounts add-iam-policy-binding<br/>gemini-juan@my-project.iam.gserviceaccount.com<br/>--member=user:juan@empresa.com<br/>--role=roles/iam.serviceAccountTokenCreator"]
    CMD3 --> CMD4["[CMD] gcloud config set auth/impersonate_service_account<br/>gemini-juan@my-project.iam.gserviceaccount.com"]
    CMD4 --> CMD5["[CMD] gcloud auth application-default login<br/>--impersonate-service-account=gemini-juan@my-project.iam.gserviceaccount.com"]
    CMD5 --> CMD6["[CMD] gcloud ai models list --region=us-central1 --limit=1"]
    CMD6 --> DONE["[DRY RUN] Ninguna operacion fue ejecutada"]
    DONE --> EXIT([Exit code 0])
```

### Cleanup Flow

```mermaid
flowchart TD
    START([./setup-gemini.sh --cleanup]) --> PARSE[Parse Flags]
    PARSE --> VALIDATE[Validar prerequisitos minimos<br/>gcloud + auth + project]

    VALIDATE --> C1[Limpiar gcloud config<br/>auth/impersonate_service_account]
    C1 --> C2{Revocar<br/>serviceAccountTokenCreator<br/>del usuario?}
    C2 -->|Binding existe| C2_REVOKE[Revocar IAM binding]
    C2 -->|No existe| C2_SKIP[Warning: Binding no encontrado]
    C2_REVOKE --> C3
    C2_SKIP --> C3

    C3{Revocar<br/>roles/aiplatform.user<br/>del SA?}
    C3 -->|Binding existe| C3_REVOKE[Revocar IAM binding]
    C3 -->|No existe| C3_SKIP[Warning: Binding no encontrado]
    C3_REVOKE --> C4
    C3_SKIP --> C4

    C4{Eliminar<br/>Service Account?}
    C4 -->|SA existe| C4_DELETE[Eliminar Service Account]
    C4 -->|No existe| C4_SKIP[Warning: SA no encontrado]
    C4_DELETE --> C5
    C4_SKIP --> C5

    C5[Limpiar ADC local<br/>si fue generado con impersonation]
    C5 --> SUMMARY[Mostrar resumen de cleanup]
    SUMMARY --> EXIT([Exit code 0])
```

### Error Handling and Trap Flow

```mermaid
flowchart TD
    START[Ejecucion del Pipeline] --> |set -euo pipefail| EXEC[Ejecutar paso del pipeline]

    EXEC -->|Exito| NEXT[Continuar al siguiente paso]
    EXEC -->|Error| TRAP[trap handler captura ERR]

    TRAP --> LOG_ERROR["Mostrar en rojo:<br/>ERROR en linea {N}: {comando}<br/>Codigo de salida: {code}"]
    LOG_ERROR --> DIAG{Diagnostico<br/>segun codigo}

    DIAG -->|code 2| D2[Prerequisito faltante:<br/>mostrar que instalar/configurar]
    DIAG -->|code 3| D3[Permiso insuficiente:<br/>mostrar roles necesarios]
    DIAG -->|code 4| D4[Error de red:<br/>verificar conectividad]
    DIAG -->|code 5| D5[Vertex AI inaccesible:<br/>verificar API y permisos]

    D2 --> SUGGEST
    D3 --> SUGGEST
    D4 --> SUGGEST
    D5 --> SUGGEST

    SUGGEST["Sugerir: ./setup-gemini.sh --cleanup<br/>para revertir cambios parciales"]
    SUGGEST --> EXIT([Exit con codigo de error])
```

---

## 4. Security Considerations

### Security Model

| Aspecto | Estrategia | Detalle |
|---------|-----------|---------|
| **Permisos minimos** | roles/aiplatform.user | Unico rol asignado al SA. No incluye permisos de escritura, admin ni acceso a otros servicios GCP |
| **Sin secrets en disco** | Service Account Impersonation | No se generan ni almacenan key files JSON. Los tokens son efimeros y se renuevan automaticamente via ADC |
| **Sin secrets en el script** | Runtime resolution | Todos los valores sensibles (project ID, email, SA email) se obtienen de gcloud CLI en runtime, no estan hardcodeados |
| **Auditoria individual** | SA por desarrollador | Cada desarrollador tiene su propio SA (gemini-{dev_name}), permitiendo trazabilidad en Cloud Audit Logs |
| **Revocacion granular** | --cleanup por usuario | Se puede revocar el acceso de un desarrollador especifico sin afectar a otros |
| **Dry run seguro** | No expone tokens | El modo --dry-run muestra comandos gcloud pero nunca tokens, credenciales ni IAM policies completas |

### Threat Model

| Amenaza | Probabilidad | Mitigacion |
|---------|-------------|-----------|
| Script modificado maliciosamente | Baja | El script esta versionado en git. Verificar integridad antes de ejecutar. No ejecutar desde fuentes no confiables |
| Escalacion de privilegios via SA | Baja | El SA solo tiene roles/aiplatform.user. No puede acceder a otros servicios GCP ni escalar permisos |
| SA compartido entre desarrolladores | Media | El script genera un SA unico por dev_name. Documentar que cada desarrollador debe usar su propio nombre |
| Credenciales ADC expuestas | Baja | ADC con impersonation genera tokens efimeros. Incluso si el archivo ADC es comprometido, los tokens expiran rapidamente |

---

## 5. Technical Decisions

### Decision 1: Script bash monolitico vs. multiples scripts

- **Options considered**: Script unico, Makefile con targets, Multiples scripts con orquestador
- **Selected**: Script unico
- **Justification**: El flujo es estrictamente secuencial (7 pasos dependientes). Un script unico permite error handling centralizado con trap, rollback coherente con --cleanup, y distribucion simple (un solo archivo).

### Decision 2: Service Account Impersonation vs. Key JSON

- **Options considered**: Impersonation, Key JSON file, Workload Identity Federation
- **Selected**: Impersonation
- **Justification**: Impersonation elimina el riesgo de secrets en disco, no requiere rotacion de keys, y es la practica recomendada por Google Cloud para desarrollo local. Key JSON files son un riesgo de seguridad si se commitean accidentalmente a git.

### Decision 3: Flags CLI con while-case vs. getopts

- **Options considered**: getopts (solo flags cortos), while-case con pattern matching, getopt (GNU)
- **Selected**: while-case con pattern matching
- **Justification**: while-case soporta flags largos (--project) y cortos (-p) de forma nativa sin depender de getopt de GNU (que no esta disponible por defecto en macOS). getopts solo soporta flags cortos. La implementacion con while-case es mas portable entre macOS y Linux.

### Decision 4: No rollback automatico en fallo

- **Options considered**: Rollback automatico en fallo, No rollback (solo --cleanup manual)
- **Selected**: No rollback automatico
- **Justification**: Un rollback automatico a mitad del pipeline podria fallar tambien, dejando el estado mas inconsistente. Es mas seguro informar al usuario del paso que fallo y sugerir --cleanup, que ejecuta la reversion completa con verificaciones de idempotencia.

---

## 6. Implementation Phases

| Phase | Description | Duration (probable) | Dependencies |
|-------|-------------|---------------------|--------------|
| Phase 1: Foundation | Estructura base, parseo de flags, validaciones, utilidades de logging y error handling | 4 horas | Ninguna |
| Phase 2: Core Pipeline | Los 7 pasos del flujo principal con verificacion de idempotencia | 5 horas | Phase 1 |
| Phase 3: Dry Run and Cleanup | Modos --dry-run y --cleanup con reversion en orden inverso | 3 horas | Phase 2 |
| Phase 4: Testing and Validation | Pruebas manuales en proyecto GCP real, todos los escenarios | 2 horas | Phase 3 |

**Total estimado**: 14 horas (2 dias de trabajo)

---

## 7. Risks and Mitigations

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Incompatibilidad bash macOS 3.2 vs Linux 5+ | Medium | Medium | Usar solo features POSIX-compatible o documentar requisito de bash 4+ con instrucciones de instalacion via brew |
| Usuario sin permisos de IAM Admin | Medium | High | Verificar permisos al inicio del script. Mostrar mensaje claro con los roles necesarios y sugerir contactar al administrador del proyecto |
| Vertex AI API no habilitada | Low | Medium | Verificar con gcloud services list. Mostrar instrucciones para habilitar manualmente con gcloud services enable |
| Nombre de SA excede 30 caracteres | Low | Low | Validar longitud antes de crear. Truncar dev_name si es necesario y avisar al usuario |
| El paso de ADC abre el navegador inesperadamente | Low | Low | Documentar en el resumen previo que el paso de ADC abrira una ventana del navegador para autorizar el flujo OAuth |

---

## 8. Usage Examples

### Setup completo

```
./setup-gemini.sh --project my-gcp-project --email juan@empresa.com --dev-name juan
```

### Setup con valores por defecto

```
./setup-gemini.sh
# Usa: proyecto activo en gcloud, email del usuario autenticado, dev-name del username
```

### Preview sin ejecutar

```
./setup-gemini.sh --dry-run --project my-gcp-project
```

### Revertir configuracion

```
./setup-gemini.sh --cleanup --project my-gcp-project --dev-name juan
```

---

**End of Technical Proposal**
