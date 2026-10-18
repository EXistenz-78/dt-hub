import Foundation

/// The words of the plug-in, in Italian and English. A plug-in bundle holds only its library, so there are no
/// `.strings` files: the table is here.
enum L {
  enum Key: CaseIterable {
    case dropHere, open, image, enlargement, overlap, loraStrength
    case prepare, prepared, finalSize, tiles, passes, croppedNote
    case unsupportedModel, tooBig, bigJob, notAnswered, unreadableImage, noFolder
    case addedToResults, resultNotAdded, resultDescription, useAsStart, stopped, failed, closed, resultPlaceholder, tileRegenerated, tilesDone
  }

  static var systemIsItalian: Bool {
    Locale.preferredLanguages.first?.hasPrefix("it") ?? false
  }

  static func text(_ key: Key, italian: Bool = systemIsItalian) -> String {
    (italian ? it : en)[key] ?? en[key] ?? "\(key)"
  }

  /// Whether the word is in the table of that language (the tests check both are complete).
  static func isDefined(_ key: Key, italian: Bool) -> Bool {
    (italian ? it : en)[key] != nil
  }

  static func format(_ key: Key, _ args: CVarArg..., italian: Bool = systemIsItalian) -> String {
    String(format: text(key, italian: italian), arguments: args)
  }

  private static let en: [Key: String] = [
    .dropHere: "Drop an image here", .open: "Open…", .image: "Image", .enlargement: "Enlargement",
    .overlap: "Overlap between tiles", .loraStrength: "LoRA strength",
    .prepare: "Prepare", .prepared: "Ready: press RUN in DT Hub.",
    .finalSize: "Final size: %d × %d px", .tiles: "%d × %d tiles", .passes: "%d passes",
    .croppedNote: "The picture is cut by a few pixels so its sides are multiples of 64.",
    .unsupportedModel: "This model has no preset in the plug-in yet: choose FLUX.2 [klein] 9B.",
    .tooBig: "Too big: the result would pass 16 384 px on a side or 268 megapixels.",
    .bigJob: "A big job: it takes many passes. Press Prepare again to confirm.",
    .notAnswered: "No answer from the app.", .unreadableImage: "This image could not be read.",
    .noFolder: "No picture folder yet: switch the plug-in on first.",
    .addedToResults: "Done. The enlarged picture is in the Results.", .resultNotAdded: "The picture could not be added to the Results: %@",
    .resultDescription: "Tiled Upscale %d× · %d×%d tiles · LoRA %.2f",
    .useAsStart: "Use as start image", .stopped: "Stopped. Nothing was saved.",
    .failed: "The enlargement failed: %@", .closed: "The enlargement was closed.",
    .resultPlaceholder: "The enlarged picture goes to the Results when it is done.",
    .tileRegenerated: "Each tile is regenerated with the LoRA, with the join kept by a mask.",
    .tilesDone: "%d of %d tiles done",
  ]

  private static let it: [Key: String] = [
    .dropHere: "Trascina qui un'immagine", .open: "Apri…", .image: "Immagine", .enlargement: "Ingrandimento",
    .overlap: "Sovrapposizione dei tile", .loraStrength: "Forza del LoRA",
    .prepare: "Prepara", .prepared: "Pronto: premi RUN in DT Hub.",
    .finalSize: "Dimensione finale: %d × %d px", .tiles: "%d × %d tile", .passes: "%d passi",
    .croppedNote: "L'immagine viene ritagliata di pochi pixel perché i lati siano multipli di 64.",
    .unsupportedModel: "Questo modello non ha ancora un preset nel plug-in: scegli FLUX.2 [klein] 9B.",
    .tooBig: "Troppo grande: il risultato supererebbe 16 384 px per lato o 268 megapixel.",
    .bigJob: "Un lavoro grande: richiede molti passi. Premi di nuovo Prepara per confermare.",
    .notAnswered: "Nessuna risposta dall'app.", .unreadableImage: "Impossibile leggere questa immagine.",
    .noFolder: "Ancora nessuna cartella per le immagini: accendi prima il plug-in.",
    .addedToResults: "Fatto. L'immagine ingrandita è nei Risultati.", .resultNotAdded: "Impossibile aggiungere l'immagine ai Risultati: %@",
    .resultDescription: "Tiled Upscale %d× · %d×%d tile · LoRA %.2f",
    .useAsStart: "Usa come immagine di partenza", .stopped: "Fermato. Non è stato salvato nulla.",
    .failed: "L'ingrandimento non è riuscito: %@", .closed: "L'ingrandimento è stato chiuso.",
    .resultPlaceholder: "L'immagine ingrandita va nei Risultati a lavoro finito.",
    .tileRegenerated: "Ogni tile viene rigenerato con il LoRA, e una maschera mantiene la giunzione.",
    .tilesDone: "%d di %d tile completati",
  ]
}
