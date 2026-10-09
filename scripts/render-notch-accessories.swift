import AppKit
import SceneKit
import Metal

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources/Notch3D", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let cellSize = 96
let columns = 10
let rows = 6
let frameCount = columns * rows

func material(_ color: NSColor, roughness: CGFloat = 0.22, metalness: CGFloat = 0.0) -> SCNMaterial {
    let result = SCNMaterial()
    result.lightingModel = .physicallyBased
    result.diffuse.contents = color
    result.roughness.contents = roughness
    result.metalness.contents = metalness
    return result
}

let ceramic = material(NSColor(white: 0.68, alpha: 1))
let silicone = material(NSColor(white: 0.58, alpha: 1), roughness: 0.65)
let vent = material(NSColor(white: 0.035, alpha: 1), roughness: 0.55)
let chrome = material(NSColor(white: 0.7, alpha: 1), roughness: 0.17, metalness: 0.85)
let aluminum = material(NSColor(red: 0.52, green: 0.60, blue: 0.66, alpha: 1), roughness: 0.3, metalness: 0.7)

@discardableResult
func add(_ geometry: SCNGeometry, to parent: SCNNode, at position: SCNVector3,
         scale: SCNVector3 = SCNVector3(1, 1, 1), surface: SCNMaterial = ceramic) -> SCNNode {
    geometry.materials = [surface]
    let node = SCNNode(geometry: geometry)
    node.position = position
    node.scale = scale
    parent.addChildNode(node)
    return node
}

func earbuds(pro: Bool) -> SCNNode {
    let pair = SCNNode()
    for side: Float in [-1, 1] {
        let bud = SCNNode()
        bud.position = SCNVector3(side * 0.67, 0, side * 0.14)
        bud.eulerAngles = SCNVector3(-0.12, side * -0.28, side * -0.14)
        pair.addChildNode(bud)
        let stemLength: CGFloat = pro ? 1.14 : 1.48
        add(SCNCapsule(capRadius: 0.125, height: stemLength), to: bud,
            at: SCNVector3(-side * 0.16, -0.30, 0.02))
        add(SCNSphere(radius: 0.49), to: bud, at: SCNVector3(0, 0.44, 0),
            scale: SCNVector3(1, 0.78, 0.83))
        add(SCNSphere(radius: 0.18), to: bud, at: SCNVector3(side * 0.17, 0.49, 0.355),
            scale: SCNVector3(0.55, 1, 0.20), surface: vent)
        add(SCNSphere(radius: 0.10), to: bud, at: SCNVector3(-side * 0.27, 0.36, 0.29),
            scale: SCNVector3(0.45, 1, 0.22), surface: vent)
        add(SCNCylinder(radius: 0.124, height: 0.07), to: bud,
            at: SCNVector3(-side * 0.16, -0.30 - Float(stemLength) / 2 + 0.13, 0.02), surface: chrome)
        if pro {
            add(SCNSphere(radius: 0.26), to: bud, at: SCNVector3(-side * 0.37, 0.48, -0.03),
                scale: SCNVector3(0.95, 0.72, 0.82), surface: silicone)
            add(SCNSphere(radius: 0.12), to: bud, at: SCNVector3(-side * 0.57, 0.48, 0.01),
                scale: SCNVector3(0.12, 0.85, 0.8), surface: vent)
        }
    }
    return pair
}

func headphones() -> SCNNode {
    let root = SCNNode()
    let path = NSBezierPath()
    path.flatness = 0.005
    path.move(to: NSPoint(x: -0.95, y: -0.02))
    path.curve(to: NSPoint(x: 0.95, y: -0.02), controlPoint1: NSPoint(x: -1.25, y: 1.78), controlPoint2: NSPoint(x: 1.25, y: 1.78))
    path.line(to: NSPoint(x: 0.78, y: -0.02))
    path.curve(to: NSPoint(x: -0.78, y: -0.02), controlPoint1: NSPoint(x: 1.04, y: 1.49), controlPoint2: NSPoint(x: -1.04, y: 1.49))
    path.close()
    let band = SCNShape(path: path, extrusionDepth: 0.16)
    band.chamferRadius = 0.055
    add(band, to: root, at: SCNVector3(0, 0, 0), surface: chrome)
    for side: Float in [-1, 1] {
        let cup = add(SCNBox(width: 0.65, height: 1.05, length: 0.44, chamferRadius: 0.23),
                      to: root, at: SCNVector3(side * 0.92, -0.30, 0), surface: aluminum)
        cup.eulerAngles.z = CGFloat(side) * 0.08
        add(SCNBox(width: 0.51, height: 0.89, length: 0.21, chamferRadius: 0.18),
            to: cup, at: SCNVector3(0, 0, -0.25), surface: vent)
    }
    return root
}

func write(_ image: CGImage, to url: URL) throws {
    guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        fatalError("PNG encoding failed")
    }
    try data.write(to: url)
}

guard let device = MTLCreateSystemDefaultDevice() else { fatalError("Metal unavailable") }
for kind in ["earbuds-pro", "earbuds", "headphones"] {
    let scene = SCNScene()
    scene.background.contents = NSColor.clear
    let product = kind == "headphones" ? headphones() : earbuds(pro: kind == "earbuds-pro")
    scene.rootNode.addChildNode(product)
    let cameraNode = SCNNode()
    let camera = SCNCamera()
    camera.usesOrthographicProjection = true
    camera.orthographicScale = 1.68
    camera.zNear = 0.1
    camera.zFar = 30
    camera.wantsHDR = true
    camera.wantsExposureAdaptation = false
    camera.exposureOffset = -1.0
    cameraNode.camera = camera
    cameraNode.position = SCNVector3(0, 0.15, 6)
    cameraNode.look(at: SCNVector3(0, 0.05, 0))
    scene.rootNode.addChildNode(cameraNode)
    for (position, intensity) in [(SCNVector3(-3, 4, 5), 350.0),
                                  (SCNVector3(4, 0, 3), 60.0),
                                  (SCNVector3(0, 3, -4), 200.0)] {
        let light = SCNLight()
        light.type = .omni
        light.intensity = intensity
        let node = SCNNode()
        node.light = light
        node.position = position
        scene.rootNode.addChildNode(node)
    }
    let ambient = SCNNode()
    ambient.light = SCNLight()
    ambient.light?.type = .ambient
    ambient.light?.intensity = 60
    scene.rootNode.addChildNode(ambient)
    let renderer = SCNRenderer(device: device, options: nil)
    renderer.scene = scene
    renderer.pointOfView = cameraNode
    guard let atlas = CGContext(data: nil, width: cellSize * columns, height: cellSize * rows,
                               bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("Atlas allocation failed") }
    for frame in 0..<frameCount {
        try autoreleasepool {
            let progress = Double(frame) / Double(frameCount - 1)
            let eased = progress * progress * (3 - 2 * progress)
            product.eulerAngles = SCNVector3(Float(-0.12 + 0.12 * eased), Float(-1.48 + 1.75 * eased), Float(-0.10 * (1 - eased)))
            let snapshot = renderer.snapshot(atTime: Double(frame) / 60, with: CGSize(width: cellSize, height: cellSize), antialiasingMode: .multisampling4X)
            guard let image = snapshot.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fatalError("Snapshot failed") }
            atlas.draw(image, in: CGRect(x: frame % columns * cellSize,
                                        y: (rows - 1 - frame / columns) * cellSize, width: cellSize, height: cellSize))
            if frame == frameCount - 1 {
                try write(image, to: output.appendingPathComponent("\(kind)-still.png"))
                if let proofPath = ProcessInfo.processInfo.environment["FLOWSHELF_3D_PROOF_DIR"] {
                    let proof = renderer.snapshot(atTime: Double(frame) / 60, with: CGSize(width: 384, height: 384), antialiasingMode: .multisampling4X)
                    if let proofImage = proof.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                        try write(proofImage, to: URL(fileURLWithPath: proofPath).appendingPathComponent("\(kind)-proof.png"))
                    }
                }
            }
        }
    }
    guard let image = atlas.makeImage() else { fatalError("Atlas missing") }
    try write(image, to: output.appendingPathComponent("\(kind)-atlas.png"))
    print("Rendered \(kind): \(frameCount) genuinely 3D frames, \(image.width) × \(image.height)")
}
