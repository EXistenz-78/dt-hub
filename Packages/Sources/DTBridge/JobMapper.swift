import DrawThingsClient
import HubKit

/// Translates DT Hub's `GenerationJob` and the library's events (spec §5).
enum JobMapper {
  static func request(for job: GenerationJob) -> GenerationRequest {
    let parameters = job.parameters.clamped()
    let configuration = DrawThingsConfiguration(
      width: Int32(parameters.width),
      height: Int32(parameters.height),
      steps: Int32(parameters.steps),
      model: job.model,
      sampler: SamplerType(rawValue: Int8(parameters.sampler.rawValue)) ?? .unipctrailing,
      guidanceScale: Float(parameters.guidanceScale),
      seed: parameters.seed,
      shift: Float(parameters.shift),
      batchCount: Int32(parameters.batchCount),
      batchSize: Int32(parameters.batchSize),
      cfgZeroStar: parameters.cfgZeroStar,
      cfgZeroInitSteps: Int32(parameters.cfgZeroInitSteps),
      resolutionDependentShift: parameters.resolutionDependentShift)
    return GenerationRequest(prompt: job.prompt, configuration: configuration)
  }

  /// The update for a library event; nil for events DT Hub does not show (audio, downloads,
  /// single images: the batch's full list arrives with `.completed`).
  static func update(for event: GenerationEvent) throws -> GenerationUpdate? {
    switch event {
    case .progress(let progress):
      switch progress.stage {
      case .sampling(let step), .secondPassSampling(let step):
        return .progress(step: step, totalSteps: progress.totalSteps)
      default:
        break
      }
      return .progress(step: nil, totalSteps: progress.totalSteps)
    case .preview(let image):
      return .preview(image)
    case .completed(let result):
      guard !result.images.isEmpty else { throw BackendError.noImages }
      return .finished(result.images)
    case .image, .audio, .remoteDownload:
      return nil
    }
  }

  /// A library error as DT Hub reports it; cancellation passes through unchanged.
  static func backendError(for error: any Error) -> any Error {
    if error is CancellationError || error is BackendError { return error }
    if case DrawThingsError.connectionFailed(let detail) = error { return BackendError.unreachable(detail) }
    if case DrawThingsError.unauthenticated = error { return BackendError.unauthorized }
    // The library reports a RUN that ends without images (e.g. #131) this way.
    if case DrawThingsError.incompleteResponse(let detail) = error, detail.contains("without returning an image") {
      return BackendError.noImages
    }
    return BackendError.generationFailed(error.localizedDescription)
  }
}
