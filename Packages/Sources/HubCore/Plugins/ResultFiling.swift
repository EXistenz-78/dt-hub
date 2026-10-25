/// Under which model a result a plug-in sends is filed in the Results strip.
public enum ResultFiling {
  /// The model of the guided pipeline that is running, else the one chosen in the header; nil when neither is there.
  public static func model(guided: String?, header: String?) -> String? {
    if let guided, !guided.isEmpty { return guided }
    if let header, !header.isEmpty { return header }
    return nil
  }
}
