"""Tests del validador de specs SDD.

Ejecutar: python3 -m unittest discover -s scripts/tests -v
"""

import shutil
import sys
import tempfile
import unittest
from pathlib import Path

import yaml

SCRIPTS = Path(__file__).resolve().parent.parent
REPO = SCRIPTS.parent
sys.path.insert(0, str(SCRIPTS))

import validate_specs as vs  # noqa: E402

SCHEMAS_DIR = REPO / "context" / "sdd-specs"


def load_example(name):
    return yaml.safe_load((SCHEMAS_DIR / f"{name}.example.yaml").read_text(encoding="utf-8"))


class SpecTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.schemas = vs.load_schemas(SCHEMAS_DIR)

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)

    def write(self, rel, data):
        path = self.tmp / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(yaml.safe_dump(data, allow_unicode=True, sort_keys=False), encoding="utf-8")
        return path

    def run_validator(self, rel, data, spec_type):
        path = self.write(rel, data)
        return vs.validate_file(path, spec_type, self.schemas)

    def task(self, **overrides):
        data = load_example("task")
        data.update(overrides)
        return data

    def errors(self, findings, field=None):
        return [f for f in findings if f.level == vs.ERROR and (field is None or f.field == field)]

    def warnings(self, findings, field=None):
        return [f for f in findings if f.level == vs.AVISO and (field is None or f.field == field)]


class TaskStatusTests(SpecTestCase):
    def test_all_four_task_statuses_are_valid(self):
        for status in ("PENDING", "IN_PROGRESS", "COMPLETED", "BLOCKED"):
            with self.subTest(status=status):
                findings = self.run_validator("t/tasks/01-create-x.yaml", self.task(task="create_x", status=status), "task")
                self.assertEqual(self.errors(findings), [])

    def test_invalid_task_statuses_are_rejected(self):
        for status in ("DONE", "PLANNED", "TODO", "IN-PROGRESS", "CANCELLED", "Completed", "pending", "planned"):
            with self.subTest(status=status):
                findings = self.run_validator("t/tasks/01-create-x.yaml", self.task(task="create_x", status=status), "task")
                errs = self.errors(findings, "status")
                self.assertEqual(len(errs), 1)
                self.assertIn(repr(status), errs[0].message)
                self.assertIn("PENDING, IN_PROGRESS, COMPLETED, BLOCKED", errs[0].message)

    def test_missing_status_is_error(self):
        data = self.task(task="create_x")
        del data["status"]
        findings = self.run_validator("t/tasks/01-create-x.yaml", data, "task")
        self.assertTrue(self.errors(findings, "status"))


class ChangeAndFeatureStatusTests(SpecTestCase):
    def test_change_lowercase_statuses_valid(self):
        for status in ("planned", "in-progress", "completed", "cancelled"):
            with self.subTest(status=status):
                data = load_example("change")
                data["status"] = status
                self.assertEqual(self.errors(self.run_validator("c/change.yaml", data, "change")), [])

    def test_change_uppercase_status_invalid(self):
        for status in ("PLANNED", "COMPLETED", "in_progress", "Completed", "BLOCKED", "DONE"):
            with self.subTest(status=status):
                data = load_example("change")
                data["status"] = status
                self.assertEqual(len(self.errors(self.run_validator("c/change.yaml", data, "change"), "status")), 1)

    def test_casing_hint_mentions_exact_value(self):
        data = load_example("change")
        data["status"] = "in_progress"
        err = self.errors(self.run_validator("c/change.yaml", data, "change"), "status")[0]
        self.assertIn("'in-progress'", err.message)

    def test_feature_status_enum(self):
        data = load_example("feature")
        self.assertEqual(self.errors(self.run_validator("f/feature.yaml", data, "feature")), [])
        data["status"] = "PLANNED"
        self.assertEqual(len(self.errors(self.run_validator("f/feature.yaml", data, "feature"), "status")), 1)

    def test_feature_without_status_is_valid(self):
        data = load_example("feature")
        data.pop("status", None)
        self.assertEqual(self.errors(self.run_validator("f/feature.yaml", data, "feature")), [])

    def test_dependency_feature_status_is_enum(self):
        data = load_example("change")
        data["dependencies"]["features"][0]["status"] = "done"
        errs = self.errors(self.run_validator("c/change.yaml", data, "change"))
        self.assertEqual([e.field for e in errs], ["dependencies.features[0].status"])
        data["dependencies"]["features"][0]["status"] = "in-progress"
        self.assertEqual(self.errors(self.run_validator("c/change.yaml", data, "change")), [])
        data["dependencies"]["features"][0]["status"] = "COMPLETED"
        self.assertEqual(len(self.errors(self.run_validator("c/change.yaml", data, "change"))), 1)

    def test_technical_with_status_warns(self):
        data = load_example("technical")
        data["status"] = "PENDING"
        findings = self.run_validator("f/technical.yaml", data, "technical")
        self.assertTrue(self.warnings(findings, "status"))


class SchemaVocabularyTests(SpecTestCase):
    """El schema es la fuente de verdad; el doc canonico debe coincidir con el."""

    def test_schema_status_values_match_canonical_vocabulary(self):
        expected = {
            "task": ["PENDING", "IN_PROGRESS", "COMPLETED", "BLOCKED"],
            "change": ["planned", "in-progress", "completed", "cancelled"],
            "feature": ["planned", "in-progress", "completed", "cancelled"],
        }
        for spec_type, values in expected.items():
            with self.subTest(spec_type=spec_type):
                self.assertEqual(vs.allowed_values(self.schemas[spec_type]["status"]), values)
        self.assertNotIn("status", self.schemas["technical"])
        dep = self.schemas["change"]["dependencies"]["campos"]["features"]["campos_por_item"]["status"]
        self.assertEqual(vs.allowed_values(dep), expected["feature"])

    def test_doc_lists_every_value(self):
        doc = (SCHEMAS_DIR / "status-vocabulary.md").read_text(encoding="utf-8")
        for value in ("PENDING", "IN_PROGRESS", "COMPLETED", "BLOCKED", "planned", "in-progress", "completed", "cancelled"):
            self.assertIn(f"`{value}`", doc)

    def test_level_enum_with_description_format(self):
        self.assertEqual(vs.allowed_values(self.schemas["task"]["level"]), ["L1", "L2", "L3", "L4", "L5"])
        findings = self.run_validator("t/tasks/01-create-x.yaml", self.task(task="create_x", level="L9"), "task")
        self.assertEqual(len(self.errors(findings, "level")), 1)


class TaskLengthTests(SpecTestCase):
    def task_findings(self, length):
        name = "a" * length
        return self.run_validator(f"t/tasks/01-{name}.yaml", self.task(task=name), "task")

    def test_47_chars_ok(self):
        findings = self.task_findings(47)
        self.assertEqual(self.errors(findings, "task"), [])
        self.assertEqual(self.warnings(findings, "task"), [])

    def test_48_chars_warns(self):
        findings = self.task_findings(48)
        self.assertEqual(self.errors(findings, "task"), [])
        self.assertEqual(len(self.warnings(findings, "task")), 1)
        self.assertIn("48", self.warnings(findings, "task")[0].message)

    def test_100_chars_warns_only(self):
        findings = self.task_findings(100)
        self.assertEqual(self.errors(findings, "task"), [])
        self.assertTrue(self.warnings(findings, "task"))

    def test_101_chars_error(self):
        findings = self.task_findings(101)
        self.assertEqual(len(self.errors(findings, "task")), 1)
        self.assertIn("101", self.errors(findings, "task")[0].message)

    def test_51_chars_is_not_error_anymore(self):
        # el caso que abortaba el sync con el limite antiguo de 50
        self.assertEqual(self.errors(self.task_findings(51), "task"), [])


class TaskFilenameTests(SpecTestCase):
    def names(self, filename, task="create_x"):
        return self.run_validator(f"t/tasks/{filename}", self.task(task=task), "task")

    def test_valid_filename(self):
        self.assertEqual(self.errors(self.names("01-create-x.yaml")), [])

    def test_bad_filenames_are_errors(self):
        for name in ("1-create-x.yaml", "001-create-x.yaml", "01_create_x.yaml", "01-Create-X.yaml", "create-x.yaml", "01-create-x.yml"):
            with self.subTest(name=name):
                self.assertTrue(self.errors(self.names(name), "nombre de archivo"))

    def test_filename_over_50_chars_error(self):
        name = "01-" + "a" * 48 + ".yaml"  # 51 sin extension
        self.assertTrue(self.errors(self.names(name), "nombre de archivo"))
        name = "01-" + "a" * 47 + ".yaml"  # 50 sin extension
        self.assertEqual(self.errors(self.names(name), "nombre de archivo"), [])

    def test_legacy_snake_filename_is_warning_under_docs_features(self):
        findings = self.run_validator("docs/features/x/tasks/01_create_x.yaml", self.task(task="create_x"), "task")
        self.assertEqual(self.errors(findings), [])
        self.assertTrue(self.warnings(findings, "nombre de archivo"))

    def test_legacy_free_phase_and_structure_do_not_error(self):
        data = self.task(task="create_x", phase=1)
        del data["acceptance"]
        findings = self.run_validator("docs/features/x/tasks/01_create_x.yaml", data, "task")
        self.assertEqual(self.errors(findings), [])

    def test_legacy_enum_violation_still_error(self):
        findings = self.run_validator("docs/features/x/tasks/01_create_x.yaml", self.task(task="create_x", status="DONE"), "task")
        self.assertEqual(len(self.errors(findings, "status")), 1)

    def test_depends_on_unknown_is_warning(self):
        path = self.write("t/tasks/01-create-x.yaml", self.task(task="create_x", depends_on=["ghost"]))
        findings = vs.validate_file(path, "task", self.schemas, sibling_tasks={"create_x"})
        self.assertTrue(self.warnings(findings, "depends_on"))


class StructureTests(SpecTestCase):
    def test_examples_pass_without_errors(self):
        for spec_type in vs.SPEC_TYPES:
            with self.subTest(spec_type=spec_type):
                path = SCHEMAS_DIR / f"{spec_type}.example.yaml"
                findings = vs.validate_file(path, spec_type, self.schemas)
                self.assertEqual(self.errors(findings), [])

    def test_missing_required_field(self):
        data = load_example("change")
        del data["title"]
        self.assertTrue(self.errors(self.run_validator("c/change.yaml", data, "change"), "title"))

    def test_wrong_type(self):
        data = load_example("change")
        data["affected_repos"] = "warehouse-api"
        self.assertTrue(self.errors(self.run_validator("c/change.yaml", data, "change"), "affected_repos"))

    def test_max_length_title(self):
        data = load_example("change")
        data["title"] = "x" * 101
        self.assertTrue(self.errors(self.run_validator("c/change.yaml", data, "change"), "title"))

    def test_invalid_yaml(self):
        path = self.tmp / "c" / "change.yaml"
        path.parent.mkdir()
        path.write_text("a: [unclosed\n", encoding="utf-8")
        findings = vs.validate_file(path, "change", self.schemas)
        self.assertEqual(len(self.errors(findings)), 1)

    def test_detect_type(self):
        self.assertEqual(vs.detect_type(Path("x/feature.yaml")), "feature")
        self.assertEqual(vs.detect_type(Path("x/tasks/01-a.yaml")), "task")
        self.assertEqual(vs.detect_type(Path("x/task.example.yaml")), "task")
        self.assertIsNone(vs.detect_type(Path("x/task.schema.yaml")))
        self.assertIsNone(vs.detect_type(Path("x/product.yaml")))


class CliTests(SpecTestCase):
    def test_exit_code(self):
        self.write("ok/tasks/01-create-x.yaml", self.task(task="create_x"))
        self.write("bad/tasks/01-create-x.yaml", self.task(task="create_x", status="DONE"))
        self.assertEqual(vs.main([str(self.tmp / "ok")]), 0)
        self.assertEqual(vs.main([str(self.tmp / "bad")]), 1)
        self.assertEqual(vs.main([str(self.tmp / "missing")]), 1)

    def test_examples_dir_exit_zero(self):
        self.assertEqual(vs.main(["--quiet", str(SCHEMAS_DIR)]), 0)


if __name__ == "__main__":
    unittest.main()
