// Ported from Draw Things (GPL-3.0): Libraries/SwiftDiffusion/Sources/Models/InstructionCount/ErnieImageInstructionCount.swift
// at drawthingsai/draw-things-community commit 3338389349ad7771e1b626e60913bf8c4fff3a26. Logic unchanged; only the
// visibility was lowered to the module's. Counts the instructions of a model's forward pass for the CU estimate.

import Foundation

private func ErnieImageTransformerBlockInstructionCount(
  batchSize: Int, sequenceLength: Int, channels: Int = 4_096, intermediateSize: Int = 12_288
) -> Int {
  let rows = batchSize * sequenceLength
  var total = 0

  total += 4 * DenseInstructionCount(rows: rows, input: channels, output: channels)
  total += 2 * DenseInstructionCount(rows: rows, input: channels, output: intermediateSize)
  total += DenseInstructionCount(rows: rows, input: intermediateSize, output: channels)
  total += ScaledDotProductAttentionInstructionCount(
    batchSize: batchSize, heads: channels / 128, headDimension: 128,
    sequenceDimensionA: sequenceLength, sequenceDimensionB: sequenceLength)

  return total
}

func ErnieImageInstructionCount(
  batchSize: Int, height: Int, width: Int, textLength: Int, channels: Int = 4_096,
  layers: Int = 36, intermediateSize: Int = 12_288
) -> Int {
  precondition(height % 2 == 0 && width % 2 == 0)
  precondition(channels % 128 == 0)
  let patchHeight = height / 2
  let patchWidth = width / 2
  let imageLength = patchHeight * patchWidth
  let totalLength = imageLength + textLength
  var total = 0

  total += ConvolutionInstructionCount(
    batchSize: batchSize, outHeight: patchHeight, outWidth: patchWidth, outChannels: channels,
    kernelHeight: 1, kernelWidth: 1, inputChannels: 128)

  total += 10 * DenseInstructionCount(rows: batchSize, input: channels, output: channels)

  for _ in 0..<layers {
    total += ErnieImageTransformerBlockInstructionCount(
      batchSize: batchSize, sequenceLength: totalLength, channels: channels,
      intermediateSize: intermediateSize)
  }

  total += DenseInstructionCount(rows: batchSize * imageLength, input: channels, output: 128)
  return total
}

func ErnieImageFixedInstructionCount(
  batchSize: Int, textLength: Int, textInputChannels: Int = 3_072, channels: Int = 4_096
) -> Int {
  DenseInstructionCount(rows: batchSize * textLength, input: textInputChannels, output: channels)
}
