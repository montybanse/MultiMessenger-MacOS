import Foundation

// App-Extensions starten nicht über eine normale main(), sondern über die
// von Foundation bereitgestellte NSExtensionMain()-Laufschleife. Diese ist in
// Swift nicht öffentlich deklariert, existiert aber im System – daher per
// @_silgen_name eingebunden.
@_silgen_name("NSExtensionMain")
func NSExtensionMain() -> Int32

_ = NSExtensionMain()
