"""Tests del validador empaquetado en la skill spec-reviewer y de la resolucion de schemas.

Ejecutar: python3 -m unittest discover -s scripts/tests -v
"""

import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import yaml

SCRIPTS = Path(__file__).resolve().parent.parent
REPO = SCRIPTS.parent
SOURCE_SCHEMAS = REPO / "context" / "sdd-specs"
SOURCE_SCRIPT = SCRIPTS / "validate_specs.py"
SKILLS = {
    "claude": REPO / "plugins" / "general" / "skills" / "spec-reviewer",
    "gemini": REPO / "gemini" / "spec-generator" / ".gemini" / "skills" / "spec-reviewer",
}
SCHEMA_NAMES = ("feature", "change", "technical", "task")


def run(script, args, cwd, env_extra=None, drop_env=("SDD_SCHEMAS_DIR",)):
    env = {k: v for k, v in os.environ.items() if k not in drop_env}
    env.update(env_extra or {})
    return subprocess.run(
        [sys.executable, str(script), *args], cwd=cwd, env=env, capture_output=True, text=True
    )


class TempDirCase(unittest.TestCase):
    def setUp(self):
        # cwd ajeno al repo: ni el script ni el cwd pueden hallar context/sdd-specs
        self.tmp = Path(tempfile.mkdtemp(prefix="sdd-validator-")).resolve()
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)

    def write_example(self, name, rel, mutate=None):
        data = yaml.safe_load((SOURCE_SCHEMAS / f"{name}.example.yaml").read_text(encoding="utf-8"))
        if mutate:
            mutate(data)
        path = self.tmp / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(yaml.safe_dump(data, allow_unicode=True, sort_keys=False), encoding="utf-8")
        return path


class PackagedValidatorTests(TempDirCase):
    def test_packaged_copies_validate_and_reject_with_only_bundled_schemas(self):
        for label, skill in SKILLS.items():
            with self.subTest(skill=label):
                script = skill / "scripts" / "validate_specs.py"
                good = self.write_example("task", f"{label}/ok/tasks/01-create-thing.yaml")
                r = run(script, [str(good)], cwd=self.tmp)
                self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
                self.assertIn("Resultado: OK", r.stdout)

                bad = self.write_example(
                    "task",
                    f"{label}/bad/tasks/01-create-thing.yaml",
                    lambda d: d.update(status="DONE"),
                )
                r = run(script, [str(bad)], cwd=self.tmp)
                self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
                self.assertIn("DONE", r.stdout)

    def test_packaged_copies_validate_feature_example(self):
        for label, skill in SKILLS.items():
            with self.subTest(skill=label):
                spec = self.write_example("feature", f"{label}/feature.yaml")
                r = run(skill / "scripts" / "validate_specs.py", [str(spec)], cwd=self.tmp)
                self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_packaged_copies_match_source(self):
        for label, skill in SKILLS.items():
            with self.subTest(skill=label):
                self.assertEqual(
                    (skill / "scripts" / "validate_specs.py").read_bytes(), SOURCE_SCRIPT.read_bytes()
                )
                for name in SCHEMA_NAMES:
                    self.assertEqual(
                        (skill / "schemas" / f"{name}.schema.yaml").read_bytes(),
                        (SOURCE_SCHEMAS / f"{name}.schema.yaml").read_bytes(),
                        name,
                    )
                self.assertEqual(
                    (skill / "references" / "status-vocabulary.md").read_bytes(),
                    (SOURCE_SCHEMAS / "status-vocabulary.md").read_bytes(),
                )

    def test_sync_script_check_passes(self):
        r = subprocess.run(
            ["bash", str(SCRIPTS / "sync-spec-validator.sh"), "--check"], capture_output=True, text=True
        )
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)


class SchemaResolutionTests(TempDirCase):
    """Usa la copia de scripts/ en un directorio aislado para que no halle schemas por si sola."""

    def setUp(self):
        super().setUp()
        self.isolated = self.tmp / "iso" / "bin"
        self.isolated.mkdir(parents=True)
        self.script = self.isolated / "validate_specs.py"
        shutil.copy(SOURCE_SCRIPT, self.script)
        self.schemas = self.tmp / "custom-schemas"
        shutil.copytree(SOURCE_SCHEMAS, self.schemas, ignore=shutil.ignore_patterns("*.example.yaml"))
        self.spec = self.write_example("task", "work/tasks/01-create-thing.yaml")
        self.work = self.tmp / "work"

    def test_no_schemas_anywhere_exits_2(self):
        r = run(self.script, [str(self.spec)], cwd=self.work)
        self.assertEqual(r.returncode, 2, r.stdout + r.stderr)
        self.assertIn("--schemas", r.stderr)

    def test_schemas_option(self):
        r = run(self.script, ["--schemas", str(self.schemas), str(self.spec)], cwd=self.work)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_schemas_dir_alias(self):
        r = run(self.script, ["--schemas-dir", str(self.schemas), str(self.spec)], cwd=self.work)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_env_variable(self):
        r = run(self.script, [str(self.spec)], cwd=self.work, env_extra={"SDD_SCHEMAS_DIR": str(self.schemas)})
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_option_takes_precedence_over_env(self):
        r = run(
            self.script,
            ["--schemas", str(self.schemas), str(self.spec)],
            cwd=self.work,
            env_extra={"SDD_SCHEMAS_DIR": str(self.tmp / "no-existe")},
        )
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_explicit_dir_without_schemas_fails_instead_of_falling_back(self):
        r = run(self.script, ["--schemas", str(self.tmp / "vacio"), str(self.spec)], cwd=self.work)
        self.assertEqual(r.returncode, 2, r.stdout + r.stderr)

    def test_bundled_schemas_next_to_script(self):
        shutil.copytree(self.schemas, self.isolated.parent / "schemas")  # <script>/../schemas
        r = run(self.script, [str(self.spec)], cwd=self.work)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_repo_mode_from_cwd(self):
        repo_like = self.tmp / "proj"
        shutil.copytree(self.schemas, repo_like / "context" / "sdd-specs")
        (repo_like / "sub").mkdir()
        r = run(self.script, [str(self.spec)], cwd=repo_like / "sub")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_missing_pyyaml_exits_2_with_install_hint(self):
        fake = self.tmp / "fake"
        fake.mkdir()
        (fake / "yaml.py").write_text("raise ImportError('simulado')\n", encoding="utf-8")
        r = run(
            self.script,
            ["--schemas", str(self.schemas), str(self.spec)],
            cwd=self.work,
            env_extra={"PYTHONPATH": str(fake)},
        )
        self.assertEqual(r.returncode, 2, r.stdout + r.stderr)
        self.assertIn("PyYAML", r.stderr)
        self.assertIn("python3 -m pip install --user pyyaml", r.stderr)


if __name__ == "__main__":
    unittest.main()
