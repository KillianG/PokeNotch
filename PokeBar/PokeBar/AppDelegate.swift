import Cocoa
import ImageIO
import QuartzCore

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var floatingWindow: NSWindow!
    private var spriteLayer: CALayer!
    private var timer: Timer?
    private var intervalMinutes: Double = 5
    private let totalPokemon = 649
    private let spriteSize: CGFloat = 48
    private var currentFrenchName: String?
    private var nameLabel: NSTextField?
    private var nameLabelWindow: NSWindow?
    private var hoverTimer: Timer?
    private var mouseCheckTimer: Timer?
    private var isMouseInside = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Small menu bar item for controls
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.title = "�Pokemon"
            button.font = NSFont.systemFont(ofSize: 9)
        }
        buildMenu()

        // Big floating sprite window near the notch
        setupFloatingWindow()

        fetchRandomPokemon()
        startTimer()
    }

    // MARK: - Floating Window

    private func findNotchScreen() -> NSScreen? {
        if #available(macOS 12.0, *) {
            for screen in NSScreen.screens {
                if screen.safeAreaInsets.top > 0 {
                    return screen
                }
            }
        }
        return nil
    }

    private func setupFloatingWindow() {
        guard let screen = findNotchScreen() ?? NSScreen.main else { return }

        var xPos: CGFloat
        var yPos: CGFloat

        if #available(macOS 12.0, *), let topRight = screen.auxiliaryTopRightArea {
            xPos = screen.frame.origin.x + topRight.origin.x + 10
            yPos = screen.frame.origin.y + screen.frame.height - spriteSize
        } else {
            xPos = screen.frame.origin.x + (screen.frame.width - spriteSize) / 2
            yPos = screen.frame.origin.y + screen.frame.height - spriteSize
        }

        let frame = NSRect(x: xPos, y: yPos, width: spriteSize, height: spriteSize)

        floatingWindow = NSWindow(contentRect: frame,
                                  styleMask: .borderless,
                                  backing: .buffered,
                                  defer: false)
        floatingWindow.isOpaque = false
        floatingWindow.backgroundColor = .clear
        floatingWindow.level = .statusBar
        floatingWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        floatingWindow.ignoresMouseEvents = true
        floatingWindow.hasShadow = false

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: spriteSize, height: spriteSize))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = .clear

        spriteLayer = CALayer()
        spriteLayer.frame = CGRect(x: 0, y: 0, width: spriteSize, height: spriteSize)
        spriteLayer.contentsGravity = .resizeAspect
        spriteLayer.magnificationFilter = .nearest // Crisp pixel art!
        contentView.layer?.addSublayer(spriteLayer)

        floatingWindow.contentView = contentView
        floatingWindow.orderFrontRegardless()

        // Label as a child window of the floating window
        let labelWidth: CGFloat = 150
        let labelHeight: CGFloat = 18
        let labelX = xPos + (spriteSize - labelWidth) / 2
        let labelY = yPos - labelHeight - 2
        let labelWin = NSWindow(contentRect: NSRect(x: labelX, y: labelY, width: labelWidth, height: labelHeight),
                                styleMask: .borderless, backing: .buffered, defer: false)
        labelWin.isOpaque = false
        labelWin.backgroundColor = .clear
        labelWin.level = .statusBar
        labelWin.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        labelWin.ignoresMouseEvents = true
        labelWin.hasShadow = false

        let label = NSTextField(labelWithString: "")
        label.font = NSFont.boldSystemFont(ofSize: 11)
        label.textColor = .white
        label.backgroundColor = NSColor.black.withAlphaComponent(0.75)
        label.drawsBackground = true
        label.isBezeled = false
        label.isEditable = false
        label.alignment = .center
        label.wantsLayer = true
        label.layer?.cornerRadius = 4
        label.layer?.masksToBounds = true
        label.frame = NSRect(x: 0, y: 0, width: labelWidth, height: labelHeight)
        label.autoresizingMask = [.width, .height]
        labelWin.contentView = label
        nameLabel = label
        nameLabelWindow = labelWin

        // Add as child window so it inherits parent's display
        floatingWindow.addChildWindow(labelWin, ordered: .above)
        labelWin.orderOut(nil)

        startMouseMonitor()
    }

    // MARK: - Menu

    private func buildMenu() {
        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())

        let intervalItem = NSMenuItem(title: "Interval", action: nil, keyEquivalent: "")
        let intervalSubmenu = NSMenu()
        for minutes in [1, 2, 5, 10, 15, 30] {
            let item = NSMenuItem(title: "\(minutes) min", action: #selector(changeInterval(_:)), keyEquivalent: "")
            item.tag = minutes
            if Double(minutes) == intervalMinutes {
                item.state = .on
            }
            intervalSubmenu.addItem(item)
        }
        intervalItem.submenu = intervalSubmenu
        menu.addItem(intervalItem)

        menu.addItem(NSMenuItem.separator())

        let pokemonNameItem = NSMenuItem(title: "Loading...", action: nil, keyEquivalent: "")
        pokemonNameItem.tag = 999
        pokemonNameItem.isEnabled = false
        menu.addItem(pokemonNameItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit PokeBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func refreshNow() {
        fetchRandomPokemon()
    }

    @objc private func changeInterval(_ sender: NSMenuItem) {
        intervalMinutes = Double(sender.tag)
        if let submenu = sender.menu {
            for item in submenu.items { item.state = .off }
        }
        sender.state = .on
        startTimer()
    }

    // MARK: - Hover (polling timer, clicks pass through)

    private func startMouseMonitor() {
        let t = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.checkMousePosition()
        }
        RunLoop.main.add(t, forMode: .common)
        mouseCheckTimer = t
    }

    private func checkMousePosition() {
        let mouseLocation = NSEvent.mouseLocation
        let inside = floatingWindow.frame.contains(mouseLocation)

        if inside && !isMouseInside {
            isMouseInside = true
            startHoverTimer()
        } else if !inside && isMouseInside {
            isMouseInside = false
            cancelHover()
        }
    }

    private func startHoverTimer() {
        hoverTimer?.invalidate()
        let t = Timer(timeInterval: 3.0, repeats: false) { [weak self] _ in
            guard let self = self, let name = self.currentFrenchName else { return }
            self.nameLabel?.stringValue = name
            self.nameLabelWindow?.orderFront(nil)
        }
        RunLoop.main.add(t, forMode: .common)
        hoverTimer = t
    }

    private func cancelHover() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        nameLabelWindow?.orderOut(nil)
    }

    // MARK: - Timer

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: intervalMinutes * 60, repeats: true) { [weak self] _ in
            self?.fetchRandomPokemon()
        }
    }

    // MARK: - Fetch Pokémon

    private func fetchRandomPokemon() {
        let pokeId = Int.random(in: 1...totalPokemon)
        let spriteURL = URL(string: "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-v/black-white/animated/\(pokeId).gif")!
        let fallbackURL = URL(string: "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/\(pokeId).png")!
        let nameURL = URL(string: "https://pokeapi.co/api/v2/pokemon/\(pokeId)")!

        // Fetch name
        URLSession.shared.dataTask(with: nameURL) { [weak self] data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = json["name"] as? String else { return }
            DispatchQueue.main.async {
                if let menuItem = self?.statusItem.menu?.item(withTag: 999) {
                    menuItem.title = "#\(pokeId) \(name.capitalized)"
                }
            }
        }.resume()

        // Fetch French name from species endpoint
        let speciesURL = URL(string: "https://pokeapi.co/api/v2/pokemon-species/\(pokeId)")!
        URLSession.shared.dataTask(with: speciesURL) { [weak self] data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let names = json["names"] as? [[String: Any]] else { return }
            let frenchName = names.first { entry in
                if let lang = entry["language"] as? [String: Any],
                   let langName = lang["name"] as? String {
                    return langName == "fr"
                }
                return false
            }
            if let name = frenchName?["name"] as? String {
                DispatchQueue.main.async {
                    self?.currentFrenchName = name
                }
            }
        }.resume()

        // Fetch animated sprite (GIF), fall back to static PNG
        fetchData(from: spriteURL) { [weak self] data in
            if let data = data {
                self?.displayAnimatedSprite(data: data)
            } else {
                self?.fetchData(from: fallbackURL) { fallbackData in
                    if let fallbackData = fallbackData {
                        self?.displayAnimatedSprite(data: fallbackData)
                    }
                }
            }
        }
    }

    private func fetchData(from url: URL, completion: @escaping (Data?) -> Void) {
        URLSession.shared.dataTask(with: url) { data, _, _ in
            completion(data)
        }.resume()
    }

    private func displayAnimatedSprite(data: Data) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return }
        let frameCount = CGImageSourceGetCount(source)

        if frameCount > 1 {
            // Animated GIF — extract frames and durations
            var frames: [CGImage] = []
            var totalDuration: Double = 0

            for i in 0..<frameCount {
                guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
                frames.append(cgImage)

                // Get frame duration from GIF properties
                var frameDuration = 0.1
                if let properties = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any],
                   let gifProps = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any] {
                    if let delay = gifProps[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double, delay > 0 {
                        frameDuration = delay
                    } else if let delay = gifProps[kCGImagePropertyGIFDelayTime as String] as? Double, delay > 0 {
                        frameDuration = delay
                    }
                }
                totalDuration += frameDuration
            }

            guard !frames.isEmpty else { return }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                // Create keyframe animation
                let animation = CAKeyframeAnimation(keyPath: "contents")
                animation.values = frames
                animation.duration = totalDuration * 2
                animation.repeatCount = .infinity
                animation.calculationMode = .discrete // No interpolation between frames

                self.spriteLayer.removeAllAnimations()
                self.spriteLayer.contents = frames.first
                self.spriteLayer.add(animation, forKey: "gif")

                self.updateMenuBarIcon(from: frames.first)
            }
        } else {
            // Static image
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.spriteLayer.removeAllAnimations()
                self.spriteLayer.contents = cgImage
                self.updateMenuBarIcon(from: cgImage)
            }
        }
    }

    private func updateMenuBarIcon(from cgImage: CGImage?) {
        guard let cgImage = cgImage else { return }
        let smallSize = NSSize(width: 18, height: 18)
        let small = NSImage(size: smallSize)
        small.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .none
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        nsImage.draw(in: NSRect(origin: .zero, size: smallSize))
        small.unlockFocus()
        small.isTemplate = false
        statusItem.button?.image = small
        statusItem.button?.title = ""
    }
}
