# Spec Generator — Plugin de Gemini CLI para SDD

Plugin de Gemini CLI que genera especificaciones de producto (`feature.yaml`) y tecnicas (`technical.yaml`) en formato **Specification-Driven Development (SDD)** usando subagents especializados.

Parte de la estrategia multi-modelo: **Gemini para Discovery, Claude Code para Delivery**.

## Requisitos

- [Gemini CLI](https://github.com/google-gemini/gemini-cli) instalado (ver [instalacion oficial](https://github.com/google-gemini/gemini-cli#installation))
- [gcloud CLI](https://cloud.google.com/sdk/docs/install) instalado y configurado
- Proyecto de Google Cloud Platform (GCP) con la API de Vertex AI habilitada
- Creditos activos en la consola de GCP para consumir Vertex AI

## Configuracion Paso a Paso

### Paso 1: Instalar Gemini CLI

```bash
npm install -g @google/gemini-cli
```

Verificar la instalacion:

```bash
gemini --version
```

### Paso 2: Instalar y configurar gcloud CLI

Si no tienes gcloud CLI, instalarlo desde https://cloud.google.com/sdk/docs/install

Verificar la instalacion:

```bash
gcloud --version
```

### Paso 3: Habilitar la API de Vertex AI en tu proyecto GCP

```bash
gcloud services enable aiplatform.googleapis.com --project=TU_PROJECT_ID
```

Reemplaza `TU_PROJECT_ID` con el ID de tu proyecto GCP (lo encuentras en la consola de GCP en https://console.cloud.google.com/).

### Paso 4: Configurar credenciales de autenticacion (ADC)

ADC (Application Default Credentials) es el metodo recomendado para desarrollo local. Funciona como un "login" con tu cuenta de Google que tiene acceso al proyecto GCP:

```bash
gcloud auth application-default login
```

Esto abre tu navegador para iniciar sesion con tu cuenta de Google. Despues de autenticarte, gcloud guarda un token en `~/.config/gcloud/application_default_credentials.json` que Gemini CLI usara automaticamente.

### Paso 5: Configurar variables de entorno

Gemini CLI necesita saber **cual proyecto GCP usar** y en **que region**. Configura estas variables en tu terminal:

**Opcion A — Temporal (solo para la sesion actual):**

```bash
export GOOGLE_CLOUD_PROJECT="tu-project-id"
export GOOGLE_CLOUD_LOCATION="us-central1"
```

**Opcion B — Permanente (persiste entre sesiones):**

Agrega estas lineas al final de tu archivo de perfil de shell:

Para zsh (macOS default):
```bash
echo 'export GOOGLE_CLOUD_PROJECT="tu-project-id"' >> ~/.zshrc
echo 'export GOOGLE_CLOUD_LOCATION="us-central1"' >> ~/.zshrc
source ~/.zshrc
```

Para bash:
```bash
echo 'export GOOGLE_CLOUD_PROJECT="tu-project-id"' >> ~/.bashrc
echo 'export GOOGLE_CLOUD_LOCATION="us-central1"' >> ~/.bashrc
source ~/.bashrc
```

Reemplaza `tu-project-id` con el ID real de tu proyecto GCP.

| Variable | Que es | Donde encontrarla |
|----------|--------|-------------------|
| `GOOGLE_CLOUD_PROJECT` | ID del proyecto GCP con Vertex AI habilitado | Consola GCP > Dashboard > Project ID |
| `GOOGLE_CLOUD_LOCATION` | Region de Vertex AI donde se ejecuta el modelo | Usar `us-central1` (misma region del cluster GKE del equipo) |

### Paso 6: Primera ejecucion de Gemini CLI

Navega al directorio del plugin y ejecuta Gemini CLI:

```bash
cd gemini/spec-generator/
gemini
```

En la **primera ejecucion**, Gemini CLI muestra un menu de autenticacion:

```
How would you like to authenticate for this project?

  1. Sign in with Google
  2. Use Gemini API Key
  3. Vertex AI              <-- SELECCIONAR ESTA OPCION

(Use Enter to select)
```

**Selecciona la opcion 3 (Vertex AI)** con las flechas del teclado y presiona Enter. Esta opcion usa las credenciales ADC que configuraste en el Paso 4 y las variables de entorno del Paso 5.

> **IMPORTANTE**: NO seleccionar "Use Gemini API Key". Las API keys solo funcionan con Google AI Studio (endpoint diferente). Para nuestro caso con creditos GCP, se usa Vertex AI.

Gemini CLI guardara esta preferencia y no volvera a preguntar en futuras sesiones.

### Paso 7: Verificar que funciona

Despues de seleccionar Vertex AI, deberias ver el prompt de Gemini CLI listo para recibir comandos. Prueba que los subagents estan disponibles:

```
> Hola, que subagents tienes disponibles?
```

Deberia mencionar `@product` y `@architect`.

## Autenticacion Alternativa: Service Account

Si no puedes usar `gcloud auth` (ej. en CI/CD o servidores sin navegador):

1. Crear un Service Account en la consola de GCP con rol `roles/aiplatform.user`
2. Descargar el JSON key file
3. Configurar la variable de entorno adicional:

```bash
export GOOGLE_APPLICATION_CREDENTIALS="/ruta/absoluta/al/service-account-key.json"
```

> **ADVERTENCIA**: Nunca commitear el archivo JSON key al repositorio. Agregarlo a `.gitignore`.

## Uso

### Flujo Secuencial Completo

El flujo recomendado es secuencial: `@product` -> `@architect` -> Claude Code.

```bash
cd gemini/spec-generator/
gemini
```

**Paso 1 — Generar feature.yaml:**

```
> @product Necesito una spec para un sistema de notificaciones push
  que soporte Firebase Cloud Messaging para Flutter y un endpoint
  de registro de device tokens en el backend Python/FastAPI.
  Stack: multi_stack (python_fastapi + flutter)
  Criterios: soportar topics, device tokens individuales, notificaciones silenciosas
  Reglas: max 5 notificaciones/hora por usuario, retry con exponential backoff
  Guardar en: docs/features/push_notifications/feature.yaml
```

**Paso 2 — Generar technical.yaml:**

```
> @architect Genera el technical.yaml a partir de:
  docs/features/push_notifications/feature.yaml
  Stack: python_fastapi
  Repositorio de referencia: /Users/dev/repos/mi-backend/
  Guardar en: docs/features/push_notifications/technical.yaml
```

**Paso 3 — Delivery con Claude Code:**

```bash
cd /Users/dev/repos/mi-backend/
claude
```

### Single Prompt (Optimizado)

Proporcionando toda la informacion en un solo prompt se minimiza el consumo de tokens:

```
> @product Necesito una spec para un modulo de pagos con Stripe.
  Stack: python_fastapi
  Descripcion: checkout con tarjeta, webhooks de Stripe, reembolsos parciales.
  Criterios: checkout <3s, webhooks idempotentes, reembolsos dentro de 30 dias.
  Reglas: comision 2.9% + $0.30, moneda USD, min $1, max $10,000.
  Guardar en: docs/features/payments/feature.yaml
```

### Ejemplos Avanzados

**Con repositorio local** (Gemini CLI explora la estructura):

```
> @architect Genera el technical.yaml a partir de:
  docs/features/payments/feature.yaml
  Stack: python_fastapi
  Repositorio: /Users/dev/repos/mi-api/
  Guardar en: docs/features/payments/technical.yaml
```

**Con Gemini Flash** (iteraciones rapidas sobre specs existentes):

```bash
gemini --model gemini-3-flash
```

```
> @architect Refina este technical.yaml:
  docs/features/payments/technical.yaml
  Agrega endpoint de webhooks para Stripe.
```

**Delegacion automatica** (sin @, Gemini CLI selecciona el subagent):

```
> Necesito crear la especificacion de producto para un modulo de pagos
  con Stripe que incluya checkout, webhooks y reembolsos.
```

## Estructura de Archivos

```
gemini/spec-generator/
├── GEMINI.md                          # Orquestador secuencial del workspace
├── README.md                          # Este archivo
├── .gemini/
│   ├── settings.json                  # Config del proyecto (maxTurns, timeouts)
│   └── agents/
│       ├── product.md                 # Subagent @product (genera feature.yaml)
│       └── architect.md               # Subagent @architect (genera technical.yaml)
├── conventions-backend-py.md          # Convenciones Python/FastAPI
├── conventions-frontend-nextjs.md     # Convenciones Next.js
├── conventions-mobile-flutter.md      # Convenciones Flutter
├── schema-feature.yaml                # Schema formal de feature.yaml
├── schema-technical.yaml              # Schema formal de technical.yaml
├── example-feature.yaml               # Ejemplo de referencia (inventario)
└── example-technical.yaml             # Ejemplo de referencia (inventario)
```

## Troubleshooting

**Gemini CLI muestra menu "How would you like to authenticate?"**
- Seleccionar opcion **3. Vertex AI** (no "Sign in with Google" ni "API Key")
- Si no aparece la opcion Vertex AI, verificar que las variables de entorno estan configuradas:
  ```bash
  echo $GOOGLE_CLOUD_PROJECT    # debe mostrar tu project ID
  echo $GOOGLE_CLOUD_LOCATION   # debe mostrar us-central1
  ```

**Error: "Could not automatically determine credentials"**
- Ejecutar `gcloud auth application-default login` y autenticarse en el navegador
- Verificar que el archivo existe: `ls ~/.config/gcloud/application_default_credentials.json`
- O configurar `GOOGLE_APPLICATION_CREDENTIALS` con ruta al Service Account JSON

**Error: "API not enabled"**
- Ejecutar `gcloud services enable aiplatform.googleapis.com --project=TU_PROJECT_ID`

**Error: "Permission denied"**
- Verificar que tu cuenta tiene el rol `roles/aiplatform.user` en el proyecto GCP
- Para verificar: `gcloud projects get-iam-policy TU_PROJECT_ID --filter="bindings.members:TU_EMAIL"`

**Error: "Quota exceeded"**
- Verificar creditos disponibles en la consola de GCP
- Considerar usar `--model gemini-3-flash` para reducir consumo

**Las variables de entorno no persisten**
- Verificar que las agregaste al archivo correcto (`~/.zshrc` para macOS, `~/.bashrc` para Linux)
- Ejecutar `source ~/.zshrc` (o `source ~/.bashrc`) despues de editar
- Abrir una nueva terminal y verificar con `echo $GOOGLE_CLOUD_PROJECT`

**Los subagents no cargan**
- Verificar que estas ejecutando `gemini` desde el directorio `gemini/spec-generator/`
- Verificar que los archivos `.gemini/agents/product.md` y `.gemini/agents/architect.md` existen
- Verificar que el frontmatter YAML de cada subagent es valido

**Las specs generadas no son compatibles con Claude Code**
- Verificar que los schemas (`schema-feature.yaml`, `schema-technical.yaml`) no han sido modificados
- Comparar la spec generada con los ejemplos de referencia
