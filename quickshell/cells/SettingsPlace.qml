pragma Singleton

import QtQuick
import Quickshell

// Where somebody was in the settings, for the length of the session.
//
// Not on the cell: there is one settings cell per place it is configured, and
// another for each screen it is invoked on, and a membrane rebuilt by a preset
// rebuilds the cell with it. Somebody adjusting a margin closes the panel to
// look at the result and reopens it from wherever their hand is — the keybind
// on another screen as often as the mark they pressed — and expects to find
// the page they left.
Singleton {
    // Empty until a category is chosen: the first in the column, then.
    property string category: ""
}
