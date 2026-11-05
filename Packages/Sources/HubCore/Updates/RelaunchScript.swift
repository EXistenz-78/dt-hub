import Foundation

/// The shell script that opens DT Hub again after it quits (an installed update or a plug-in change takes effect at the
/// next launch). It waits for the old instance to be gone instead of for a fixed time: the app needs several seconds to
/// quit when it stops the Draw Things server, and a new instance started meanwhile would run beside the old one. An old
/// instance that has not quit after `grace` seconds is asked to (SIGTERM) and, if that is not enough, killed.
public enum RelaunchScript {
  public static let source = """
    pid="$1"; app="$2"; opener="$3"; grace="$4"
    waited=0
    while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt $((grace * 5)) ]; do sleep 0.2; waited=$((waited + 1)); done
    if kill -0 "$pid" 2>/dev/null; then
      kill -TERM "$pid" 2>/dev/null
      waited=0
      while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 25 ]; do sleep 0.2; waited=$((waited + 1)); done
    fi
    if kill -0 "$pid" 2>/dev/null; then kill -KILL "$pid" 2>/dev/null; sleep 0.5; fi
    "$opener" "$app"
    """

  /// The arguments of `/bin/sh` that run the script for the instance `pid`, then open the app at `appPath`.
  public static func arguments(
    pid: Int32, appPath: String, openCommand: String = "/usr/bin/open", grace: Int = 15
  ) -> [String] {
    ["-c", source, "dthub-relaunch", String(pid), appPath, openCommand, String(grace)]
  }
}
