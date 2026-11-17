import Foundation
import HubKit
import Testing

@testable import HubCore

/// The stack of Turbo LoRA activations: applies the Turbo values to the parameters and restores them.
struct TurboLoRAsTests {
  private func start() -> GenerationParameters {
    var parameters = GenerationParameters()
    parameters.steps = 20
    parameters.guidanceScale = 4
    parameters.shift = 3
    return parameters
  }

  @Test func activateSetsTheGivenValuesAndKeepsTheOthers() {
    var parameters = start()
    var stack = TurboLoRAs()
    stack.activate(file: "a", values: TurboValues(steps: 4, guidance: nil, shift: 2), in: &parameters)
    #expect(parameters.steps == 4)
    #expect(parameters.guidanceScale == 4)
    #expect(parameters.shift == 2)
    #expect(stack.files == ["a"])
    #expect(stack.applied(for: "a") == TurboValues(steps: 4, guidance: nil, shift: 2))
  }

  @Test func valuesAreBroughtIntoRange() {
    var parameters = start()
    var stack = TurboLoRAs()
    stack.activate(file: "a", values: TurboValues(steps: 999, guidance: -3, shift: 99), in: &parameters)
    #expect(parameters.steps == 150)
    #expect(parameters.guidanceScale == 0)
    #expect(parameters.shift == 20)
    #expect(stack.applied(for: "a") == TurboValues(steps: 150, guidance: 0, shift: 20))
  }

  @Test func emptyValuesDoNothing() {
    var parameters = start()
    var stack = TurboLoRAs()
    stack.activate(file: "a", values: TurboValues(), in: &parameters)
    #expect(parameters == start())
    #expect(stack.files.isEmpty)
  }

  @Test func deactivateRestoresUntouchedValues() {
    var parameters = start()
    var stack = TurboLoRAs()
    stack.activate(file: "a", values: TurboValues(steps: 4, guidance: 1, shift: 2), in: &parameters)
    stack.deactivate(file: "a", in: &parameters)
    #expect(parameters == start())
    #expect(stack.files.isEmpty)
  }

  @Test func deactivateKeepsAValueTheUserChanged() {
    var parameters = start()
    var stack = TurboLoRAs()
    stack.activate(file: "a", values: TurboValues(steps: 4, guidance: 1, shift: nil), in: &parameters)
    parameters.steps = 10
    stack.deactivate(file: "a", in: &parameters)
    #expect(parameters.steps == 10)
    #expect(parameters.guidanceScale == 4)
    #expect(parameters.shift == 3)
  }

  @Test func activatingTheSameFileTwiceKeepsTheFirstSnapshot() {
    var parameters = start()
    var stack = TurboLoRAs()
    stack.activate(file: "a", values: TurboValues(steps: 4), in: &parameters)
    stack.activate(file: "a", values: TurboValues(steps: 6), in: &parameters)
    #expect(parameters.steps == 4)
    #expect(stack.files == ["a"])
    stack.deactivate(file: "a", in: &parameters)
    #expect(parameters.steps == 20)
  }

  @Test func twoTurbosRemovedInOrderRestoreStepByStep() {
    var parameters = start()
    var stack = TurboLoRAs()
    stack.activate(file: "a", values: TurboValues(steps: 8, guidance: 2), in: &parameters)
    stack.activate(file: "b", values: TurboValues(steps: 4, guidance: 1), in: &parameters)
    stack.deactivate(file: "b", in: &parameters)
    #expect(parameters.steps == 8)
    #expect(parameters.guidanceScale == 2)
    stack.deactivate(file: "a", in: &parameters)
    #expect(parameters == start())
  }

  @Test func twoTurbosRemovedOutOfOrder() {
    var parameters = start()
    var stack = TurboLoRAs()
    stack.activate(file: "a", values: TurboValues(steps: 8, guidance: 2), in: &parameters)
    stack.activate(file: "b", values: TurboValues(steps: 4, guidance: 1), in: &parameters)
    stack.deactivate(file: "a", in: &parameters)
    #expect(parameters.steps == 4)
    #expect(parameters.guidanceScale == 1)
    #expect(stack.files == ["b"])
    stack.deactivate(file: "b", in: &parameters)
    #expect(parameters == start())
  }

  @Test func pruneDropsActivationsOfFilesNoLongerPresent() {
    var parameters = start()
    var stack = TurboLoRAs()
    stack.activate(file: "a", values: TurboValues(steps: 8), in: &parameters)
    stack.activate(file: "b", values: TurboValues(steps: 4), in: &parameters)
    stack.prune(keeping: ["b"])
    #expect(stack.files == ["b"])
    #expect(parameters.steps == 4)
  }

  @Test func deactivatingAnUnknownFileDoesNothing() {
    var parameters = start()
    var stack = TurboLoRAs()
    stack.activate(file: "a", values: TurboValues(steps: 8), in: &parameters)
    let before = parameters
    stack.deactivate(file: "zzz", in: &parameters)
    #expect(parameters == before)
    #expect(stack.files == ["a"])
  }

  @Test func outOfOrderRemovalRestoresAParameterTheUpperTurboDoesNotOwn() {
    var parameters = start()
    var stack = TurboLoRAs()
    stack.activate(file: "a", values: TurboValues(steps: 8, guidance: 2), in: &parameters)
    stack.activate(file: "b", values: TurboValues(steps: 4), in: &parameters)
    stack.deactivate(file: "a", in: &parameters)
    #expect(parameters.steps == 4)
    #expect(parameters.guidanceScale == 2)
    stack.deactivate(file: "b", in: &parameters)
    #expect(parameters == start())
  }

  @Test func outOfOrderRemovalKeepsAValueTheUserChangedAfterwards() {
    var parameters = start()
    var stack = TurboLoRAs()
    stack.activate(file: "a", values: TurboValues(steps: 8, guidance: 2), in: &parameters)
    stack.activate(file: "b", values: TurboValues(steps: 4), in: &parameters)
    parameters.steps = 10
    stack.deactivate(file: "a", in: &parameters)
    stack.deactivate(file: "b", in: &parameters)
    #expect(parameters.steps == 10)
    #expect(parameters.guidanceScale == 4)
  }

  @Test func infiniteValuesAreClampedAndNaNIsIgnored() {
    var parameters = start()
    var stack = TurboLoRAs()
    stack.activate(
      file: "a", values: TurboValues(steps: nil, guidance: .infinity, shift: -.infinity), in: &parameters)
    #expect(parameters.guidanceScale == 50)
    #expect(parameters.shift == 0)
    stack.activate(file: "n", values: TurboValues(steps: nil, guidance: .nan, shift: nil), in: &parameters)
    #expect(stack.files == ["a"])
    #expect(parameters.guidanceScale == 50)
  }

  @Test func stillAppliedListsOnlyValuesThatStillMatch() {
    var parameters = start()
    parameters.loras = [LoRASelection(file: "a")]
    var stack = TurboLoRAs()
    stack.activate(file: "a", values: TurboValues(steps: 8, guidance: 1, shift: 2), in: &parameters)
    #expect(stack.stillApplied(for: "a", in: parameters) == TurboValues(steps: 8, guidance: 1, shift: 2))
    parameters.steps = 30
    #expect(stack.stillApplied(for: "a", in: parameters) == TurboValues(steps: nil, guidance: 1, shift: 2))
    parameters.guidanceScale = 5
    parameters.shift = 9
    #expect(stack.stillApplied(for: "a", in: parameters) == nil)
  }

  @Test func stillAppliedIsNilWhenTheFileIsNotChosenOrNotInTheStack() {
    var parameters = start()
    parameters.loras = [LoRASelection(file: "a")]
    var stack = TurboLoRAs()
    stack.activate(file: "a", values: TurboValues(steps: 8), in: &parameters)
    #expect(stack.stillApplied(for: "b", in: parameters) == nil)
    parameters.loras = []
    #expect(stack.stillApplied(for: "a", in: parameters) == nil)
  }
}
