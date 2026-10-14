"""Load a ForestMamba checkpoint's state_dict without unpickling arbitrary code.

The released checkpoint is an mmengine pickle. Besides tensors it carries
numpy arrays and the logger's HistoryBuffer, whose statistics methods are
pickled as builtins.getattr(HistoryBuffer, name), so torch's weights_only
loader rejects it and weights_only=False would run whatever the pickle names.
Here only the audited globals resolve: torch's tensor rebuild (storages are
resolved by torch itself), OrderedDict, numpy arrays/dtypes/scalars and the
protocol-2 bytes helper. The HistoryBuffer and its getattr become inert stubs,
never imported or called; any other global stops the load.
"""
import _compat_pickle
import pickle
import zipfile

import torch

ALLOWED = {
    ("torch._utils", "_rebuild_tensor_v2"), ("collections", "OrderedDict"),
    ("numpy", "dtype"), ("numpy", "ndarray"), ("_codecs", "encode"),
    ("numpy.core.multiarray", "_reconstruct"), ("numpy.core.multiarray", "scalar"),
    ("numpy._core.multiarray", "_reconstruct"), ("numpy._core.multiarray", "scalar"),
}
INERT_MODULES = ("mmengine.logging.history_buffer",)


class _Inert:
    """Stands in for a logging object; state is discarded."""

    def __init__(self, *args, **kwargs):
        pass

    def __setstate__(self, state):
        pass


def _inert_getattr(obj, name):
    if obj is not _Inert:
        raise pickle.UnpicklingError(f"Disallowed getattr on {obj!r}")
    return _Inert


class _Unpickler(pickle.Unpickler):
    def find_class(self, module, name):
        module = _compat_pickle.IMPORT_MAPPING.get(module, module)   # __builtin__ -> builtins
        if (module, name) in ALLOWED:
            return super().find_class(module, name)
        if module in INERT_MODULES:
            return _Inert
        if (module, name) == ("builtins", "getattr"):
            return _inert_getattr
        raise pickle.UnpicklingError(f"Disallowed global in checkpoint: {module} {name}")


class _PickleModule:          # the pickle_module duck type torch.load expects
    Unpickler = _Unpickler
    load = staticmethod(lambda f, **kwargs: _Unpickler(f, **kwargs).load())
    __name__ = "fm_checkpoint_pickle"


def load_state_dict(path):
    """The checkpoint's state_dict (CPU tensors).

    Only a plain torch zip checkpoint is read: the legacy and tar formats read
    records with pickle_module.load outside the archive, and torch hands a
    TorchScript archive to torch.jit.load before any unpickler runs.
    """
    if not zipfile.is_zipfile(path):
        raise ValueError(f"Not a zip checkpoint: {path}")
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
    if any(n.endswith("/constants.pkl") or "/code/" in n for n in names):
        raise ValueError(f"TorchScript archive refused: {path}")
    # weights_only=False only because torch requires it with a custom
    # pickle_module; _Unpickler.find_class is the allowlist that keeps it safe.
    checkpoint = torch.load(path, map_location="cpu", weights_only=False,
                            pickle_module=_PickleModule)
    return checkpoint["state_dict"]
