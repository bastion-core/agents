#!/usr/bin/env python3
"""Validador de especificaciones SDD (feature, change, technical y tasks).

Carga el schema de cada tipo desde context/sdd-specs/*.schema.yaml y valida las specs
contra el: campos obligatorios, tipos, max_length y enums (valores_permitidos), ademas de
las reglas propias de las tasks (nombre de archivo y longitud del campo `task`).

Los estados (`status`) son una lista cerrada por tipo; ver
context/sdd-specs/status-vocabulary.md. Solo depende de PyYAML.

Uso:
    python3 scripts/validate_specs.py [--schemas-dir DIR] RUTA [RUTA ...]

Codigo de salida: 0 sin errores (los avisos no fallan), 1 con algun ERROR, 2 por uso
incorrecto.
"""

from __future__ import annotations

import argparse
import datetime
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

try:
    import yaml
except ImportError:  # pragma: no cover
    sys.stderr.write("Falta PyYAML: pip install pyyaml\n")
    sys.exit(2)

ERROR = "ERROR"
AVISO = "AVISO"

SPEC_TYPES = ("feature", "change", "technical", "task")
DETECTED_NAMES = {
    "feature.yaml": "feature",
    "change.yaml": "change",
    "technical.yaml": "technical",
}
SKIP_DIRS = {".git", "node_modules", "__pycache__", ".venv", "venv"}

TASK_SOFT_LIMIT = 47  # guia estricta del repo
TASK_HARD_LIMIT = 100  # limite duro de la plataforma (task_code)
TASK_FILE_MAX = 50  # nombre de archivo sin extension
TASK_FILE_RE = re.compile(r"^\d{2}-[a-z0-9]+(?:-[a-z0-9]+)*$")
LEGACY_TASK_FILE_RE = re.compile(r"^\d{2}_[a-z0-9]+(?:_[a-z0-9]+)*$")
SNAKE_RE = re.compile(r"^[a-z0-9]+(?:_[a-z0-9]+)*$")

VOCAB_DOC = "context/sdd-specs/status-vocabulary.md"
DEFAULT_SCHEMAS_DIR = Path(__file__).resolve().parent.parent / "context" / "sdd-specs"


@dataclass(frozen=True)
class Finding:
    level: str
    file: str
    field: str
    message: str
    # Problema estructural (tipo, campo obligatorio, longitud, YAML) que en los documentos
    # legados bajo docs/features se degrada a AVISO. Los enums y los limites de `task`
    # nunca se degradan.
    structural: bool = False

    def render(self) -> str:
        campo = f" [{self.field}]" if self.field else ""
        return f"{self.level} {self.file}{campo}: {self.message}"


# --------------------------------------------------------------------------- schemas


def load_schemas(schemas_dir: Path) -> dict[str, dict[str, Any]]:
    schemas: dict[str, dict[str, Any]] = {}
    for spec_type in SPEC_TYPES:
        path = schemas_dir / f"{spec_type}.schema.yaml"
        if not path.is_file():
            raise FileNotFoundError(f"No existe el schema {path}")
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
        schemas[spec_type] = data["schema"]
    return schemas


def allowed_values(field_schema: dict[str, Any]) -> list[str] | None:
    """Extrae los valores permitidos de `valores_permitidos` (o `valores`).

    Cada item puede ser un string (`PENDING`) o un mapa de un solo par (`L1: descripcion`),
    que YAML carga como dict; en ambos casos el valor permitido es el token inicial.
    """
    raw = field_schema.get("valores_permitidos", field_schema.get("valores"))
    if raw is None:
        return None
    values: list[str] = []
    for item in raw:
        if isinstance(item, dict):
            values.extend(str(k) for k in item)
        else:
            text = str(item)
            values.append(text.split(":", 1)[0].strip() if re.match(r"^\w+:\s", text) else text)
    return values


def type_kind(field_schema: dict[str, Any]) -> str:
    tipo = str(field_schema.get("tipo", "")).strip().lower()
    if tipo.startswith("lista"):
        return "list"
    if tipo.startswith("objeto"):
        return "dict"
    if tipo.startswith("enum"):
        return "enum"
    if "enum" in tipo:
        return "enum"
    return "string"


def is_required(field_schema: dict[str, Any]) -> bool:
    value = field_schema.get("obligatorio")
    if value is True:
        return True
    # "true (cuando data_model se incluye)": obligatorio dentro de su padre
    return isinstance(value, str) and value.strip().lower().startswith("true")


def item_schema(field_schema: dict[str, Any]) -> dict[str, Any] | None:
    for key in ("campos_por_item", "campos_por_endpoint"):
        if isinstance(field_schema.get(key), dict):
            return field_schema[key]
    if type_kind(field_schema) == "list" and isinstance(field_schema.get("campos"), dict):
        return field_schema["campos"]
    return None


# --------------------------------------------------------------------------- campos


def _closest(value: Any, allowed: list[str]) -> str | None:
    norm = re.sub(r"[-_\s]", "", str(value)).lower()
    for candidate in allowed:
        if re.sub(r"[-_\s]", "", candidate).lower() == norm:
            return candidate
    return None


def check_field(
    value: Any,
    schema: dict[str, Any],
    file: str,
    path: str,
    out: list[Finding],
) -> None:
    kind = type_kind(schema)
    allowed = allowed_values(schema)

    if kind == "list":
        if not isinstance(value, list):
            out.append(Finding(ERROR, file, path, f"se esperaba una lista y se encontro {_tname(value)}", structural=True))
            return
        sub = item_schema(schema)
        if sub:
            for i, item in enumerate(value):
                if not isinstance(item, dict):
                    out.append(Finding(ERROR, file, f"{path}[{i}]", f"se esperaba un objeto y se encontro {_tname(item)}", structural=True))
                    continue
                check_mapping(item, sub, file, f"{path}[{i}]", out)
        return

    if kind == "dict":
        if not isinstance(value, dict):
            out.append(Finding(ERROR, file, path, f"se esperaba un objeto y se encontro {_tname(value)}", structural=True))
            return
        if isinstance(schema.get("campos"), dict):
            check_mapping(value, schema["campos"], file, path, out)
        return

    # string / enum: escalares
    if isinstance(value, (dict, list)):
        out.append(Finding(ERROR, file, path, f"se esperaba un string y se encontro {_tname(value)}", structural=True))
        return

    if allowed is not None:
        if not isinstance(value, str) or value not in allowed:
            hint = ""
            near = _closest(value, allowed)
            if near:
                hint = f" El valor {near!r} existe, pero el casing y la puntuacion deben ser exactos."
            doc = f" Ver {VOCAB_DOC}." if path.split(".")[-1].split("[")[0] == "status" or path.endswith("status") else ""
            out.append(
                Finding(
                    ERROR,
                    file,
                    path,
                    f"valor {value!r} no permitido. Valores permitidos: {', '.join(allowed)}.{hint}{doc}",
                )
            )
        return

    if not isinstance(value, str):
        if isinstance(value, (datetime.date, datetime.datetime)) and "fecha" in str(schema.get("tipo", "")):
            return
        out.append(Finding(AVISO, file, path, f"se esperaba un string y se encontro {_tname(value)} ({value!r}); entrecomillarlo"))
        return

    max_length = schema.get("max_length")
    if isinstance(max_length, int) and len(value) > max_length:
        if path == "task":
            return  # la longitud de `task` tiene reglas propias (aviso/error)
        out.append(Finding(ERROR, file, path, f"longitud {len(value)} supera el maximo de {max_length}: {value!r}", structural=True))


def check_mapping(
    data: dict[str, Any],
    schema: dict[str, Any],
    file: str,
    prefix: str,
    out: list[Finding],
) -> None:
    for name, field_schema in schema.items():
        if not isinstance(field_schema, dict):
            continue
        path = f"{prefix}.{name}" if prefix else name
        if name not in data or data[name] is None:
            if is_required(field_schema):
                out.append(Finding(ERROR, file, path, "campo obligatorio ausente o vacio", structural=True))
            continue
        check_field(data[name], field_schema, file, path, out)


def _tname(value: Any) -> str:
    return {
        dict: "un objeto",
        list: "una lista",
        str: "un string",
        int: "un numero",
        float: "un numero",
        bool: "un booleano",
    }.get(type(value), type(value).__name__)


# --------------------------------------------------------------------------- tasks


def check_task_length(task: Any, file: str, out: list[Finding]) -> None:
    if not isinstance(task, str):
        return
    n = len(task)
    if n > TASK_HARD_LIMIT:
        out.append(
            Finding(
                ERROR,
                file,
                "task",
                f"longitud {n} supera el limite duro de la plataforma ({TASK_HARD_LIMIT}); "
                f"la guia es {TASK_SOFT_LIMIT}. Valor: {task!r}",
            )
        )
    elif n > TASK_SOFT_LIMIT:
        out.append(
            Finding(
                AVISO,
                file,
                "task",
                f"longitud {n} excede la guia de {TASK_SOFT_LIMIT} caracteres (limite duro {TASK_HARD_LIMIT}); acortar. Valor: {task!r}",
            )
        )
    if not SNAKE_RE.match(task):
        out.append(Finding(AVISO, file, "task", f"se esperaba snake_case en minusculas: {task!r}"))


def is_legacy(path: Path) -> bool:
    parts = path.resolve().parts
    return any(parts[i : i + 2] == ("docs", "features") for i in range(len(parts) - 1))


def check_task_filename(path: Path, file: str, out: list[Finding]) -> None:
    stem = path.name[: -len(path.suffix)] if path.suffix else path.name
    if path.suffix != ".yaml":
        out.append(Finding(ERROR, file, "nombre de archivo", f"la extension debe ser .yaml, no {path.suffix!r}"))
    if len(stem) > TASK_FILE_MAX:
        out.append(
            Finding(ERROR, file, "nombre de archivo", f"{len(stem)} caracteres sin extension; el maximo es {TASK_FILE_MAX}: {stem!r}")
        )
    if TASK_FILE_RE.match(stem):
        return
    if LEGACY_TASK_FILE_RE.match(stem) and is_legacy(path):
        out.append(
            Finding(AVISO, file, "nombre de archivo", f"formato legado NN_snake_case ({stem!r}); el vigente es NN-accion-componente.yaml")
        )
        return
    out.append(
        Finding(
            ERROR,
            file,
            "nombre de archivo",
            f"{stem!r} no cumple NN-accion-componente.yaml (NN de 2 digitos, kebab-case en minusculas, guion medio tras NN)",
        )
    )


def check_task_filename_coherence(path: Path, data: dict[str, Any], file: str, out: list[Finding]) -> None:
    task = data.get("task")
    if not isinstance(task, str):
        return
    stem = path.stem
    m = re.match(r"^\d{2}[-_](.+)$", stem)
    if not m:
        return
    expected = m.group(1).replace("_", "-")
    if task.replace("_", "-") != expected:
        out.append(
            Finding(AVISO, file, "task", f"no coincide con el nombre de archivo sin contador ({expected!r}): {task!r}")
        )


def check_depends_on(data: dict[str, Any], siblings: set[str], file: str, out: list[Finding]) -> None:
    deps = data.get("depends_on")
    if not isinstance(deps, list) or not siblings:
        return
    task = data.get("task")
    for dep in deps:
        if dep == task:
            out.append(Finding(ERROR, file, "depends_on", f"la task depende de si misma: {dep!r}"))
        elif dep not in siblings:
            out.append(Finding(AVISO, file, "depends_on", f"{dep!r} no es el campo `task` de ninguna task hermana de este directorio"))


# --------------------------------------------------------------------------- archivos


def detect_type(path: Path) -> str | None:
    name = path.name
    if name.endswith(".schema.yaml"):
        return None
    if name.endswith(".example.yaml"):
        base = name[: -len(".example.yaml")]
        return base if base in SPEC_TYPES else None
    if name in DETECTED_NAMES:
        return DETECTED_NAMES[name]
    if path.parent.name == "tasks" and path.suffix in (".yaml", ".yml"):
        return "task"
    return None


def validate_file(
    path: Path,
    spec_type: str,
    schemas: dict[str, dict[str, Any]],
    display: str | None = None,
    sibling_tasks: set[str] | None = None,
) -> list[Finding]:
    file = display or str(path)
    out: list[Finding] = []
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
    except yaml.YAMLError as exc:
        return _legacy_adjust(
            [Finding(ERROR, file, "", f"YAML invalido: {str(exc).splitlines()[0] if str(exc) else exc}", structural=True)], path
        )
    except OSError as exc:
        return [Finding(ERROR, file, "", f"no se pudo leer: {exc}")]
    if not isinstance(data, dict):
        return _legacy_adjust([Finding(ERROR, file, "", "el documento debe ser un mapa YAML en la raiz", structural=True)], path)

    schema = schemas[spec_type]
    check_mapping(data, schema, file, "", out)

    for key in data:
        if key not in schema:
            out.append(Finding(AVISO, file, str(key), "campo no declarado en el schema; la plataforma puede rechazarlo"))

    if spec_type == "technical" and "status" in data:
        out.append(
            Finding(AVISO, file, "status", f"technical.yaml no tiene estado; eliminar el campo. Ver {VOCAB_DOC}")
        )

    if spec_type == "task":
        check_task_length(data.get("task"), file, out)
        if path.parent.name == "tasks" and not path.name.endswith(".example.yaml"):
            check_task_filename(path, file, out)
            check_task_filename_coherence(path, data, file, out)
            check_depends_on(data, sibling_tasks or set(), file, out)
    return _legacy_adjust(out, path)


def _legacy_adjust(findings: list[Finding], path: Path) -> list[Finding]:
    """En docs/features (documentos legados) los errores estructurales pasan a AVISO."""
    if not is_legacy(path):
        return findings
    return [
        Finding(AVISO, f.file, f.field, f"(legado) {f.message}", f.structural) if f.level == ERROR and f.structural else f
        for f in findings
    ]


def collect_targets(paths: list[str]) -> list[Path]:
    found: list[Path] = []
    for raw in paths:
        p = Path(raw)
        if p.is_dir():
            for root, dirs, files in os.walk(p):
                dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
                for f in sorted(files):
                    if f.endswith((".yaml", ".yml")):
                        found.append(Path(root) / f)
        else:
            found.append(p)
    return found


def _task_names(directory: Path) -> set[str]:
    names: set[str] = set()
    for f in directory.glob("*.y*ml"):
        try:
            d = yaml.safe_load(f.read_text(encoding="utf-8"))
        except (yaml.YAMLError, OSError):
            continue
        if isinstance(d, dict) and isinstance(d.get("task"), str):
            names.add(d["task"])
    return names


def validate_paths(paths: list[str], schemas_dir: Path = DEFAULT_SCHEMAS_DIR) -> tuple[list[Finding], int]:
    schemas = load_schemas(schemas_dir)
    findings: list[Finding] = []
    validated = 0
    sibling_cache: dict[Path, set[str]] = {}
    for path in collect_targets(paths):
        if not path.exists():
            findings.append(Finding(ERROR, str(path), "", "la ruta no existe"))
            continue
        spec_type = detect_type(path)
        if spec_type is None:
            continue
        siblings = None
        if spec_type == "task" and path.parent.name == "tasks":
            siblings = sibling_cache.setdefault(path.parent, _task_names(path.parent))
        findings.extend(validate_file(path, spec_type, schemas, sibling_tasks=siblings))
        validated += 1
    return findings, validated


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Valida specs SDD contra context/sdd-specs/*.schema.yaml")
    parser.add_argument("paths", nargs="+", help="directorios o archivos a validar")
    parser.add_argument("--schemas-dir", type=Path, default=DEFAULT_SCHEMAS_DIR)
    parser.add_argument("--quiet", action="store_true", help="no imprimir los avisos")
    args = parser.parse_args(argv)

    try:
        findings, validated = validate_paths(args.paths, args.schemas_dir)
    except (FileNotFoundError, KeyError) as exc:
        sys.stderr.write(f"No se pudieron cargar los schemas: {exc}\n")
        return 2

    errors = [f for f in findings if f.level == ERROR]
    warnings = [f for f in findings if f.level == AVISO]
    for f in errors:
        print(f.render())
    if not args.quiet:
        for f in warnings:
            print(f.render())
    print(f"\nSpecs validadas: {validated} | errores: {len(errors)} | avisos: {len(warnings)}")
    if validated == 0:
        print("AVISO: no se encontro ninguna spec (feature/change/technical/tasks) en las rutas indicadas")
    if errors:
        print("Resultado: FALLO (hay errores)")
        return 1
    print("Resultado: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
