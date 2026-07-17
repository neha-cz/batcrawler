import Cocoa
import Foundation

// MARK: - Math helpers

struct Vec2 {
    var x: CGFloat
    var y: CGFloat
}

enum Side: CaseIterable {
    case bottom, right, top, left
}

struct Batarang {
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat
    var rotation: CGFloat
    var spin: CGFloat
    var life: CGFloat
    var bouncesLeft: Int
}

struct Spark {
    var x: CGFloat
    var y: CGFloat
    var life: CGFloat
    var maxLife: CGFloat
    var nx: CGFloat
    var ny: CGFloat
}

// MARK: - Asset loader

final class Assets {
    let left: NSImage
    let right: NSImage
    let front: NSImage
    let batarang: NSImage

    init(base: URL) {
        func load(_ name: String) -> NSImage {
            let url = base.appendingPathComponent("assets/\(name)")
            guard let image = NSImage(contentsOf: url) else {
                fputs("Missing asset: \(url.path)\n", stderr)
                exit(1)
            }
            return image
        }
        left = load("batman-left.png")
        right = load("batman-right.png")
        front = load("batman-front.png")
        batarang = load("batarang.png")
    }
}

// MARK: - Batman view

final class BatmanView: NSView {
    var sprite: NSImage?
    var rotation: CGFloat = 0
    var bobPhase: CGFloat = 0
    var isWalking = true
    var onSingleClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onDragStart: (() -> Void)?
    var onDragMove: ((NSPoint) -> Void)?
    var onDragEnd: ((NSPoint) -> Void)?

    private var pendingClick: DispatchWorkItem?
    private var dragStart: NSPoint?
    private var isDragging = false
    private let dragThreshold: CGFloat = 6

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let sprite, let ctx = NSGraphicsContext.current?.cgContext else { return }

        let bob = isWalking ? sin(bobPhase) * 3 : 0
        let scale: CGFloat = isWalking ? 1 : 1.06
        let drawSize = min(bounds.width, bounds.height) * 0.92 * scale

        ctx.saveGState()
        ctx.translateBy(x: bounds.midX, y: bounds.midY + bob)
        ctx.rotate(by: rotation * .pi / 180)
        let rect = NSRect(x: -drawSize / 2, y: -drawSize / 2, width: drawSize, height: drawSize)
        sprite.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        ctx.restoreGState()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            pendingClick?.cancel()
            pendingClick = nil
            dragStart = nil
            onDoubleClick?()
            return
        }

        dragStart = event.locationInWindow
        isDragging = false

        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isDragging else { return }
            self.onSingleClick?()
        }
        pendingClick = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: work)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let current = event.locationInWindow
        let dx = current.x - start.x
        let dy = current.y - start.y

        if !isDragging, hypot(dx, dy) > dragThreshold {
            isDragging = true
            pendingClick?.cancel()
            pendingClick = nil
            onDragStart?()
        }

        if isDragging {
            onDragMove?(NSEvent.mouseLocation)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            onDragEnd?(NSEvent.mouseLocation)
            isDragging = false
            dragStart = nil
            return
        }
        dragStart = nil
    }
}

// MARK: - Batarang overlay view

final class BatarangView: NSView {
    var batarangs: [Batarang] = []
    var sparks: [Spark] = []
    var image: NSImage?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let size: CGFloat = 36

        if let image {
            for b in batarangs {
                let alpha = min(1, b.life / 0.35)
                ctx.saveGState()
                ctx.translateBy(x: b.x, y: b.y)
                ctx.rotate(by: b.rotation * .pi / 180)
                ctx.setAlpha(alpha)
                let rect = NSRect(x: -size / 2, y: -size / 2, width: size, height: size)
                image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: nil)
                ctx.restoreGState()
            }
        }

        for spark in sparks {
            let t = spark.life / spark.maxLife
            let alpha = min(1, t * 1.4)
            let burst = (1 - t) * 18 + 4

            ctx.saveGState()
            ctx.translateBy(x: spark.x, y: spark.y)
            ctx.setAlpha(alpha)

            for i in 0..<8 {
                let angle = CGFloat(i) * (.pi / 4) + atan2(spark.ny, spark.nx)
                let inner = burst * 0.2
                let outer = burst * (0.65 + CGFloat(i) * 0.04)
                ctx.setStrokeColor(NSColor(red: 1, green: 0.35 + CGFloat(i) * 0.04, blue: 0.15, alpha: alpha).cgColor)
                ctx.setLineWidth(2.2)
                ctx.move(to: CGPoint(x: cos(angle) * inner, y: sin(angle) * inner))
                ctx.addLine(to: CGPoint(x: cos(angle) * outer, y: sin(angle) * outer))
                ctx.strokePath()
            }

            ctx.setFillColor(NSColor(red: 1, green: 0.95, blue: 0.7, alpha: alpha * 0.9).cgColor)
            ctx.fillEllipse(in: CGRect(x: -3, y: -3, width: 6, height: 6))
            ctx.restoreGState()
        }
    }
}

// MARK: - Crawler engine

final class Crawler: NSObject {
    let assets: Assets
    let batmanWindow: NSWindow
    let batmanView: BatmanView
    let overlayWindow: NSWindow
    let batarangView: BatarangView

    let size: CGFloat = 88
    let speed: CGFloat = 110
    let burstMultiplier: CGFloat = 2.6
    let inset: CGFloat = 4
    let faceEvery: CFTimeInterval = 4
    let faceDuration: CFTimeInterval = 1.2

    var side: Side = .bottom
    var along: CGFloat = 0
    var clockwise = true
    var facingFront = false
    var firing = false
    var jumping = false
    var dragging = false
    var jumpProgress: CGFloat = 0
    let jumpDuration: CGFloat = 0.55
    let jumpHeight: CGFloat = 72

    var faceTimer: CFTimeInterval = 0
    var faceHold: CFTimeInterval = 0
    var bobPhase: CGFloat = 0
    var lastTick = CFAbsoluteTimeGetCurrent()

    var burstCooldown: CGFloat = 8
    var burstRemaining: CGFloat = 0
    var reverseCooldown: CGFloat = 22

    var batarangs: [Batarang] = []
    var sparks: [Spark] = []
    var screenFrame: NSRect = .zero

    init(assets: Assets) {
        self.assets = assets

        batmanView = BatmanView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        batmanWindow = NSWindow(
            contentRect: batmanView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        batmanWindow.contentView = batmanView
        batmanWindow.backgroundColor = .clear
        batmanWindow.isOpaque = false
        batmanWindow.hasShadow = false
        batmanWindow.level = .screenSaver
        batmanWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        batmanWindow.isReleasedWhenClosed = false

        batarangView = BatarangView(frame: .zero)
        batarangView.image = assets.batarang
        overlayWindow = NSWindow(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        overlayWindow.contentView = batarangView
        overlayWindow.backgroundColor = .clear
        overlayWindow.isOpaque = false
        overlayWindow.hasShadow = false
        overlayWindow.ignoresMouseEvents = true
        overlayWindow.level = .screenSaver
        overlayWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        overlayWindow.isReleasedWhenClosed = false

        super.init()

        batmanView.onSingleClick = { [weak self] in self?.fireBatarangs() }
        batmanView.onDoubleClick = { [weak self] in self?.startJump() }
        batmanView.onDragStart = { [weak self] in self?.startDrag() }
        batmanView.onDragMove = { [weak self] in self?.dragMove(to: $0) }
        batmanView.onDragEnd = { [weak self] in self?.endDrag(at: $0) }

        refreshScreenFrame()
        along = (sideLength(for: side) * 0.25).rounded()
        updateBatman(animateBob: false)
    }

    func show() {
        batmanWindow.orderFrontRegardless()
        overlayWindow.orderFrontRegardless()
    }

    func hide() {
        batmanWindow.orderOut(nil)
        overlayWindow.orderOut(nil)
    }

    func refreshScreenFrame() {
        guard let screen = NSScreen.main else { return }
        screenFrame = screen.frame
        overlayWindow.setFrame(screenFrame, display: true)
        batarangView.frame = overlayWindow.contentView?.bounds ?? screenFrame
        along = min(along, max(1, sideLength(for: side) - 1))
    }

    func borderBounds() -> (left: CGFloat, right: CGFloat, bottom: CGFloat, top: CGFloat) {
        let half = size / 2
        return (
            screenFrame.minX + inset + half,
            screenFrame.maxX - inset - half,
            screenFrame.minY + inset + half,
            screenFrame.maxY - inset - half
        )
    }

    func sideLength(for side: Side) -> CGFloat {
        let b = borderBounds()
        switch side {
        case .bottom, .top: return max(1, b.right - b.left)
        case .left, .right: return max(1, b.top - b.bottom)
        }
    }

    func nextSide(_ side: Side) -> Side {
        let order: [Side] = [.bottom, .right, .top, .left]
        guard let i = order.firstIndex(of: side) else { return .bottom }
        return order[(i + 1) % 4]
    }

    func previousSide(_ side: Side) -> Side {
        let order: [Side] = [.bottom, .right, .top, .left]
        guard let i = order.firstIndex(of: side) else { return .bottom }
        return order[(i + 3) % 4]
    }

    func borderPosition() -> (center: NSPoint, dir: Vec2, edgeRot: CGFloat) {
        let b = borderBounds()
        let len = sideLength(for: side)
        along = along.truncatingRemainder(dividingBy: len)
        if along < 0 { along += len }

        switch side {
        case .bottom:
            let x = clockwise ? b.left + along : b.right - along
            return (NSPoint(x: x, y: b.bottom), Vec2(x: clockwise ? 1 : -1, y: 0), 0)
        case .right:
            let y = clockwise ? b.bottom + along : b.top - along
            return (NSPoint(x: b.right, y: y), Vec2(x: 0, y: clockwise ? 1 : -1), 90)
        case .top:
            let x = clockwise ? b.right - along : b.left + along
            return (NSPoint(x: x, y: b.top), Vec2(x: clockwise ? -1 : 1, y: 0), 180)
        case .left:
            let y = clockwise ? b.top - along : b.bottom + along
            return (NSPoint(x: b.left, y: y), Vec2(x: 0, y: clockwise ? -1 : 1), -90)
        }
    }

    func maybeReverse(atCorner: Bool) {
        let chance: CGFloat = atCorner ? 0.18 : 0.35
        guard CGFloat.random(in: 0...1) < chance else { return }
        clockwise.toggle()
        facingFront = true
        faceHold = 0
        faceTimer = 0
        reverseCooldown = CGFloat.random(in: 20...34)
    }

    func advanceSide(_ distance: CGFloat) {
        let startSide = side
        along += distance
        var guardCount = 0
        while along >= sideLength(for: side), guardCount < 8 {
            along -= sideLength(for: side)
            side = clockwise ? nextSide(side) : previousSide(side)
            if side != startSide || guardCount > 0 {
                maybeReverse(atCorner: true)
            }
            guardCount += 1
        }
    }

    func updateSprite(pos: (center: NSPoint, dir: Vec2, edgeRot: CGFloat)) {
        if facingFront || dragging {
            batmanView.sprite = assets.front
            batmanView.rotation = dragging ? 0 : pos.edgeRot
            batmanView.isWalking = false
            return
        }

        let useRight: Bool
        switch side {
        case .bottom: useRight = pos.dir.x > 0
        case .top: useRight = pos.dir.x < 0
        case .right: useRight = pos.dir.y > 0
        case .left: useRight = pos.dir.y < 0
        }

        batmanView.sprite = useRight ? assets.right : assets.left
        batmanView.rotation = pos.edgeRot
    }

    func inwardNormal() -> Vec2 {
        switch side {
        case .bottom: return Vec2(x: 0, y: 1)
        case .top: return Vec2(x: 0, y: -1)
        case .left: return Vec2(x: 1, y: 0)
        case .right: return Vec2(x: -1, y: 0)
        }
    }

    func startJump() {
        guard !jumping, !dragging else { return }
        jumping = true
        jumpProgress = 0
        facingFront = false
    }

    func startDrag() {
        dragging = true
        jumping = false
        facingFront = false
        burstRemaining = 0
    }

    func dragMove(to point: NSPoint) {
        let origin = NSPoint(x: point.x - size / 2, y: point.y - size / 2)
        batmanWindow.setFrame(NSRect(origin: origin, size: NSSize(width: size, height: size)), display: true)
        batmanView.sprite = assets.front
        batmanView.rotation = 0
        batmanView.isWalking = false
        batmanView.needsDisplay = true
    }

    func endDrag(at point: NSPoint) {
        dragging = false
        snapToBorder(point: point)
        reverseCooldown = CGFloat.random(in: 14...24)
        updateBatman(animateBob: false)
    }

    func snapToBorder(point: NSPoint) {
        let b = borderBounds()
        let dBottom = abs(point.y - b.bottom)
        let dTop = abs(point.y - b.top)
        let dLeft = abs(point.x - b.left)
        let dRight = abs(point.x - b.right)
        let minD = min(dBottom, dTop, dLeft, dRight)

        if minD == dBottom {
            side = .bottom
            along = max(0, min(point.x - b.left, sideLength(for: .bottom)))
            clockwise = along < sideLength(for: .bottom) / 2
        } else if minD == dTop {
            side = .top
            along = max(0, min(b.right - point.x, sideLength(for: .top)))
            clockwise = along < sideLength(for: .top) / 2
        } else if minD == dLeft {
            side = .left
            along = max(0, min(b.top - point.y, sideLength(for: .left)))
            clockwise = along > sideLength(for: .left) / 2
        } else {
            side = .right
            along = max(0, min(point.y - b.bottom, sideLength(for: .right)))
            clockwise = along < sideLength(for: .right) / 2
        }
    }

    func updateBatman(animateBob: Bool) {
        let pos = borderPosition()
        updateSprite(pos: pos)

        var center = pos.center
        if jumping {
            let t = min(1, max(0, jumpProgress))
            let arc = sin(t * .pi)
            let n = inwardNormal()
            center.x += n.x * jumpHeight * arc
            center.y += n.y * jumpHeight * arc
        }

        if !dragging {
            let origin = NSPoint(x: center.x - size / 2, y: center.y - size / 2)
            batmanWindow.setFrame(NSRect(origin: origin, size: NSSize(width: size, height: size)), display: true)
        }

        if animateBob {
            let bobRate: CGFloat = burstRemaining > 0 ? 0.5 : 0.28
            bobPhase += bobRate
        }
        batmanView.bobPhase = bobPhase
        batmanView.isWalking = !facingFront && !firing && !jumping && !dragging
        batmanView.needsDisplay = true
    }

    func fireBatarangs() {
        guard !firing, !jumping, !dragging else { return }
        let pos = borderPosition()
        let baseAngle = atan2(pos.dir.y, pos.dir.x)
        let count = 5
        let spread: CGFloat = 0.28

        firing = true
        facingFront = false
        updateBatman(animateBob: false)

        for i in 0..<count {
            let t = CGFloat(i) / CGFloat(count - 1)
            let offset = (t - 0.5) * spread
            let angle = baseAngle + offset
            let delay = Double(i) * 0.055
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.spawnBatarang(at: pos.center, angle: angle)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.firing = false
        }
    }

    func spawnBatarang(at center: NSPoint, angle: CGFloat) {
        let shotSpeed = 520 * CGFloat.random(in: 0.88...1.12)
        let spin: CGFloat = (Bool.random() ? 1 : -1) * CGFloat.random(in: 540...900)
        batarangs.append(Batarang(
            x: center.x,
            y: center.y,
            vx: cos(angle) * shotSpeed,
            vy: sin(angle) * shotSpeed,
            rotation: CGFloat.random(in: 0...360),
            spin: spin,
            life: 2.8,
            bouncesLeft: 1
        ))
    }

    func spawnSpark(at point: NSPoint, normal: Vec2) {
        sparks.append(Spark(
            x: point.x,
            y: point.y,
            life: 0.28,
            maxLife: 0.28,
            nx: normal.x,
            ny: normal.y
        ))
    }

    func currentMoveSpeed() -> CGFloat {
        burstRemaining > 0 ? speed * burstMultiplier : speed
    }

    func tick() {
        let now = CFAbsoluteTimeGetCurrent()
        let dt = min(0.05, CGFloat(now - lastTick))
        lastTick = now

        if !dragging {
            burstCooldown -= dt
            if burstCooldown <= 0, burstRemaining <= 0, !jumping, !facingFront, !firing {
                burstCooldown = CGFloat.random(in: 9...16)
                if CGFloat.random(in: 0...1) < 0.42 {
                    burstRemaining = CGFloat.random(in: 1.4...2.1)
                }
            }
            if burstRemaining > 0 {
                burstRemaining -= dt
            }

            reverseCooldown -= dt
            if reverseCooldown <= 0, !jumping, !facingFront, !firing {
                maybeReverse(atCorner: false)
            }
        }

        if jumping {
            jumpProgress += dt / jumpDuration
            if jumpProgress >= 1 {
                jumpProgress = 0
                jumping = false
            }
        } else if !facingFront, !firing, !dragging {
            faceTimer += dt
            if faceTimer >= faceEvery {
                facingFront = true
                faceHold = 0
                faceTimer = 0
            } else {
                advanceSide(currentMoveSpeed() * dt)
            }
        } else if facingFront, !dragging {
            faceHold += dt
            if faceHold >= faceDuration {
                facingFront = false
                faceHold = 0
            }
        }

        updateBatman(animateBob: !facingFront && !firing && !jumping && !dragging)
        updateBatarangs(dt: dt)
        updateSparks(dt: dt)
    }

    func updateBatarangs(dt: CGFloat) {
        let frame = screenFrame
        let margin: CGFloat = 90
        let pad: CGFloat = 10
        var remaining: [Batarang] = []

        for var b in batarangs {
            b.x += b.vx * dt
            b.y += b.vy * dt
            b.rotation += b.spin * dt
            b.life -= dt

            if b.x <= frame.minX + pad, b.vx < 0, b.bouncesLeft > 0 {
                b.x = frame.minX + pad
                b.vx = -b.vx * 0.88
                b.bouncesLeft -= 1
                spawnSpark(at: NSPoint(x: frame.minX, y: b.y), normal: Vec2(x: 1, y: 0))
            } else if b.x >= frame.maxX - pad, b.vx > 0, b.bouncesLeft > 0 {
                b.x = frame.maxX - pad
                b.vx = -b.vx * 0.88
                b.bouncesLeft -= 1
                spawnSpark(at: NSPoint(x: frame.maxX, y: b.y), normal: Vec2(x: -1, y: 0))
            }

            if b.y <= frame.minY + pad, b.vy < 0, b.bouncesLeft > 0 {
                b.y = frame.minY + pad
                b.vy = -b.vy * 0.88
                b.bouncesLeft -= 1
                spawnSpark(at: NSPoint(x: b.x, y: frame.minY), normal: Vec2(x: 0, y: 1))
            } else if b.y >= frame.maxY - pad, b.vy > 0, b.bouncesLeft > 0 {
                b.y = frame.maxY - pad
                b.vy = -b.vy * 0.88
                b.bouncesLeft -= 1
                spawnSpark(at: NSPoint(x: b.x, y: frame.maxY), normal: Vec2(x: 0, y: -1))
            }

            let off = b.x < frame.minX - margin ||
                b.x > frame.maxX + margin ||
                b.y < frame.minY - margin ||
                b.y > frame.maxY + margin ||
                b.life <= 0

            if !off {
                remaining.append(b)
            }
        }

        batarangs = remaining
        batarangView.batarangs = batarangs
        batarangView.needsDisplay = true
    }

    func updateSparks(dt: CGFloat) {
        sparks = sparks.compactMap { spark in
            var s = spark
            s.life -= dt
            return s.life > 0 ? s : nil
        }
        batarangView.sparks = sparks
        batarangView.needsDisplay = true
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    var crawler: Crawler?
    var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let base = URL(fileURLWithPath: #file).deletingLastPathComponent()
        let assets = Assets(base: base)
        let crawler = Crawler(assets: assets)
        self.crawler = crawler
        crawler.show()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.crawler?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        signal(SIGINT) { _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }

        fputs("Batman is crawling your screen.\n", stderr)
        fputs("  Click      → throw batarangs\n", stderr)
        fputs("  Double-click → jump\n", stderr)
        fputs("  Drag       → move to any edge\n", stderr)
        fputs("  Ctrl+C     → quit\n", stderr)
    }

    @objc func screenChanged() {
        crawler?.refreshScreenFrame()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        crawler?.hide()
        fputs("Batman retreated to the shadows.\n", stderr)
    }
}

// MARK: - Entry

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
