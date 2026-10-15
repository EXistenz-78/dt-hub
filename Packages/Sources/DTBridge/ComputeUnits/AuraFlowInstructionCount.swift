// Ported from Draw Things (GPL-3.0): Libraries/SwiftDiffusion/Sources/Models/InstructionCount/AuraFlowInstructionCount.swift
// at drawthingsai/draw-things-community commit 3338389349ad7771e1b626e60913bf8c4fff3a26. Logic unchanged; only the
// visibility was lowered to the module's. Counts the instructions of a model's forward pass for the CU estimate.

import Foundation

// Counts only Dense (GEMM), SDPA-equivalent attention, and Convolution instructions.
func AuraFlowInstructionCount(
  batchSize: Int, tokenLength: Int, height: Int, width: Int, channels: Int, layers: (Int, Int)
) -> Int {
  precondition(height % 2 == 0 && width % 2 == 0)
  precondition(channels % 256 == 0)

  let h = height / 2
  let w = width / 2
  let imageLength = h * w
  let contextLength = tokenLength + 8
  let totalLength = contextLength + imageLength
  let heads = channels / 256
  let headDimension = 256
  let ffnIntermediate = channels * 8 / 3
  let rowsImage = batchSize * imageLength
  let rowsContext = batchSize * contextLength
  let rowsTotal = batchSize * totalLength
  var total = 0

  // x_embedder patchify conv: 4 -> channels.
  total += ConvolutionInstructionCount(
    batchSize: batchSize, outHeight: h, outWidth: w, outChannels: channels, kernelHeight: 2,
    kernelWidth: 2, inputChannels: 4)

  for _ in 0..<layers.0 {
    // Joint attention qkv on context + x streams, then separate output projections.
    total += 3 * DenseInstructionCount(rows: rowsContext, input: channels, output: channels)
    total += 3 * DenseInstructionCount(rows: rowsImage, input: channels, output: channels)
    total += ScaledDotProductAttentionInstructionCount(
      batchSize: batchSize, heads: heads, headDimension: headDimension,
      sequenceDimensionA: totalLength,
      sequenceDimensionB: totalLength)
    total += DenseInstructionCount(rows: rowsContext, input: channels, output: channels)  // c_o
    total += DenseInstructionCount(rows: rowsImage, input: channels, output: channels)  // x_o

    // GEGLU FFNs (two up projections + one down) on both streams.
    total += DenseInstructionCount(rows: rowsContext, input: channels, output: ffnIntermediate)
    total += DenseInstructionCount(rows: rowsContext, input: channels, output: ffnIntermediate)
    total += DenseInstructionCount(rows: rowsContext, input: ffnIntermediate, output: channels)
    total += DenseInstructionCount(rows: rowsImage, input: channels, output: ffnIntermediate)
    total += DenseInstructionCount(rows: rowsImage, input: channels, output: ffnIntermediate)
    total += DenseInstructionCount(rows: rowsImage, input: ffnIntermediate, output: channels)
  }

  for i in 0..<layers.1 {
    let contextBlockPreOnly = (i == layers.1 - 1)
    let rowsOut = contextBlockPreOnly ? rowsImage : rowsTotal

    // Single self-attention on concatenated context+x sequence.
    total += 3 * DenseInstructionCount(rows: rowsTotal, input: channels, output: channels)
    total += ScaledDotProductAttentionInstructionCount(
      batchSize: batchSize, heads: heads, headDimension: headDimension,
      sequenceDimensionA: totalLength,
      sequenceDimensionB: totalLength)
    total += DenseInstructionCount(rows: rowsOut, input: channels, output: channels)  // x_o

    // GEGLU FFN on surviving query tokens.
    total += DenseInstructionCount(rows: rowsOut, input: channels, output: ffnIntermediate)
    total += DenseInstructionCount(rows: rowsOut, input: channels, output: ffnIntermediate)
    total += DenseInstructionCount(rows: rowsOut, input: ffnIntermediate, output: channels)
  }

  total += DenseInstructionCount(rows: rowsImage, input: channels, output: 2 * 2 * 4)
  return total
}

// Extra params are needed because `AuraFlowFixed(...)` does not carry the text token count
// or text feature width, but the context embedder GEMM depends on them.
func AuraFlowFixedInstructionCount(
  batchSize: (Int, Int), tokenLength: Int, channels: Int, layers: (Int, Int),
  contextInputChannels: Int = 4096
) -> Int {
  let rowsContext = batchSize.0 * tokenLength
  let rowsTime = batchSize.1
  var total = 0

  // t_embedder MLP.
  total += DenseInstructionCount(rows: rowsTime, input: 256, output: channels)
  total += DenseInstructionCount(rows: rowsTime, input: channels, output: channels)

  // cond_seq_linear / context_embedder.
  total += DenseInstructionCount(rows: rowsContext, input: contextInputChannels, output: channels)

  // Per-layer adaLN projections emitted by fixed path.
  total += layers.0 * 12 * DenseInstructionCount(rows: rowsTime, input: channels, output: channels)
  total += layers.1 * 6 * DenseInstructionCount(rows: rowsTime, input: channels, output: channels)

  // Final shift + scale.
  total += 2 * DenseInstructionCount(rows: rowsTime, input: channels, output: channels)

  return total
}
