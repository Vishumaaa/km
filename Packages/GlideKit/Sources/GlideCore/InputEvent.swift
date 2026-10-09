/// Everything the phone can ask the Mac to do.
public enum InputEvent: Equatable {
    /// Relative pointer movement in whole Mac points (already accelerated on the phone).
    case move(dx: Int16, dy: Int16)
    case button(MouseButton, down: Bool)
    /// For `.began`/`.changed`: dx/dy are scroll distance in points (finger direction).
    /// For `.ended`: dx/dy are the release velocity in points/second (drives momentum).
    case scroll(dx: Float, dy: Float, phase: ScrollPhase)
    case action(SystemAction)
}

public enum MouseButton: UInt8, Equatable {
    case left = 0
    case right = 1
}

public enum ScrollPhase: UInt8, Equatable {
    case began = 0
    case changed = 1
    case ended = 2
}

/// Multi-finger swipes are mapped to the stock macOS keyboard shortcuts.
public enum SystemAction: UInt8, Equatable {
    case missionControl = 0
    case appExpose = 1
    case spaceLeft = 2
    case spaceRight = 3
}
