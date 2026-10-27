import SwiftUI

/// Avec le SDK macOS 27, `@State` est une macro dont le plugin n'est fourni qu'avec Xcode.
/// Cet alias pointe vers le property wrapper `State` lui-même, ce qui permet de compiler
/// avec les seuls Command Line Tools.
typealias ViewState = SwiftUI.State
