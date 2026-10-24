import DTHubPluginKit
import Foundation

/// La richiesta al PUP ufficiale per un testo-in-immagine con riquadri, come la compone `flux3/pup.py` di BFL (`bbox.upsampling_input`
/// senza scaffold: non ci sono immagini): le righe sono annotazioni «bloccate» che il modello non deve cambiare.
enum F3PupRequest {
  /// La decodifica di BFL: greedy, top-p 0,95, top-k 20, penalità di presenza 1,5 per il testo-in-immagine, 3584 token, senza thinking.
  static let options = DTHubLLMOptions(
    temperature: 0, topP: 0.95, topK: 20, presencePenalty: 1.5, maxTokens: 3584, thinking: false, timeout: 600)

  static func message(prose: String, locked: [PupRow], reminder: String? = nil) -> String {
    var text =
      "ORIGINAL PROMPT:\n\(prose.trimmingCharacters(in: .whitespacesAndNewlines))\n\n"
      + "LOCKED BOUNDING-BOX ANNOTATIONS ([y_min, x_min, y_max, x_max] on a 0-1000 canvas, with (0, 0) at the top-left). "
      + "This is an authoritative JSON list of dictionaries; preserve every supplied identity, provenance value, null, and coordinate exactly:\n"
      + PupRecord.json(locked)
    if let reminder { text += "\n" + reminder }
    return text
  }
}
