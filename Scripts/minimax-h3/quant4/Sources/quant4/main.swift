import Foundation
import NNC

// Re-quantizes Draw Things' Qwen3-VL 32B text encoder (row-wise 8-bit) to 4-bit (Q4_K) row-wise matrices.
// Token embeddings and the vision tower stay FP16, vectors are compressed (ezm7), as in the 8-bit file.
// usage: quant4 <input.ckpt> <output.ckpt>   (resumes: tensors already in the output are kept)
setvbuf(stdout, nil, _IOLBF, 0)
func say(_ text: String) { print(text) }
let arguments = CommandLine.arguments
guard arguments.count == 3 else {
  print("usage: quant4 <input.ckpt> <output.ckpt>")
  exit(2)
}
let input = arguments[1]
let output = arguments[2]
let graph = DynamicGraph()
let started = Date()
var matrices = 0
var kept = 0
graph.openStore(input, flags: .readOnly, externalStore: input + "-tensordata") { store in
  let keys = store.keys
  say("input has \(keys.count) tensors")
  graph.openStore(output) { out in
    let written = Set(out.keys)
    for (index, key) in keys.enumerated() {
      if written.contains(key) {
        kept += 1
        continue
      }
      guard let tensor = store.read(key, codec: [.q8p, .q6p, .q4p, .i8x, .ezm7, .externalData]) else {
        say("cannot read \(key)")
        exit(1)
      }
      if tensor.dataType == .Float32 {
        out.write(key, tensor: tensor)
        continue
      }
      let fp16 = Tensor<Float16>(from: tensor)
      let isMatrix = fp16.shape.filter { $0 > 1 }.count > 1
      if key.contains("tok_embeddings") || key.hasPrefix("__vision_model__") {
        out.write(key, tensor: fp16)
      } else if isMatrix {
        out.write(key, tensor: fp16, codec: [.i8x(.q4k), .ezm7])
        matrices += 1
      } else {
        out.write(key, tensor: fp16, codec: .ezm7)
      }
      if (index + 1) % 25 == 0 {
        let seconds = Date().timeIntervalSince(started)
        say("\(index + 1)/\(keys.count) tensors, \(matrices) matrices, \(Int(seconds)) s")
      }
    }
  }
}
print("done: \(matrices) matrices quantized, \(kept) kept from a previous run, \(Int(Date().timeIntervalSince(started))) s")
