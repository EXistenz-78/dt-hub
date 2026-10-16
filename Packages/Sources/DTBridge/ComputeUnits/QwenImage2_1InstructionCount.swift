// Ported from Draw Things (GPL-3.0): Libraries/SwiftDiffusion/Sources/Models/InstructionCount/QwenImage2_1InstructionCount.swift
// at drawthingsai/draw-things-community commit 3338389349ad7771e1b626e60913bf8c4fff3a26. Logic unchanged; only the
// visibility was lowered to the module's. Counts the instructions of a model's forward pass for the CU estimate.

import Foundation

func QwenImage2_1InstructionCount(
  batchSize: Int, height: Int, width: Int, prefixLength: Int
) -> Int {
  let count = height * width
  let rows = batchSize * count
  let width = 4096
  var total = DenseInstructionCount(rows: rows, input: 64, output: width)
  total +=
    32
    * (4 * DenseInstructionCount(rows: rows, input: width, output: width)
      + 3 * DenseInstructionCount(rows: rows, input: width, output: 12288)
      + ScaledDotProductAttentionInstructionCount(
        batchSize: batchSize, heads: 32,
        headDimension: 128, sequenceDimensionA: count, sequenceDimensionB: prefixLength + count))
  total += DenseInstructionCount(rows: rows, input: width, output: 64)
  return total
}

func QwenImage2_1FixedInstructionCount(
  batchSize: Int, timesteps: Int, segments: [(length: Int, image: Bool)]
) -> Int {
  let textLength = segments.filter { !$0.image }.reduce(0) { $0 + $1.length }
  let referenceLength = segments.filter { $0.image }.reduce(0) { $0 + $1.length }
  let rows = batchSize * (textLength + referenceLength)
  let width = 4096
  var total = 2 * DenseInstructionCount(rows: batchSize * textLength, input: width, output: width)
  total += DenseInstructionCount(rows: batchSize * referenceLength, input: 64, output: width)
  total += DenseInstructionCount(rows: batchSize * (timesteps + 1), input: 256, output: width)
  total += 6 * DenseInstructionCount(rows: batchSize * (timesteps + 1), input: width, output: width)
  var end = 0
  var attention = 0
  for segment in segments {
    end += segment.length
    attention += ScaledDotProductAttentionInstructionCount(
      batchSize: batchSize, heads: 32,
      headDimension: 128, sequenceDimensionA: segment.length, sequenceDimensionB: end)
  }
  total +=
    31
    * (4 * DenseInstructionCount(rows: rows, input: width, output: width)
      + 3 * DenseInstructionCount(rows: rows, input: width, output: 12288) + attention)
  // The last prefix block only computes K and V.
  total += 2 * DenseInstructionCount(rows: rows, input: width, output: width)
  return total
}
