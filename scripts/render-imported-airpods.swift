import AppKit
import SceneKit
import Metal
import simd

enum ImportError: Error { case invalid(String) }

final class GLBModel {
    let document: [String: Any]
    let binary: Data

    init(url: URL) throws {
        let data = try Data(contentsOf: url)
        func word(_ offset: Int) -> UInt32 {
            data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian }
        }
        guard data.count >= 28, word(0) == 0x46546C67, word(4) == 2,
              Int(word(8)) == data.count else { throw ImportError.invalid("GLB header") }
        let jsonSize = Int(word(12))
        guard word(16) == 0x4E4F534A, 28 + jsonSize <= data.count else { throw ImportError.invalid("JSON chunk") }
        document = try JSONSerialization.jsonObject(with: data.subdata(in: 20..<20 + jsonSize)) as! [String: Any]
        let binaryStart = 20 + jsonSize
        let binarySize = Int(word(binaryStart))
        guard word(binaryStart + 4) == 0x004E4942,
              binaryStart + 8 + binarySize <= data.count else { throw ImportError.invalid("BIN chunk") }
        binary = data.subdata(in: binaryStart + 8..<binaryStart + 8 + binarySize)
    }

    func array(_ key: String) -> [[String: Any]] { document[key] as? [[String: Any]] ?? [] }

    func accessor(_ index: Int) throws -> (Data, Int, Int, Int) {
        let descriptor = array("accessors")[index]
        guard descriptor["sparse"] == nil, let viewIndex = descriptor["bufferView"] as? Int,
              let component = descriptor["componentType"] as? Int,
              let count = descriptor["count"] as? Int,
              let type = descriptor["type"] as? String,
              let components = ["SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4][type],
              let bytes = [5121: 1, 5123: 2, 5125: 4, 5126: 4][component]
        else { throw ImportError.invalid("Unsupported accessor") }
        let view = array("bufferViews")[viewIndex]
        guard view["buffer"] as? Int == 0 else { throw ImportError.invalid("External buffer") }
        let offset = (view["byteOffset"] as? Int ?? 0) + (descriptor["byteOffset"] as? Int ?? 0)
        let width = components * bytes
        let stride = view["byteStride"] as? Int ?? width
        guard count > 0, stride >= width, offset >= 0,
              offset + (count - 1) * stride + width <= binary.count else { throw ImportError.invalid("Accessor bounds") }
        var packed = Data()
        for element in 0..<count { packed.append(binary.subdata(in: offset + element * stride..<offset + element * stride + width)) }
        return (packed, count, components, bytes)
    }

    func material(_ index: Int) throws -> SCNMaterial {
        let descriptor = array("materials")[index]
        let properties = descriptor["pbrMetallicRoughness"] as? [String: Any] ?? [:]
        let color = properties["baseColorFactor"] as? [Double] ?? [1, 1, 1, 1]
        let material = SCNMaterial()
        material.name = descriptor["name"] as? String
        material.lightingModel = .physicallyBased
        material.diffuse.contents = NSColor(srgbRed: color[0], green: color[1], blue: color[2], alpha: color[3])
        material.metalness.contents = properties["metallicFactor"] as? Double ?? 1
        material.roughness.contents = max(0.18, properties["roughnessFactor"] as? Double ?? 1)
        material.isDoubleSided = descriptor["doubleSided"] as? Bool ?? false
        if let texture = properties["baseColorTexture"] as? [String: Any], let textureIndex = texture["index"] as? Int,
           let sourceIndex = array("textures")[textureIndex]["source"] as? Int,
           let viewIndex = array("images")[sourceIndex]["bufferView"] as? Int {
            let view = array("bufferViews")[viewIndex]
            let offset = view["byteOffset"] as? Int ?? 0
            let length = view["byteLength"] as! Int
            guard offset >= 0, offset + length <= binary.count else { throw ImportError.invalid("Image bounds") }
            material.diffuse.contents = NSImage(data: binary.subdata(in: offset..<offset + length))
        }
        return material
    }

    func node(_ index: Int) throws -> SCNNode {
        let descriptor = array("nodes")[index]
        let node = SCNNode()
        node.name = descriptor["name"] as? String
        if let matrix = descriptor["matrix"] as? [Float], matrix.count == 16 {
            node.simdTransform = simd_float4x4(columns: (
                SIMD4(matrix[0], matrix[1], matrix[2], matrix[3]), SIMD4(matrix[4], matrix[5], matrix[6], matrix[7]),
                SIMD4(matrix[8], matrix[9], matrix[10], matrix[11]), SIMD4(matrix[12], matrix[13], matrix[14], matrix[15])))
        } else {
            if let values = descriptor["translation"] as? [Float] { node.simdPosition = SIMD3(values[0], values[1], values[2]) }
            if let values = descriptor["rotation"] as? [Float] { node.simdOrientation = simd_quatf(vector: SIMD4(values[0], values[1], values[2], values[3])) }
            if let values = descriptor["scale"] as? [Float] { node.simdScale = SIMD3(values[0], values[1], values[2]) }
        }
        if let meshIndex = descriptor["mesh"] as? Int {
            let primitives = array("meshes")[meshIndex]["primitives"] as! [[String: Any]]
            for primitive in primitives {
                guard primitive["mode"] as? Int ?? 4 == 4 else { throw ImportError.invalid("Non-triangle primitive") }
                let attributes = primitive["attributes"] as! [String: Int]
                var sources: [SCNGeometrySource] = []
                for (key, semantic) in [("POSITION", SCNGeometrySource.Semantic.vertex), ("NORMAL", .normal), ("TEXCOORD_0", .texcoord)] {
                    guard let attributeIndex = attributes[key] else { continue }
                    let (data, count, components, bytes) = try accessor(attributeIndex)
                    guard bytes == 4 else { throw ImportError.invalid("Non-float attribute") }
                    sources.append(SCNGeometrySource(data: data, semantic: semantic, vectorCount: count,
                        usesFloatComponents: true, componentsPerVector: components, bytesPerComponent: bytes,
                        dataOffset: 0, dataStride: components * bytes))
                }
                let (indices, count, _, bytes) = try accessor(primitive["indices"] as! Int)
                let element = SCNGeometryElement(data: indices, primitiveType: .triangles, primitiveCount: count / 3, bytesPerIndex: bytes)
                let geometry = SCNGeometry(sources: sources, elements: [element])
                geometry.materials = [try material(primitive["material"] as! Int)]
                node.addChildNode(SCNNode(geometry: geometry))
            }
        }
        for child in descriptor["children"] as? [Int] ?? [] { node.addChildNode(try self.node(child)) }
        return node
    }
}

func savePNG(_ image: CGImage, to url: URL) throws {
    let representation = NSBitmapImageRep(cgImage: image)
    guard let data = representation.representation(using: .png, properties: [:]) else { throw ImportError.invalid("PNG encode") }
    try data.write(to: url, options: .atomic)
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else { fatalError("Usage: render-imported-airpods model.glb output-directory") }
let output = URL(fileURLWithPath: arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let model = try GLBModel(url: URL(fileURLWithPath: arguments[1]))
let nodes = model.array("nodes")
guard let accessoryIndex = nodes.firstIndex(where: { $0["name"] as? String == "Airpods" }) else { throw ImportError.invalid("Airpods node missing") }
let imported = try model.node(accessoryIndex)
imported.simdPosition = .zero
let accessory = SCNNode()
let earbuds = [SCNNode(), SCNNode()]
var splitTriangles = 0
imported.enumerateChildNodes { node, _ in
    guard let geometry = node.geometry,
          let vertices = geometry.sources(for: .vertex).first,
          let normals = geometry.sources(for: .normal).first else { return }
    func vector(_ source: SCNGeometrySource, _ index: Int) -> SIMD3<Float> {
        source.data.withUnsafeBytes { data in
            let offset = source.dataOffset + index * source.dataStride
            return SIMD3(data.loadUnaligned(fromByteOffset: offset, as: Float.self),
                         data.loadUnaligned(fromByteOffset: offset + 4, as: Float.self),
                         data.loadUnaligned(fromByteOffset: offset + 8, as: Float.self))
        }
    }
    for element in geometry.elements {
        var positions = [[SCNVector3](), [SCNVector3]()]
        var directions = [[SCNVector3](), [SCNVector3]()]
        var textureCoordinates = [[CGPoint](), [CGPoint]()]
        let textureSource = geometry.sources(for: .texcoord).first
        element.data.withUnsafeBytes { indices in
            for triangle in 0..<element.primitiveCount {
                let triangleIndices = (0..<3).map { corner -> Int in
                    let offset = (triangle * 3 + corner) * element.bytesPerIndex
                    if element.bytesPerIndex == 2 { return Int(indices.loadUnaligned(fromByteOffset: offset, as: UInt16.self)) }
                    if element.bytesPerIndex == 1 { return Int(indices.loadUnaligned(fromByteOffset: offset, as: UInt8.self)) }
                    return Int(indices.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
                }
                let points = triangleIndices.map { node.simdConvertPosition(vector(vertices, $0), to: imported) }
                if points.contains(where: { $0.x < 0 }) && points.contains(where: { $0.x > 0 }) { splitTriangles += 1 }
                let side = points.reduce(Float(0)) { $0 + $1.x } < 0 ? 0 : 1
                for (index, point) in zip(triangleIndices, points) {
                    positions[side].append(SCNVector3(point))
                    directions[side].append(SCNVector3(simd_normalize(node.simdConvertVector(vector(normals, index), to: imported))))
                    if let textureSource {
                        let coordinate = textureSource.data.withUnsafeBytes { data -> CGPoint in
                            let offset = textureSource.dataOffset + index * textureSource.dataStride
                            return CGPoint(x: CGFloat(data.loadUnaligned(fromByteOffset: offset, as: Float.self)),
                                           y: CGFloat(data.loadUnaligned(fromByteOffset: offset + 4, as: Float.self)))
                        }
                        textureCoordinates[side].append(coordinate)
                    }
                }
            }
        }
        for side in 0..<2 where !positions[side].isEmpty {
            let indices = (0..<positions[side].count).map(UInt32.init)
            var sources: [SCNGeometrySource] = [.init(vertices: positions[side]), .init(normals: directions[side])]
            if !textureCoordinates[side].isEmpty { sources.append(.init(textureCoordinates: textureCoordinates[side])) }
            let mesh = SCNGeometry(sources: sources,
                                  elements: [.init(indices: indices, primitiveType: .triangles)])
            mesh.materials = geometry.materials
            earbuds[side].addChildNode(SCNNode(geometry: mesh))
        }
    }
}
guard splitTriangles == 0 else { throw ImportError.invalid("Earbud separation crosses \(splitTriangles) triangles") }
for (index, earbud) in earbuds.enumerated() {
    let bounds = earbud.boundingBox
    let midpoint = (SIMD3<Float>(bounds.min) + SIMD3<Float>(bounds.max)) / 2
    for part in earbud.childNodes {
        part.simdPosition = -midpoint
    }
    earbud.eulerAngles = SCNVector3(0, index == 0 ? -0.45 : 2.5, index == 0 ? 0 : -0.30)
    earbud.position = SCNVector3(index == 0 ? -45 : 45, index == 0 ? -14 : 14, index == 0 ? 48 : -48)
    accessory.addChildNode(earbud)
}
var minimum = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
var maximum = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
accessory.enumerateChildNodes { node, _ in
    guard let vertices = node.geometry?.sources(for: .vertex).first else { return }
    vertices.data.withUnsafeBytes { data in
        for index in 0..<vertices.vectorCount {
            let offset = vertices.dataOffset + index * vertices.dataStride
            let position = SIMD3<Float>(data.loadUnaligned(fromByteOffset: offset, as: Float.self),
                                       data.loadUnaligned(fromByteOffset: offset + 4, as: Float.self),
                                       data.loadUnaligned(fromByteOffset: offset + 8, as: Float.self))
            let converted = node.simdConvertPosition(position, to: accessory)
            minimum = simd_min(minimum, converted)
            maximum = simd_max(maximum, converted)
        }
    }
}
let center = (minimum + maximum) / 2
let extent = maximum - minimum
print("Accessory bounds: \(minimum)...\(maximum), extent: \(extent)")
for earbud in earbuds { earbud.simdPosition -= center }
let normalization = 1.8 / max(extent.x, extent.y, extent.z)
accessory.simdScale = SIMD3(repeating: normalization)
let turn = SCNNode()
turn.addChildNode(accessory)
let scene = SCNScene()
scene.background.contents = NSColor.clear
scene.rootNode.addChildNode(turn)
let camera = SCNNode()
camera.camera = SCNCamera()
camera.camera?.usesOrthographicProjection = true
camera.camera?.orthographicScale = 1.15
camera.camera?.wantsHDR = true
camera.camera?.wantsExposureAdaptation = false
camera.camera?.exposureOffset = -1
camera.position = SCNVector3(0, 0, 6)
scene.rootNode.addChildNode(camera)
for (position, intensity, type) in [(SCNVector3(-3, 4, 5), 230.0, SCNLight.LightType.omni),
                                   (SCNVector3(4, 1, 3), 60.0, .omni),
                                   (SCNVector3(0, 3, -4), 120.0, .omni),
                                   (SCNVector3(0, 0, 0), 45.0, .ambient)] {
    let light = SCNNode()
    light.light = SCNLight()
    light.light?.type = type
    light.light?.intensity = intensity
    light.position = position
    scene.rootNode.addChildNode(light)
}
guard let device = MTLCreateSystemDefaultDevice() else { throw ImportError.invalid("Metal unavailable") }
let renderer = SCNRenderer(device: device, options: nil)
renderer.scene = scene
renderer.pointOfView = camera
let cell = 96
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let atlas = CGContext(data: nil, width: cell * 10, height: cell * 6, bitsPerComponent: 8,
                      bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
for frame in 0..<60 {
    try autoreleasepool {
        let progress = Float(frame) / 59
        let eased = progress * progress * (3 - 2 * progress)
        turn.eulerAngles = SCNVector3(-0.08, -0.22 + eased * 0.38, 0)
        let snapshot = renderer.snapshot(atTime: Double(frame) / 60, with: CGSize(width: 384, height: 384), antialiasingMode: .multisampling4X)
        guard let image = snapshot.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw ImportError.invalid("Snapshot") }
        atlas.interpolationQuality = .high
        atlas.draw(image, in: CGRect(x: frame % 10 * cell, y: (5 - frame / 10) * cell, width: cell, height: cell))
        if [0, 29, 59].contains(frame) { try savePNG(image, to: output.appendingPathComponent("proof-\(frame).png")) }
        if frame == 59 {
            let still = CGContext(data: nil, width: cell, height: cell, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            still.interpolationQuality = .high
            still.draw(image, in: CGRect(x: 0, y: 0, width: cell, height: cell))
            try savePNG(still.makeImage()!, to: output.appendingPathComponent("earbuds-pro-still.png"))
        }
    }
}
try savePNG(atlas.makeImage()!, to: output.appendingPathComponent("earbuds-pro-atlas.png"))
print("Rendered 60 frames from Jed Falcone's AirPods Pro mesh")
