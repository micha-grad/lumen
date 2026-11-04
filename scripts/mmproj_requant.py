#!/usr/bin/env python3
"""Requantize a GGUF mmproj (vision encoder + projector) to another weight type.

Usage: mmproj_requant.py <gguf-py dir> <input.gguf> <output.gguf> <F16|Q8_0|Q5_0|Q4_0>

Policy (same as ggml-org's Q8_0 mmproj for this model): 2-D weight matrices
(attention q/k/v/out, FFN up/gate/down, projector mm.N and patch_merger) take the
target type; everything else (norms, patch_embd convolution, img_break, 1-D
tensors) is stored as F32. Metadata is copied unchanged.
"""
import sys

sys.path.insert(0, sys.argv[1])
import numpy as np  # noqa: E402
import gguf  # noqa: E402
from gguf import GGMLQuantizationType as Q  # noqa: E402

src, dst, target = sys.argv[2], sys.argv[3], sys.argv[4]
TARGET = {"F16": Q.F16, "Q8_0": Q.Q8_0, "Q5_0": Q.Q5_0, "Q4_0": Q.Q4_0}[target]


def is_matrix(name: str, shape) -> bool:
    if len(shape) != 2 or not name.endswith(".weight"):
        return False
    return any(k in name for k in ("attn_q", "attn_k", "attn_v", "attn_out", "ffn_up", "ffn_gate",
                                   "ffn_down", "patch_merger")) or name.startswith("mm.")


reader = gguf.GGUFReader(src)
arch = reader.fields[gguf.Keys.General.ARCHITECTURE].contents()
writer = gguf.GGUFWriter(dst, arch=arch, endianess=reader.endianess)

for field in reader.fields.values():
    if field.name == gguf.Keys.General.ARCHITECTURE or field.name.startswith("GGUF."):
        continue
    val_type = field.types[0]
    sub_type = field.types[-1] if val_type == gguf.GGUFValueType.ARRAY else None
    writer.add_key_value(field.name, field.contents(), val_type, sub_type=sub_type)

out = []
counts = {}
for t in reader.tensors:
    f32 = gguf.quants.dequantize(t.data, t.tensor_type).astype(np.float32)
    shape_ne = [int(x) for x in t.shape]  # ggml order (ne0 first)
    qtype = TARGET if is_matrix(t.name, shape_ne) else Q.F32
    if qtype == Q.F32:
        data = f32
    elif qtype == Q.F16:
        data = f32.astype(np.float16)
    else:
        data = gguf.quants.quantize(f32, qtype)
    counts[qtype.name] = counts.get(qtype.name, 0) + 1
    out.append((t.name, data, qtype))
    writer.add_tensor_info(t.name, data.shape, data.dtype, data.nbytes, qtype)

writer.write_header_to_file()
writer.write_kv_data_to_file()
writer.write_ti_data_to_file()
for _, data, _ in out:
    writer.write_tensor_data(data, tensor_endianess=reader.endianess)
writer.close()
print("wrote %s: %s" % (dst, ", ".join("%s=%d" % kv for kv in sorted(counts.items()))))
