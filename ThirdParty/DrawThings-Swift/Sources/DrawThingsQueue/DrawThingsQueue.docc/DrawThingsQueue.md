# ``DrawThingsQueue``

Run many Draw Things generations one after another.

## Overview

A ``GenerationQueue`` takes `GenerationRequest`s and runs them in order on a `DrawThingsService`.
Jobs can be reordered, paused, cancelled and retried, and pending jobs can be saved so they
survive a relaunch.

```swift
import DrawThingsClient
import DrawThingsQueue

let queue = GenerationQueue(
    service: try DrawThingsService(address: "localhost:7859"),
    storage: QueueStorage()
)
try await queue.restore()

queue.enqueue(GenerationRequest(prompt: "A lighthouse at sunset", configuration: config))

for await result in queue.results {
    save(result.images)
}
```

The queue is `@Observable`, so SwiftUI views that read ``GenerationQueue/pending``,
``GenerationQueue/current``, ``GenerationQueue/finished``, ``GenerationQueue/progress`` or
``GenerationQueue/preview`` update as jobs move. The library contains no views:

```swift
struct QueueList: View {
    let queue: GenerationQueue

    var body: some View {
        List {
            if let job = queue.current {
                ProgressView(value: queue.progress?.fractionCompleted ?? 0) { Text(job.name) }
            }
            ForEach(queue.pending) { job in
                Text(job.name)
            }
            .onMove { queue.movePending(fromOffsets: $0, toOffset: $1) }
        }
    }
}
```

### Lost connections

When the server can't be reached, the running job goes back to the front of the queue and the
queue pauses with a ``GenerationQueue/pauseReason``. Other failures mark the job failed; retry it
with ``GenerationQueue/retry(_:)``.

### Saved queues

``QueueStorage`` saves pending jobs, including their input images, masks and hints. Its default
location is the one DrawThingsQueue 0.x used, and it reads 0.x files, whose jobs come back without
input images or hints (0.x didn't save them).

## Topics

### Queue

- ``GenerationQueue``
- ``QueueJob``
- ``QueueEvent``

### Saving

- ``QueueStorage``
