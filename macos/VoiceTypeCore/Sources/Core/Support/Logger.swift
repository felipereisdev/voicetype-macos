import Foundation
import os

/// Thin wrapper around `os.Logger` so `Core` keeps a single log subsystem.
public enum CoreLog {
    public static let stateMachine = Logger(subsystem: "dev.voicetype.core", category: "state-machine")
    public static let configStore = Logger(subsystem: "dev.voicetype.core", category: "config-store")
}
