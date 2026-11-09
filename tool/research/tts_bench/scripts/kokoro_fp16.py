"""Make the published fp16 Kokoro export loadable by sherpa-onnx.

Usage: python3 -I kokoro_fp16.py SHERPA_MODEL.onnx model_fp16.onnx OUT.onnx
model_fp16.onnx is onnx/model_fp16.onnx of onnx-community/Kokoro-82M-v1.0-ONNX
on Hugging Face. Its inputs and outputs are fp32, as in the sherpa-onnx
export, but it lacks the metadata (sample rate, voices, style shape) that
sherpa-onnx reads. This copies that metadata over. A local fp16 conversion
with onnxconverter-common did not load (Cast and MatMul type mismatches).
"""
import sys

import onnx

sherpa = onnx.load(sys.argv[1], load_external_data=False)
m = onnx.load(sys.argv[2])
del m.metadata_props[:]
m.metadata_props.extend(sherpa.metadata_props)
onnx.save(m, sys.argv[3])
