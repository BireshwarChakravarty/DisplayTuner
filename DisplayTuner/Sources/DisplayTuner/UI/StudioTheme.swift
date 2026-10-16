import SwiftUI

// Explicit property-wrapper alias also supports SDKs that add a State macro.
typealias ViewState<Value> = SwiftUI.State<Value>
