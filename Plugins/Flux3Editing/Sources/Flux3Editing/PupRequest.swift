import DTHubPluginKit
import Foundation

/// La richiesta al PUP ufficiale, come la compone `flux3/pup.py` di BFL per le modifiche con riquadri (`I2I_SCAFFOLD[True]` e
/// `bbox.upsampling_input`): le righe stanno nel testo come annotazioni «bloccate» che il modello non deve cambiare.
enum PupRequest {
  /// La decodifica di BFL: greedy, top-p 0,95, top-k 20, nessuna penalità per le modifiche, fino a 3584 token, senza thinking.
  static let options = DTHubLLMOptions(
    temperature: 0, topP: 0.95, topK: 20, presencePenalty: 0, maxTokens: 3584, thinking: false, timeout: 600)

  static func message(prose: String, locked: [PupRow], reminder: String? = nil) -> String {
    let instruction =
      "ORIGINAL PROMPT:\n\(prose.trimmingCharacters(in: .whitespacesAndNewlines))\n\n"
      + "LOCKED BOUNDING-BOX ANNOTATIONS ([y_min, x_min, y_max, x_max] on a 0-1000 canvas, with (0, 0) at the top-left). "
      + "This is an authoritative JSON list of dictionaries; preserve every supplied identity, provenance value, null, and coordinate exactly:\n"
      + PupRecord.json(locked)
    var text =
      "Reference images follow in attachment order: ref_image_0, ref_image_1, ...\nUser editing instruction: \(instruction)\n"
    if let reminder { text += reminder + "\n" }
    return text + "Decide the edit, imagine the target image, and output the annotation record."
  }
}
