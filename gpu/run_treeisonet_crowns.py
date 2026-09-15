#!/usr/bin/env python3
# #M7 crown variant (#20): treeLoc -> postPeakExtraction seeds -> treeOff offset
# net -> per-point instance ids. Writes the labeled CANOPY points (height >= hmin
# in the normalized frame, so ground returns don't inflate the crown footprint)
# as a CSV (x y z crown_id) in UTM. R reduces these to apexes (reduce_instances)
# and crown diameters (crown_diameter_table) for the crown-diameter benchmark.
#
# Usage: run_treeisonet_crowns.py <input.laz> <out.csv> <loc.pth> <loc.json>
#            <off.pth> <off.json> [voxel] [conf] [hmin] [aligned.laz]
#   voxel <= 0 -> checkpoint native; scalar >0 -> isotropic override;
#   "x,y,z" -> anisotropic override.
import os, sys, json, numpy as np, laspy
from treeisonet_export import prediction_support, canopy_labels
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "TreeAIBox"))
from modules.treeisonet.treeLoc import treeLoc, postPeakExtraction
from modules.treeisonet.treeOff import treeOff

if len(sys.argv) < 7:
    sys.exit("Usage: run_treeisonet_crowns.py <input.laz> <out.csv> <loc.pth> "
             "<loc.json> <off.pth> <off.json> [voxel] [conf] [hmin]")
inp, out, loc_pth, loc_cfg, off_pth, off_cfg = sys.argv[1:7]
voxel = sys.argv[7] if len(sys.argv) > 7 else "0"
conf  = float(sys.argv[8]) if len(sys.argv) > 8 else 0.22
hmin  = float(sys.argv[9]) if len(sys.argv) > 9 else 2.0
aligned_out = sys.argv[10] if len(sys.argv) > 10 else None
HEADER = "x y z crown_id"

def write_aligned(labels):
    if aligned_out:
        las.add_extra_dim(laspy.ExtraBytesParams(name="tree_pred", type=np.int32))
        las.tree_pred = labels
        las.write(aligned_out)

def write_empty():
    with open(out, "w") as f:
        f.write(HEADER + "\n")
    write_aligned(np.zeros(len(las.points), dtype=np.int32))
    if os.environ.get("TREEISONET_AUDIT_OUT"):
        xyz = np.column_stack([las.x, las.y, las.z])
        np.savez_compressed(os.environ["TREEISONET_AUDIT_OUT"], xyz=xyz,
                            raw_ids=np.zeros(len(xyz)), labels=np.zeros(len(xyz)),
                            support=np.zeros(len(xyz), dtype=bool),
                            shifted_z=xyz[:, 2] - (xyz[:, 2].min() if len(xyz) else 0),
                            seeds=np.empty((0, 3)), hmin=hmin, confidence=conf)

def voxel_resolution(arg):
    vals = [float(v) for v in str(arg).split(",")]
    if len(vals) == 1:
        v = vals[0]
        return np.array([v, v, v]) if v > 0 else np.zeros(3)
    if len(vals) == 3 and all(v > 0 for v in vals):
        return np.array(vals)
    raise SystemExit("ERROR: voxel must be <=0, a positive scalar, or 'x,y,z'")

las = laspy.read(inp)
try:
    epsg = las.header.parse_crs().to_epsg()
except Exception:
    epsg = None
if epsg == 3857:
    sys.exit("ERROR: input is EPSG:3857 (web-mercator); reproject to metric UTM")
pcd = np.transpose([np.asarray(las.x), np.asarray(las.y), np.asarray(las.z)]).astype(float)
if pcd.shape[0] == 0:
    write_empty(); sys.exit(0)
pmin = pcd.min(0); pcd[:, :3] -= pmin
cr = voxel_resolution(voxel)
preds_raw = treeLoc(loc_cfg, pcd, loc_pth, use_cuda=True,
                    if_stem=False, custom_resolution=cr)
if preds_raw is None:
    sys.exit("ERROR: treeLoc returned no result")
preds = np.asarray(preds_raw)
if preds.size == 0:
    write_empty(); sys.exit(0)
preds = np.atleast_2d(preds)
if preds.shape[1] < 4:
    sys.exit(f"ERROR: treeLoc returned {preds.shape[1]} columns; expected at least 4")
sel = preds[preds[:, 3] > conf]
nseed = sel.shape[0]
if nseed == 0:
    write_empty(); sys.exit(0)
if nseed == 1:
    tops = sel[:, :3]
else:
    tops_raw = np.asarray(postPeakExtraction(sel, K=min(5, nseed)))
    if tops_raw.size == 0:
        write_empty(); sys.exit(0)
    tops_raw = np.atleast_2d(tops_raw)
    if tops_raw.shape[1] < 3:
        sys.exit(f"ERROR: postPeakExtraction returned {tops_raw.shape[1]} columns; expected at least 3")
    tops = tops_raw[:, :3]
if tops.shape[0] == 0:
    write_empty(); sys.exit(0)
ids_raw = treeOff(off_cfg, pcd, tops, off_pth, use_cuda=True,
                  custom_resolution=cr)
if ids_raw is None:
    sys.exit("ERROR: treeOff returned no result")
ids = np.asarray(ids_raw).reshape(-1)  # per-point 1..N
if ids.size != pcd.shape[0]:
    sys.exit(f"ERROR: treeOff returned {ids.size} labels for {pcd.shape[0]} points")
xyz = pcd[:, :3] + pmin[:3]                                # back to UTM + height frame
with open(off_cfg) as stream:
    config = json.load(stream)["model"]
resolution = cr if np.all(cr > 0) else config["voxel_resolution_in_meter"]
support = prediction_support(pcd, config["voxel_number_in_block"], resolution)
fixed = canopy_labels(xyz, ids, support, hmin)
if os.environ.get("TREEISONET_AUDIT_OUT"):
    np.savez_compressed(os.environ["TREEISONET_AUDIT_OUT"], xyz=xyz, raw_ids=ids,
                        support=support, labels=fixed, shifted_z=pcd[:, 2],
                        seeds=tops + pmin[:3], hmin=hmin, confidence=conf)
ids = fixed
keep = ids > 0
write_aligned(fixed)
if not keep.any():
    with open(out, "w") as stream:
        stream.write(HEADER + "\n")
    sys.exit(0)
arr = np.column_stack([xyz[keep], ids[keep].astype(int)])
np.savetxt(out, arr, header=HEADER, comments="",
           fmt=["%.3f", "%.3f", "%.3f", "%d"])
print(f"wrote {int(keep.sum())} canopy pts in {len(np.unique(ids[keep]))} crowns -> {out}")
