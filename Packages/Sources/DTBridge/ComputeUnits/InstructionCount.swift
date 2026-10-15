// Ported from Draw Things (GPL-3.0): Libraries/SwiftDiffusion/Sources/Models/InstructionCount/InstructionCount.swift
// at drawthingsai/draw-things-community commit 3338389349ad7771e1b626e60913bf8c4fff3a26. Logic unchanged; only the
// visibility was lowered to the module's. Counts the instructions of a model's forward pass for the CU estimate.

import Foundation

@inline(__always)
func DenseInstructionCount(rows: Int, input: Int, output: Int) -> Int {
  precondition(rows >= 0 && input >= 0 && output >= 0)
  return rows * output * input  // M * N * K (FMA)
}

@inline(__always)
func ScaledDotProductAttentionInstructionCount(
  batchSize: Int, heads: Int, headDimension: Int, sequenceDimensionA: Int, sequenceDimensionB: Int
) -> Int {
  precondition(
    batchSize >= 0 && heads >= 0 && headDimension >= 0 && sequenceDimensionA >= 0
      && sequenceDimensionB >= 0)
  return batchSize * heads * (2 * headDimension + 5) * sequenceDimensionA * sequenceDimensionB
}

@inline(__always)
func ConvolutionInstructionCount(
  batchSize: Int, outHeight: Int, outWidth: Int, outChannels: Int, kernelHeight: Int,
  kernelWidth: Int, inputChannels: Int, groups: Int = 1
) -> Int {
  precondition(
    batchSize >= 0 && outHeight >= 0 && outWidth >= 0 && outChannels >= 0 && kernelHeight >= 0
      && kernelWidth >= 0 && inputChannels >= 0 && groups > 0)
  precondition(inputChannels % groups == 0)
  let kernelK = kernelHeight * kernelWidth * (inputChannels / groups)
  let outputElements = batchSize * outHeight * outWidth * outChannels
  return outputElements * kernelK
}
