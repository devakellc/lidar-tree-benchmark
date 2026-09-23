"""Checkpoint inspection treats pickle bytecode as data, never executable code."""
from pathlib import Path
import pickle
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from audit_fgiemit_checkpoints import inspect_checkpoint


class NeverExecute:
    def __reduce__(self):
        return (eval, ("1/0",))


class CheckpointInspectionTests(unittest.TestCase):
    def test_text_inspection_never_executes_serialized_calls(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "checkpoint.pt"
            with zipfile.ZipFile(path, "w") as archive:
                archive.writestr("archive/data.pkl", pickle.dumps(
                    {"dataset": "ForAINetV2", "payload": NeverExecute()}))
            result = inspect_checkpoint(path)
            self.assertIn("ForAINetV2", result["serialized_text_evidence"])
            self.assertFalse(result["pickle_executed"])
            self.assertFalse(result["model_loaded"])
            self.assertEqual(len(result["sha256"]), 64)

    def test_ambiguous_checkpoint_metadata_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "checkpoint.pt"
            with zipfile.ZipFile(path, "w") as archive:
                for prefix in ("one", "two"):
                    archive.writestr(f"{prefix}/data.pkl", pickle.dumps({}))
            with self.assertRaisesRegex(ValueError, "one checkpoint"):
                inspect_checkpoint(path)
