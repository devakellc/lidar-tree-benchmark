# SegmentAnyTree (#M6) stack-modernization compat shims, applied as a
# `usercustomize` module: any python started with this directory on PYTHONPATH
# auto-imports it at interpreter startup (site machinery), so the upstream
# eval.py / torch_points3d run UNMODIFIED. The driver puts this dir on the
# PYTHONPATH it hands to run_inference.sh.
#
# WHY: SAT pins torch 1.9 / CUDA 11.1 / hydra 1.0 / omegaconf 2.0 / old PyG. The
# RTX 5090 (sm_120) forces torch 2.7 / cu128 / py3.11, which drags hydra 1.3 +
# omegaconf 2.3 + modern PyG. That version jump breaks several runtime
# assumptions. Each shim below restores ONE behavior SAT was written against.
#
# STATUS (2026-06-09): together with the image's pinned deps (torch-geometric
# 2.3.1, hdbscan, pyarrow) and --shm-size/--ipc=host, these shims carry SAT
# inference END-TO-END on the 5090 (verified: SOAP-native clip -> labeled .laz
# with PredInstance). The four shims below each restore one behavior the 2023-era
# stack assumed; the torch-geometric pin (not a shim) fixes the Data.keys drift.
# A fifth function changes behavior only when SAT_CLUSTER_RADIUS is set: it
# replaces the grouping radius for the radius check, and is off for every
# benchmark run.
import warnings


def _patch_omegaconf_missing_attr():
    # omegaconf 2.0.6: reading a MISSING attribute on a struct-disabled config
    # returns None (the "optional config group" idiom, e.g. self._cfg.training).
    # omegaconf >= 2.2 raises ConfigAttributeError instead. torch_points3d relies
    # on the old behavior pervasively; restore it in one place.
    try:
        import omegaconf
        from omegaconf import OmegaConf, DictConfig
    except Exception:
        return
    if getattr(DictConfig, "_sat_compat_getattr", False):
        return
    _orig = DictConfig.__getattr__

    def _getattr(self, key):
        try:
            return _orig(self, key)
        except omegaconf.errors.ConfigAttributeError:
            if not OmegaConf.is_struct(self):
                return None
            raise

    DictConfig.__getattr__ = _getattr
    DictConfig._sat_compat_getattr = True


def _patch_torch_load_weights_only():
    # torch 2.6 flipped torch.load's weights_only default to True, which refuses
    # the omegaconf run_config pickled into the SAT checkpoint. The official
    # weights are trusted -> restore weights_only=False.
    try:
        import torch
    except Exception:
        return
    if getattr(torch, "_sat_compat_load", False):
        return
    _orig = torch.load

    def _load(*a, **k):
        k.setdefault("weights_only", False)
        return _orig(*a, **k)

    torch.load = _load
    torch._sat_compat_load = True


def _set_spawn_start_method():
    # SAT's meanshift/hdbscan clustering builds a multiprocessing.Pool AFTER the
    # model forward has initialized CUDA in the parent. The Linux default 'fork'
    # inherits the live CUDA context + torch's thread pool into the child, which
    # deadlocks (idle parent, zombie workers). 'spawn' starts a clean
    # interpreter -> CUDA-safe. SAT runs num_workers=0, so no DataLoader workers
    # are affected. Set at interpreter startup, before any Pool is created.
    try:
        import multiprocessing as mp
        if mp.get_start_method(allow_none=True) != "spawn":
            mp.set_start_method("spawn", force=True)
    except Exception:
        pass


def _patch_tensor_getitem_cross_device():
    # torch < ~2.1 auto-moved a device-mismatched index tensor; torch 2.7 raises
    # "indices should be ... on the same device as the indexed tensor". SAT's
    # 2023 code indexes CPU tensors with GPU index/mask tensors (and vice versa)
    # in several places (region_grow, PointGroup _compute_score, ...). Restore
    # the old leniency once: when a Tensor key's device != the tensor's, move the
    # key to the tensor's device, including tuple/list indexing forms such as
    # x[idx, :] and x[:, mask]. Fast path (non-Tensor keys) is untouched.
    try:
        import torch
    except Exception:
        return
    if getattr(torch.Tensor, "_sat_compat_getitem", False):
        return
    _orig = torch.Tensor.__getitem__

    def _normalize_key(key, device):
        if isinstance(key, torch.Tensor) and key.device != device:
            return key.to(device)
        if isinstance(key, tuple):
            return tuple(_normalize_key(k, device) for k in key)
        if isinstance(key, list):
            return [_normalize_key(k, device) for k in key]
        return key

    def _getitem(self, key):
        return _orig(self, _normalize_key(key, self.device))

    torch.Tensor.__getitem__ = _getitem
    torch.Tensor._sat_compat_getitem = True


def _patch_region_grow_radius():
    # Opt-in, for the radius check (scripts/sat_radius_check.R): SAT's type-5
    # clustering region-grows the offset-shifted tree points with
    # cluster_radius_search, 1.5 grid cells (0.3 m), against a mean point
    # spacing of 0.67 m at 2 points/m2. SAT_CLUSTER_RADIUS (metres) replaces
    # that radius in every region_grow call; unset or empty, nothing is
    # imported or changed. The model module binds region_grow by name when it
    # is imported, after this file runs. A malformed value raises here, which
    # the interpreter reports and then ignores, so callers must check for the
    # logged line (gpu/run_sat_radius_check.sh does).
    import os
    import sys
    value = os.environ.get("SAT_CLUSTER_RADIUS", "")
    if not value:
        return
    radius = float(value)
    if not radius > 0:
        raise ValueError("SAT_CLUSTER_RADIUS must be positive, got %r" % value)
    import torch_points_kernels as tpk
    if getattr(tpk, "_sat_compat_region_grow", False):
        return
    _orig = tpk.region_grow
    logged = []

    def _region_grow(*a, **k):
        # radius is the sixth positional argument of region_grow.
        if len(a) > 5:
            a = a[:5] + (radius,) + a[6:]
        else:
            k["radius"] = radius
        if not logged:
            sys.stderr.write("sat_compat: region_grow radius %.4f m\n" % radius)
            logged.append(True)
        return _orig(*a, **k)

    tpk.region_grow = _region_grow
    tpk._sat_compat_region_grow = True


def apply():
    _patch_omegaconf_missing_attr()
    _patch_torch_load_weights_only()
    _set_spawn_start_method()
    _patch_tensor_getitem_cross_device()
    _patch_region_grow_radius()


with warnings.catch_warnings():
    warnings.simplefilter("ignore")
    apply()
