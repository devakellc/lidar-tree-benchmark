# ForestMamba inference image for the RTX 5090 (sm_120). It is the
# ForestFormer3D image (torch 2.7.0 / CUDA 12.8, spconv-cu128, MinkowskiEngine,
# the pinned OpenMMLab stack) plus the Mamba kernels and the upstream
# mmengine/mmdet3d file swaps: ForestMamba is a fork of the ForestFormer3D
# code, so nothing else changes. Build ../forestformer3d-sm120 (tag ff3d-sm120)
# first; the benchmark's base was sha256:fd60f5cdc5ae880af13b339f4aa1f1e891a3809c7f39fb15d2b5ff04978799f3
# (setup.sh warns on another). fm_freeze.txt is the version lock of the result.
FROM ff3d-sm120:latest

# Prebuilt wheels for torch 2.7, CUDA 12, Python 3.11 and the C++11 ABI.
# Built with CUDA 12.9, they carry sm_120 kernels, so nothing is compiled.
# Upstream pins 1.1.1 for both; the Mamba v1 block it uses keeps its
# parameter names and kernels in these releases.
ARG MAMBA_URL=https://github.com/state-spaces/mamba/releases/download/v2.3.2.post1/mamba_ssm-2.3.2.post1%2Bcu12torch2.7cxx11abiTRUE-cp311-cp311-linux_x86_64.whl
ARG MAMBA_SHA256=62f046ec823624504066b077976730441d79ecab0045e46fd06167334421a3d1
ARG CONV_URL=https://github.com/Dao-AILab/causal-conv1d/releases/download/v1.6.2.post1/causal_conv1d-1.6.2.post1%2Bcu12torch2.7cxx11abiTRUE-cp311-cp311-linux_x86_64.whl
ARG CONV_SHA256=f60bdd32d31e458f4da15772a8b61d648893bc0443ef0d7bb29a27306e2aaa63
RUN pip install --no-cache-dir --no-deps \
      "mamba_ssm @ ${MAMBA_URL}#sha256=${MAMBA_SHA256}" \
      "causal_conv1d @ ${CONV_URL}#sha256=${CONV_SHA256}"

# `import mamba_ssm` loads its language-model head, which needs einops and the
# generation API of transformers (upstream's 4.36.0 pin lacks it). Exact
# versions, --no-deps: their other requirements are already in the base image.
# mamba-ssm 2.3 also lists tilelang, quack-kernels and triton>=3.5 for its
# Mamba-2/3 kernels; the Mamba v1 block never calls them, so they are not
# installed (pip reports them as unmet).
RUN pip install --no-cache-dir --no-deps "einops==0.8.2" "transformers==4.46.3" \
      "tokenizers==0.20.3" "huggingface_hub==0.36.2" "hf-xet==1.7.0" \
      "regex==2026.9.29" "safetensors==0.8.0"

# The driver calls test_step(data, epoch=...), which the upstream swap of
# mmengine's base_model.py provides; transforms_3d.py is swapped likewise. Both
# come from the pinned checkout (byte-identical to ForestFormer3D's), so the
# image does not depend on how its base was built. Upstream's loops.py swap
# (wandb logging for training) is not needed for inference and not applied.
ARG FM_REF=f0c5239d0d83e95f56508cdc20287f025a0b98db
RUN git clone --quiet https://github.com/thanhhff/ForestMamba.git /opt/forestmamba && \
    git -C /opt/forestmamba checkout --quiet "$FM_REF" && \
    SITE="$(python -c 'import site; print(site.getsitepackages()[0])')" && \
    cp /opt/forestmamba/replace_mmdetection_files/base_model.py "$SITE/mmengine/model/base_model/" && \
    cp /opt/forestmamba/replace_mmdetection_files/transforms_3d.py "$SITE/mmdet3d/datasets/transforms/" && \
    rm -rf /opt/forestmamba && \
    python -c "import inspect; from mmengine.model import BaseModel; \
assert 'epoch' in inspect.signature(BaseModel.test_step).parameters"

ENV WANDB_MODE=disabled
WORKDIR /workspace
CMD ["bash"]
