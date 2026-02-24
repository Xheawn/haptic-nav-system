//
//  LiDARManager.swift
//  navigationTest
//
//  8×8 grid depth analysis using ARKit smoothedSceneDepth.
//  Divides the 256×192 depth map into 64 cells (32×24 px each),
//  computes percentile-10 depth per cell, and publishes the grid
//  via a closure callback for UI display.
//

import Foundation
import ARKit
import simd

// MARK: - B2 Data Structures

enum ObstacleType {
    case wall           // continuous large surface, height > 1.5m
    case pole           // narrow, height > 1.0m
    case lowObstacle    // 0.15m ~ 0.5m (planter, bollard)
    case dropOff        // drop > 0.15m
    case tripHazard     // 0.08m ~ 0.15m trip risk
}

enum PointClassification: UInt8 {
    case invalid = 0
    case ground = 1
    case tripHazard = 2
    case obstacleLow = 3
    case obstacleMid = 4
    case obstacleHigh = 5
    case dropMild = 6
    case dropSevere = 7
}

struct PoseSnapshot {
    let cameraY: Float
    let cameraPitch: Float
    let bandGroundY: [Float]  // [near 0-1.5m, mid 1.5-3m, far 3-5m]
    let timestamp: TimeInterval
}

struct ObstacleCluster {
    let centerAngle: Float      // obstacle center direction (°, 0=forward, +=right, -=left)
    let distance: Float         // nearest distance (m)
    let angularWidth: Float     // angular width (°)
    let physicalWidth: Float    // physical width (m)
    let type: ObstacleType
}

struct FrameAnalysisResult {
    // ── Safe path ──
    let safePathExist: Bool           // (spe) a safe path exists
    let safePathStraight: Bool        // (sps) safe path is straight ahead
    let safePathAngle: Float          // (spa) safe path guidance angle (°, 0=forward, +=right, -=left)
    let safePathWidth: Float          // safe path physical width (m)

    // ── Terrain ──
    let pathDownSlope: Bool           // (pds) downhill slope detected
    let pathUpSlope: Bool             // (pus) uphill slope detected
    let downStairsExist: Bool         // (dse) downward stairs/curb detected
    let upStairsExist: Bool           // (use) upward stairs/curb detected

    // ── Blocked ──
    let noSafePathFound: Bool         // (nspf) no safe path exists

    // ── Auxiliary ──
    let nearestObstacleDistance: Float // nearest obstacle distance (m)
    let nearestObstacleAngle: Float   // nearest obstacle direction (°)
    let nearestForwardDistance: Float // nearest obstacle in forward cone ±15° (m)
    let groundY: Float                // current ground world Y height (band 0 = near)
    let bandGroundY: [Float]          // [near 0-1.5m, mid 1.5-3m, far 3-5m] ground Y
    let obstacles: [ObstacleCluster]  // detected obstacle clusters

    static let empty = FrameAnalysisResult(
        safePathExist: false, safePathStraight: false, safePathAngle: 0,
        safePathWidth: 0, pathDownSlope: false, pathUpSlope: false,
        downStairsExist: false, upStairsExist: false, noSafePathFound: true,
        nearestObstacleDistance: Float.greatestFiniteMagnitude,
        nearestObstacleAngle: 0, nearestForwardDistance: Float.greatestFiniteMagnitude,
        groundY: 0, bandGroundY: [0, 0, 0], obstacles: []
    )
}

// MARK: - LiDARManager

class LiDARManager: NSObject {

    static let shared = LiDARManager()

    // MARK: - Configurable parameters

    /// Distance (m) below which a cell is colored red (extreme danger)
    var dangerCloseDistance: Float = 0.5
    /// Distance (m) below which a cell is considered danger (orange)
    var dangerDistance: Float = 1.0
    /// Distance (m) below which a cell is considered caution zone
    var cautionDistance: Float = 2.0
    /// Horizontal gradient threshold (m) — obstacle edge detection
    var hGradientThreshold: Float = 1.0
    /// Vertical gradient threshold (m) — terrain discontinuity detection
    var vGradientThreshold: Float = 0.5
    /// Fraction of buffer x-axis to use (0.0–1.0). Lower = skip more near-ground data.
    /// 0.75 means use forward 75% of FOV, ignore bottom 25% (near feet).
    var forwardCropRatio: Float = 0.75
    /// How often to run analysis (seconds)
    var analysisInterval: TimeInterval = 0.2   // 5 Hz (balances responsiveness vs battery/heat)
    /// How often to print to console (seconds)
    var logInterval: TimeInterval = 0.5        // 2 Hz

    // MARK: - B2 Hazard analysis parameters

    /// Minimum safe passage width (m), approx. shoulder width
    var safeWidthConstant: Float = 0.8
    /// Direction column "safe" minimum obstacle distance (m)
    var minSafeDistance: Float = 2.0
    /// Maximum analysis range (m)
    var maxAnalysisRange: Float = 5.0
    /// ±tolerance (m) considered ground
    var groundTolerance: Float = 0.08
    /// Height above ground considered trip hazard (m)
    var tripHazardHeight: Float = 0.15
    /// Minimum height above ground to be an obstacle (m)
    var obstacleMinHeight: Float = 0.15
    /// Drop mild threshold (m, negative)
    var dropMildThreshold: Float = -0.10
    /// Drop severe threshold (m, negative)
    var dropSevereThreshold: Float = -0.15
    /// Stair single step min height (m)
    var stairStepHeightMin: Float = 0.10
    /// Stair single step max height (m)
    var stairStepHeightMax: Float = 0.25
    /// Minimum consecutive steps to classify as stairs
    var stairMinSteps: Int = 3
    /// Slope angle threshold (degrees) to report
    var slopeAngleThreshold: Float = 5.0
    /// EMA alpha for ground Y estimation (slow, ground doesn't jump)
    var groundYAlpha: Float = 0.1
    /// EMA alpha for safe path angle
    var angleAlpha: Float = 0.3
    /// Frames of consecutive detection to activate a bool flag
    var boolHysteresisOn: Int = 3
    /// Frames of consecutive non-detection to deactivate a bool flag
    var boolHysteresisOff: Int = 5

    // MARK: - Grid constants

    static let gridRows = 16
    static let gridCols = 16
    // Portrait rotation: display row ↔ buffer x, display col ↔ buffer y
    // Buffer is 256(w) × 192(h)
    // cellPixelsX is computed dynamically based on forwardCropRatio
    static let cellPixelsY = 12   // 192 / 16 — maps to display cols (left→right)

    // MARK: - Public state

    /// Latest 8×8 depth grid (row-major). Each value = percentile-10 depth in meters.
    /// Access from main thread only.
    private(set) var depthGrid: [[Float]] = Array(
        repeating: Array(repeating: Float.greatestFiniteMagnitude, count: 16),
        count: 16
    )

    /// Callback invoked on main thread with the updated 16×16 grid.
    /// ViewController hooks into this to update the debug UI.
    var onGridUpdate: (([[Float]]) -> Void)?

    /// Latest B2 hazard analysis result.
    private(set) var latestAnalysis: FrameAnalysisResult = .empty

    /// Callback invoked on main thread with the updated hazard analysis.
    var onHazardUpdate: ((FrameAnalysisResult) -> Void)?

    // MARK: - Private state

    private let session = ARSession()
    private var lastAnalysisTime: TimeInterval = 0
    private var lastLogTime: TimeInterval = 0

    // B2 temporal state
    private var smoothedBandGroundY: [Float?] = [nil, nil, nil]  // near/mid/far
    private var poseHistory: [PoseSnapshot] = []  // last ~10 frames for temporal validation
    private var smoothedAngle: Float = 0
    private var smoothedNearestDist: Float = 5.0
    private var lastCameraPitch: Float?  // degrees, 0=horizontal, +90=looking up, -90=looking down

    // Hysteresis counters for bool flags: [flagName: consecutiveFrameCount]
    // Positive = consecutive true frames, negative = consecutive false frames
    private var hysteresisCounters: [String: Int] = [
        "spe": 0, "sps": 0, "pds": 0, "pus": 0,
        "dse": 0, "use": 0, "nspf": 0
    ]
    // Latched (smoothed) boolean values
    private var latchedBools: [String: Bool] = [
        "spe": false, "sps": false, "pds": false, "pus": false,
        "dse": false, "use": false, "nspf": true
    ]

    // MARK: - Lifecycle

    /// Call once to start the ARSession with LiDAR depth.
    func start() {
        guard ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else {
            print("[LiDAR] This device does NOT support sceneDepth (needs LiDAR hardware)")
            return
        }

        let config = ARWorldTrackingConfiguration()
        config.frameSemantics = .sceneDepth
        session.delegate = self
        session.run(config)
        print("[LiDAR] ARSession started with smoothedSceneDepth (8×8 grid)")
    }

    func stop() {
        session.pause()
        print("[LiDAR] ARSession paused")
    }

    private override init() {
        super.init()
    }
}

// MARK: - ARSessionDelegate

extension LiDARManager: ARSessionDelegate {

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let now = frame.timestamp

        // Throttle analysis
        guard now - lastAnalysisTime >= analysisInterval else { return }
        lastAnalysisTime = now

        // Prefer smoothedSceneDepth; fall back to sceneDepth
        guard let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth else { return }
        let depthMap = depthData.depthMap  // CVPixelBuffer, Float32, 256×192
        let confidenceMap = depthData.confidenceMap  // CVPixelBuffer?, UInt8, 256×192

        let grid = buildGrid(from: depthMap)
        self.depthGrid = grid

        // B2: Full-resolution hazard analysis
        let analysis = analyzeHazards(frame: frame, depthMap: depthMap, confidenceMap: confidenceMap)
        self.latestAnalysis = analysis

        // Notify UI on main thread
        DispatchQueue.main.async { [weak self] in
            self?.onGridUpdate?(grid)
            self?.onHazardUpdate?(analysis)
        }

        // Console log (throttled separately)
        if now - lastLogTime >= logInterval {
            lastLogTime = now
            printGrid(grid)
            printAnalysis(analysis)
        }
    }
}

// MARK: - Grid computation

extension LiDARManager {

    /// Build a 16×16 grid from the depth map. Each cell = percentile-10 depth.
    /// Portrait rotation: display row ↔ buffer x-axis, display col ↔ buffer y-axis.
    private func buildGrid(from depthMap: CVPixelBuffer) -> [[Float]] {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let bufW = CVPixelBufferGetWidth(depthMap)    // 256
        let bufH = CVPixelBufferGetHeight(depthMap)    // 192
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            return depthGrid
        }

        let floatBuffer = baseAddress.assumingMemoryBound(to: Float32.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let floatsPerRow = bytesPerRow / MemoryLayout<Float32>.size

        let rows = LiDARManager.gridRows   // 16
        let cols = LiDARManager.gridCols   // 16
        // Forward crop: only use the forward portion of buffer x range
        let usableX = Int(Float(bufW) * forwardCropRatio)  // e.g. 256*0.75 = 192
        let pxPerRow = max(1, usableX / rows)  // e.g. 192/16 = 12
        let pxPerCol = LiDARManager.cellPixelsY  // 12 px along buffer y → display col

        var grid = Array(repeating: Array(repeating: Float.greatestFiniteMagnitude, count: cols), count: rows)

        for row in 0..<rows {
            for col in 0..<cols {
                // Map: display row → buffer x, display col → buffer y (mirrored L↔R)
                let bxStart = row * pxPerRow
                let byStart = (cols - 1 - col) * pxPerCol  // mirror columns

                var cellDepths: [Float] = []
                cellDepths.reserveCapacity(pxPerRow * pxPerCol)

                for bx in bxStart..<min(bxStart + pxPerRow, bufW) {
                    for by in byStart..<min(byStart + pxPerCol, bufH) {
                        let d = floatBuffer[by * floatsPerRow + bx]
                        if d > 0 && !d.isNaN && !d.isInfinite {
                            cellDepths.append(d)
                        }
                    }
                }

                if cellDepths.isEmpty {
                    grid[row][col] = Float.greatestFiniteMagnitude
                } else {
                    // O(n) approximate percentile-10 using partitioning
                    grid[row][col] = Self.percentile10(&cellDepths)
                }
            }
        }

        return grid
    }

    /// O(n) approximate percentile-10 using partial selection.
    /// Much faster than full sort for 192-element arrays.
    private static func percentile10(_ arr: inout [Float]) -> Float {
        let k = max(0, Int(Float(arr.count) * 0.1))
        let target = min(k, arr.count - 1)
        // Use partial sort: only need the k-th smallest element
        // For small arrays (≤192), an insertion-based select is efficient
        if arr.count <= 1 { return arr[0] }
        // nth_element via introselect approximation: just partition once
        return kthSmallest(&arr, 0, arr.count - 1, target)
    }

    /// Quickselect to find k-th smallest element in O(n) average.
    private static func kthSmallest(_ arr: inout [Float], _ lo: Int, _ hi: Int, _ k: Int) -> Float {
        if lo == hi { return arr[lo] }

        // Median-of-three pivot
        let mid = lo + (hi - lo) / 2
        if arr[mid] < arr[lo] { arr.swapAt(lo, mid) }
        if arr[hi] < arr[lo] { arr.swapAt(lo, hi) }
        if arr[mid] < arr[hi] { arr.swapAt(mid, hi) }
        let pivot = arr[hi]

        var i = lo
        for j in lo..<hi {
            if arr[j] <= pivot {
                arr.swapAt(i, j)
                i += 1
            }
        }
        arr.swapAt(i, hi)

        if k == i {
            return arr[i]
        } else if k < i {
            return kthSmallest(&arr, lo, i - 1, k)
        } else {
            return kthSmallest(&arr, i + 1, hi, k)
        }
    }

    /// Print the 16×16 grid to console in a compact format.
    private func printGrid(_ grid: [[Float]]) {
        var output = "[LiDAR] 16×16 Depth Grid (p10, meters):\n"
        for row in 0..<grid.count {
            let cells = grid[row].map { val -> String in
                if val > 99 { return " -- " }
                return String(format: "%4.1f", val)
            }
            output += "  [\(cells.joined(separator: "|"))]\n"
        }
        print(output)
    }
}

// MARK: - B2 Hazard Analysis Pipeline

extension LiDARManager {

    /// Main entry: analyse full-resolution depth + camera pose → FrameAnalysisResult
    func analyzeHazards(frame: ARFrame, depthMap: CVPixelBuffer, confidenceMap: CVPixelBuffer?) -> FrameAnalysisResult {
        let camera = frame.camera
        let transform = camera.transform
        // camera.intrinsics is for capturedImage resolution; scale to depth map resolution
        let capturedW = Float(CVPixelBufferGetWidth(frame.capturedImage))
        let capturedH = Float(CVPixelBufferGetHeight(frame.capturedImage))
        let depthW = Float(CVPixelBufferGetWidth(depthMap))
        let depthH = Float(CVPixelBufferGetHeight(depthMap))
        let scaleX = depthW / capturedW
        let scaleY = depthH / capturedH
        var scaledIntrinsics = camera.intrinsics
        scaledIntrinsics[0][0] *= scaleX   // fx
        scaledIntrinsics[1][1] *= scaleY   // fy
        scaledIntrinsics[2][0] *= scaleX   // cx
        scaledIntrinsics[2][1] *= scaleY   // cy

        // Compute camera pitch for debug logging
        // Camera forward = -Z column of transform (column 2, negated)
        let fwd = -simd_float3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        lastCameraPitch = asin(fwd.y) * 180.0 / Float.pi  // +up, -down

        // Full resolution: use every depth pixel (with forward crop)
        let rows = Int(depthW * forwardCropRatio) // e.g. 256*0.75 = 192
        let cols = Int(depthH)                     // 192

        // ── Step A: Depth → World coordinates (full resolution + confidence filter) ──
        let (worldPoints, validMask) = projectToWorld(
            depthMap: depthMap, transform: transform,
            intrinsics: scaledIntrinsics, rows: rows, cols: cols,
            confidenceMap: confidenceMap
        )

        // Camera position for relative distance calculations
        let camPos = simd_float3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)

        // ── Step B: Distance-band ground Y estimation ──
        let bandGroundY = estimateBandGroundY(
            worldPoints: worldPoints, validMask: validMask,
            rows: rows, cols: cols, cameraPos: camPos,
            cameraPitch: lastCameraPitch ?? 0, timestamp: frame.timestamp
        )

        // ── Step C: Height classification (band-aware) ──
        let classification = classifyPoints(worldPoints: worldPoints, validMask: validMask,
                                             rows: rows, cols: cols,
                                             bandGroundY: bandGroundY, cameraPos: camPos)

        // ── Step E: Stairs detection ──
        let (rawUpStairs, rawDownStairs) = detectStairs(
            worldPoints: worldPoints, classification: classification,
            validMask: validMask, rows: rows, cols: cols, cameraPos: camPos
        )

        // ── Step F: Slope detection ──
        let (rawUpSlope, rawDownSlope) = detectSlope(
            worldPoints: worldPoints, classification: classification,
            validMask: validMask, rows: rows, cols: cols, cameraPos: camPos
        )

        // ── Step G: Angular free space map ──
        let freeDistance = computeFreeSpaceMap(
            worldPoints: worldPoints, classification: classification,
            validMask: validMask, rows: rows, cols: cols, cameraPos: camPos
        )

        // ── Step H: Safe path finding ──
        let (rawSPE, rawSPS, rawSPA, rawSPW, rawNSPF,
             rawNearDist, rawNearAngle, rawForwardNearDist, obstacles) = findSafePath(
            freeDistance: freeDistance, cols: cols,
            classification: classification, worldPoints: worldPoints,
            validMask: validMask, rows: rows
        )

        // ── Step I: Temporal smoothing ──
        let spe  = applyHysteresis(key: "spe",  rawValue: rawSPE)
        let sps  = applyHysteresis(key: "sps",  rawValue: rawSPS)
        let nspf = applyHysteresis(key: "nspf", rawValue: rawNSPF)
        let dse  = applyHysteresis(key: "dse",  rawValue: rawDownStairs)
        let use  = applyHysteresis(key: "use",  rawValue: rawUpStairs)
        let pds  = applyHysteresis(key: "pds",  rawValue: rawDownSlope)
        let pus  = applyHysteresis(key: "pus",  rawValue: rawUpSlope)

        // EMA smooth angle
        smoothedAngle = smoothedAngle * (1 - angleAlpha) + rawSPA * angleAlpha

        // Asymmetric EMA for nearest obstacle distance (fast approach, slow release)
        let distAlpha: Float = rawNearDist < smoothedNearestDist ? 0.7 : 0.3
        smoothedNearestDist = smoothedNearestDist * (1 - distAlpha) + rawNearDist * distAlpha

        return FrameAnalysisResult(
            safePathExist: spe,
            safePathStraight: sps,
            safePathAngle: smoothedAngle,
            safePathWidth: rawSPW,
            pathDownSlope: pds,
            pathUpSlope: pus,
            downStairsExist: dse,
            upStairsExist: use,
            noSafePathFound: nspf,
            nearestObstacleDistance: smoothedNearestDist,
            nearestObstacleAngle: rawNearAngle,
            nearestForwardDistance: rawForwardNearDist,
            groundY: bandGroundY[0],
            bandGroundY: bandGroundY,
            obstacles: obstacles
        )
    }

    // MARK: - Step A: World Coordinate Projection

    private func projectToWorld(
        depthMap: CVPixelBuffer, transform: simd_float4x4,
        intrinsics: simd_float3x3, rows: Int, cols: Int,
        confidenceMap: CVPixelBuffer?
    ) -> ([[simd_float3]], [[Bool]]) {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        if let conf = confidenceMap { CVPixelBufferLockBaseAddress(conf, .readOnly) }
        defer { if let conf = confidenceMap { CVPixelBufferUnlockBaseAddress(conf, .readOnly) } }

        let bufW = CVPixelBufferGetWidth(depthMap)    // 256
        let bufH = CVPixelBufferGetHeight(depthMap)    // 192
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            return (
                Array(repeating: Array(repeating: simd_float3(0, 0, 0), count: cols), count: rows),
                Array(repeating: Array(repeating: false, count: cols), count: rows)
            )
        }

        let floatBuffer = baseAddress.assumingMemoryBound(to: Float32.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let floatsPerRow = bytesPerRow / MemoryLayout<Float32>.size

        // Confidence map buffer (nil if unavailable)
        let confBuffer: UnsafeMutablePointer<UInt8>?
        let confBytesPerRow: Int
        if let conf = confidenceMap, let confBase = CVPixelBufferGetBaseAddress(conf) {
            confBuffer = confBase.assumingMemoryBound(to: UInt8.self)
            confBytesPerRow = CVPixelBufferGetBytesPerRow(conf)
        } else {
            confBuffer = nil
            confBytesPerRow = 0
        }

        // Intrinsics for depth map resolution
        let fx = intrinsics[0][0]
        let fy = intrinsics[1][1]
        let cx = intrinsics[2][0]
        let cy = intrinsics[2][1]

        let usableX = Int(Float(bufW) * forwardCropRatio) // e.g. 192
        let strideX = max(1, usableX / rows)    // 192/64 = 3
        let strideY = max(1, bufH / cols)       // 192/48 = 4

        var worldPoints = Array(repeating: Array(repeating: simd_float3(0, 0, 0), count: cols), count: rows)
        var validMask = Array(repeating: Array(repeating: false, count: cols), count: rows)

        for row in 0..<rows {
            let bx = row * strideX
            guard bx < bufW else { continue }
            for col in 0..<cols {
                // Mirror columns (same as buildGrid)
                let by = (cols - 1 - col) * strideY
                guard by < bufH else { continue }

                let d = floatBuffer[by * floatsPerRow + bx]
                guard d > 0 && !d.isNaN && !d.isInfinite && d < maxAnalysisRange else { continue }

                // Skip low-confidence pixels (ARConfidenceLevel: 0=low, 1=medium, 2=high)
                if let cb = confBuffer {
                    let confidence = cb[by * confBytesPerRow + bx]
                    guard confidence >= 1 else { continue }
                }

                // Unproject to camera coordinates
                // ARKit camera: +X right, +Y up, -Z forward
                // Image Y flipped vs camera Y → negative; depth along -Z → negative
                let x_cam = d * (Float(bx) - cx) / fx
                let y_cam = -d * (Float(by) - cy) / fy
                let z_cam = -d

                // Transform to world coordinates
                let camPoint = simd_float4(x_cam, y_cam, z_cam, 1.0)
                let wp = transform * camPoint

                worldPoints[row][col] = simd_float3(wp.x, wp.y, wp.z)
                validMask[row][col] = true
            }
        }

        return (worldPoints, validMask)
    }

    // MARK: - Step B: Distance-Band Ground Y Estimation

    // Distance band boundaries (meters from camera)
    private static let bandEdges: [Float] = [0.0, 1.5, 3.0, 5.0]  // 3 bands: near/mid/far
    private static let bandCount = 3
    private static let minBandPoints = 50  // minimum valid points per band for histogram

    private func estimateBandGroundY(
        worldPoints: [[simd_float3]], validMask: [[Bool]],
        rows: Int, cols: Int, cameraPos: simd_float3,
        cameraPitch: Float, timestamp: TimeInterval
    ) -> [Float] {
        // ── 1. Collect Y values per distance band ──
        var bandYValues: [[Float]] = Array(repeating: [], count: Self.bandCount)
        for i in 0..<Self.bandCount { bandYValues[i].reserveCapacity(rows * cols / 6) }

        for r in 0..<rows {
            for c in 0..<cols {
                guard validMask[r][c] else { continue }
                let pt = worldPoints[r][c]
                let dx = pt.x - cameraPos.x
                let dz = pt.z - cameraPos.z
                let hdist2 = dx * dx + dz * dz  // squared distance (avoid sqrt)
                // Band assignment: 0-1.5m → 0, 1.5-3.0m → 1, 3.0-5.0m → 2
                let band: Int
                if hdist2 < 2.25 {       // 1.5² = 2.25
                    band = 0
                } else if hdist2 < 9.0 { // 3.0² = 9.0
                    band = 1
                } else {
                    band = 2
                }
                bandYValues[band].append(pt.y)
            }
        }

        // ── 2. Histogram peak per band ──
        var rawBandGroundY: [Float?] = [nil, nil, nil]
        for b in 0..<Self.bandCount {
            rawBandGroundY[b] = histogramGroundY(yValues: bandYValues[b])
        }

        // ── 3. Fallback: if a band has too few points, inherit from neighbour ──
        // Near band fallback: cameraY - 1.2m
        if rawBandGroundY[0] == nil {
            rawBandGroundY[0] = rawBandGroundY[1] ?? rawBandGroundY[2] ?? (cameraPos.y - 1.2)
        }
        if rawBandGroundY[1] == nil {
            rawBandGroundY[1] = rawBandGroundY[0]
        }
        if rawBandGroundY[2] == nil {
            rawBandGroundY[2] = rawBandGroundY[1]
        }

        let newBandGY = rawBandGroundY.map { $0! }

        // ── 4. Pose-aware dynamic EMA alpha ──
        var alpha = groundYAlpha  // base 0.1
        if let prev = poseHistory.last {
            let deltaPitch = abs(cameraPitch - prev.cameraPitch)
            let deltaCamY = abs(cameraPos.y - prev.cameraY)
            let deltaGY0 = abs(newBandGY[0] - prev.bandGroundY[0])

            // Large pitch change → histogram sampling unstable → be conservative
            if deltaPitch > 10.0 {
                alpha *= 0.5
            }
            // Ground Y jumped but camera didn't move much → suspicious noise → very conservative
            if deltaGY0 > 0.10 && deltaCamY < 0.03 {
                alpha *= 0.3
            }
        }

        // ── 5. Per-band EMA smoothing ──
        var result: [Float] = [0, 0, 0]
        for b in 0..<Self.bandCount {
            if let prev = smoothedBandGroundY[b] {
                result[b] = prev * (1 - alpha) + newBandGY[b] * alpha
            } else {
                result[b] = newBandGY[b]
            }
            smoothedBandGroundY[b] = result[b]
        }

        // ── 6. Store pose snapshot (keep last 10) ──
        poseHistory.append(PoseSnapshot(
            cameraY: cameraPos.y, cameraPitch: cameraPitch,
            bandGroundY: result, timestamp: timestamp
        ))
        if poseHistory.count > 10 { poseHistory.removeFirst() }

        return result
    }

    /// Histogram peak-finding for a single band's Y values.
    /// Returns nil if too few points.
    private func histogramGroundY(yValues: [Float]) -> Float? {
        guard yValues.count >= Self.minBandPoints else { return nil }

        let binSize: Float = 0.05
        let minY = yValues.min()!
        let maxY = yValues.max()!
        let range = maxY - minY
        guard range > 0 else { return yValues[0] }

        let numBins = max(1, Int(range / binSize) + 1)
        var histogram = Array(repeating: 0, count: numBins)

        for y in yValues {
            let bin = min(numBins - 1, max(0, Int((y - minY) / binSize)))
            histogram[bin] += 1
        }

        // Find peak in lowest 30% of Y range (ground = lowest dense cluster)
        let searchBins = max(1, numBins * 30 / 100)
        var bestBin = 0
        var bestCount = 0
        for i in 0..<searchBins {
            if histogram[i] > bestCount {
                bestCount = histogram[i]
                bestBin = i
            }
        }

        return minY + (Float(bestBin) + 0.5) * binSize
    }

    // MARK: - Step C: Height Classification

    private func classifyPoints(
        worldPoints: [[simd_float3]], validMask: [[Bool]],
        rows: Int, cols: Int, bandGroundY: [Float], cameraPos: simd_float3
    ) -> [[PointClassification]] {
        var cls = Array(repeating: Array(repeating: PointClassification.invalid, count: cols), count: rows)

        for r in 0..<rows {
            for c in 0..<cols {
                guard validMask[r][c] else { continue }
                let pt = worldPoints[r][c]
                let dx = pt.x - cameraPos.x
                let dz = pt.z - cameraPos.z
                let hdist2 = dx * dx + dz * dz
                let band = hdist2 < 2.25 ? 0 : (hdist2 < 9.0 ? 1 : 2)
                let h = pt.y - bandGroundY[band]

                if h < dropSevereThreshold {
                    cls[r][c] = .dropSevere
                } else if h < dropMildThreshold {
                    cls[r][c] = .dropMild
                } else if h >= -groundTolerance && h <= groundTolerance {
                    cls[r][c] = .ground
                } else if h > groundTolerance && h < tripHazardHeight {
                    cls[r][c] = .tripHazard
                } else if h >= tripHazardHeight && h < 0.50 {
                    cls[r][c] = .obstacleLow
                } else if h >= 0.50 && h < 1.50 {
                    cls[r][c] = .obstacleMid
                } else if h >= 1.50 {
                    cls[r][c] = .obstacleHigh
                } else {
                    cls[r][c] = .ground // fallback for small negative
                }
            }
        }

        return cls
    }

    // MARK: - Step E: Stairs Detection

    private func detectStairs(
        worldPoints: [[simd_float3]], classification: [[PointClassification]],
        validMask: [[Bool]], rows: Int, cols: Int, cameraPos: simd_float3
    ) -> (upStairs: Bool, downStairs: Bool) {
        var upStairs = false
        var downStairs = false

        // Scan central ±10° (column range scales with resolution)
        let centerCol = cols / 2
        let stairScanCols = max(10, cols * 10 / 48) // ±10 cols @48 → ±40 cols @192
        let scanStart = max(0, centerCol - stairScanCols)
        let scanEnd = min(cols, centerCol + stairScanCols)

        for col in scanStart..<scanEnd {
            // Collect (worldY, worldZ forward distance) for ground-ish points
            var yzPairs: [(y: Float, z: Float)] = []
            for row in 0..<rows {
                guard validMask[row][col] else { continue }
                let cls = classification[row][col]
                if cls == .ground || cls == .tripHazard || cls == .obstacleLow {
                    let pt = worldPoints[row][col]
                    // horizontal distance from camera (not world origin)
                    let dx = pt.x - cameraPos.x
                    let dz = pt.z - cameraPos.z
                    let hdist = sqrtf(dx * dx + dz * dz)
                    yzPairs.append((y: pt.y, z: hdist))
                }
            }

            guard yzPairs.count >= stairMinSteps + 1 else { continue }

            // Sort by distance (near to far)
            yzPairs.sort { $0.z < $1.z }

            // Look for step pattern: jumps in Y between consecutive distance-sorted points
            var stepDeltas: [Float] = []
            var prevY = yzPairs[0].y
            for i in 1..<yzPairs.count {
                let deltaY = yzPairs[i].y - prevY
                let deltaZ = yzPairs[i].z - yzPairs[i - 1].z
                // Only consider significant Y jumps with some forward distance
                if abs(deltaY) >= stairStepHeightMin && abs(deltaY) <= stairStepHeightMax
                    && deltaZ > 0.05 {
                    stepDeltas.append(deltaY)
                }
                prevY = yzPairs[i].y
            }

            if stepDeltas.count >= stairMinSteps {
                // Check consistency: all deltas same sign
                let positiveCount = stepDeltas.filter { $0 > 0 }.count
                let negativeCount = stepDeltas.filter { $0 < 0 }.count

                if positiveCount >= stairMinSteps {
                    upStairs = true
                }
                if negativeCount >= stairMinSteps {
                    downStairs = true
                }
            }
        }

        return (upStairs, downStairs)
    }

    // MARK: - Step F: Slope Detection

    private func detectSlope(
        worldPoints: [[simd_float3]], classification: [[PointClassification]],
        validMask: [[Bool]], rows: Int, cols: Int, cameraPos: simd_float3
    ) -> (upSlope: Bool, downSlope: Bool) {
        // Collect GROUND-only points from central ±5° (column range scales with resolution)
        let centerCol = cols / 2
        let slopeScanCols = max(5, cols * 5 / 48) // ±5 cols @48 → ±20 cols @192
        let scanStart = max(0, centerCol - slopeScanCols)
        let scanEnd = min(cols, centerCol + slopeScanCols)

        var forwardDists: [Float] = []
        var heights: [Float] = []

        for col in scanStart..<scanEnd {
            for row in 0..<rows {
                guard validMask[row][col], classification[row][col] == .ground else { continue }
                let pt = worldPoints[row][col]
                let dx = pt.x - cameraPos.x
                let dz = pt.z - cameraPos.z
                let hdist = sqrtf(dx * dx + dz * dz)
                forwardDists.append(hdist)
                heights.append(pt.y)
            }
        }

        // Need enough points for meaningful regression
        guard forwardDists.count >= 30 else { return (false, false) }

        // Ground points must span at least 1.0m of horizontal distance
        let minDist = forwardDists.min()!
        let maxDist = forwardDists.max()!
        guard maxDist - minDist >= 1.0 else { return (false, false) }

        // Simple linear regression: Y = a * dist + b
        let n = Float(forwardDists.count)
        let sumX = forwardDists.reduce(0, +)
        let sumY = heights.reduce(0, +)
        var sumXY: Float = 0
        var sumX2: Float = 0
        for i in 0..<forwardDists.count {
            sumXY += forwardDists[i] * heights[i]
            sumX2 += forwardDists[i] * forwardDists[i]
        }

        let denomX = n * sumX2 - sumX * sumX
        guard abs(denomX) > 1e-6 else { return (false, false) }

        let a = (n * sumXY - sumX * sumY) / denomX  // slope coefficient
        let b = (sumY - a * sumX) / n

        // Compute R² — reject low-quality fits (noise, not a real slope)
        let meanY = sumY / n
        var ssTot: Float = 0
        var ssRes: Float = 0
        for i in 0..<forwardDists.count {
            let predicted = a * forwardDists[i] + b
            ssRes += (heights[i] - predicted) * (heights[i] - predicted)
            ssTot += (heights[i] - meanY) * (heights[i] - meanY)
        }

        let rSquared = ssTot > 1e-6 ? 1.0 - ssRes / ssTot : 0
        // Only report slope if the linear fit actually explains the data well
        guard rSquared > 0.5 else { return (false, false) }

        let slopeAngleDeg = atan(a) * 180.0 / Float.pi

        let upSlope = slopeAngleDeg > slopeAngleThreshold
        let downSlope = slopeAngleDeg < -slopeAngleThreshold

        return (upSlope, downSlope)
    }

    // MARK: - Step G: Angular Free Space Map

    private func computeFreeSpaceMap(
        worldPoints: [[simd_float3]], classification: [[PointClassification]],
        validMask: [[Bool]], rows: Int, cols: Int, cameraPos: simd_float3
    ) -> [Float] {
        var freeDistance = Array(repeating: maxAnalysisRange, count: cols)

        for col in 0..<cols {
            var minDist = maxAnalysisRange

            for row in 0..<rows {
                guard validMask[row][col] else { continue }
                let cls = classification[row][col]

                // Blocking classifications
                let isBlocking = (cls == .obstacleLow || cls == .obstacleMid
                                  || cls == .obstacleHigh || cls == .dropSevere)
                guard isBlocking else { continue }

                let pt = worldPoints[row][col]
                let dx = pt.x - cameraPos.x
                let dz = pt.z - cameraPos.z
                let hdist = sqrtf(dx * dx + dz * dz)
                minDist = min(minDist, hdist)
            }

            freeDistance[col] = minDist
        }

        return freeDistance
    }

    // MARK: - Step H: Safe Path Finding

    private func findSafePath(
        freeDistance: [Float], cols: Int,
        classification: [[PointClassification]], worldPoints: [[simd_float3]],
        validMask: [[Bool]], rows: Int
    ) -> (spe: Bool, sps: Bool, spa: Float, spw: Float, nspf: Bool,
          nearDist: Float, nearAngle: Float, forwardNearDist: Float,
          obstacles: [ObstacleCluster]) {

        let centerCol = Float(cols) / 2.0 - 0.5  // 23.5 for 48 cols

        // Approximate horizontal FOV from depth buffer (portrait mode, 192px height ≈ 46°)
        let hFOVDeg: Float = 46.0
        let hFOVRad: Float = hFOVDeg * Float.pi / 180.0
        let angPerCol: Float = hFOVDeg / Float(cols) // ≈ 0.96°

        // ── Mark safe columns ──
        var safeCols = Array(repeating: false, count: cols)
        for c in 0..<cols {
            safeCols[c] = freeDistance[c] >= minSafeDistance
        }

        // ── Find contiguous safe corridors ──
        struct Corridor {
            let startCol: Int
            let endCol: Int
            var numCols: Int { endCol - startCol + 1 }
            var centerCol: Float { Float(startCol + endCol) / 2.0 }
        }

        var corridors: [Corridor] = []
        var runStart: Int? = nil
        for c in 0..<cols {
            if safeCols[c] {
                if runStart == nil { runStart = c }
            } else {
                if let start = runStart {
                    corridors.append(Corridor(startCol: start, endCol: c - 1))
                    runStart = nil
                }
            }
        }
        if let start = runStart {
            corridors.append(Corridor(startCol: start, endCol: cols - 1))
        }

        // ── Compute physical width for each corridor ──
        struct ScoredCorridor {
            let corridor: Corridor
            let physicalWidth: Float
            let minFreeDist: Float
        }

        var scored: [ScoredCorridor] = []
        for c in corridors {
            var minFD = maxAnalysisRange
            for col in c.startCol...c.endCol {
                minFD = min(minFD, freeDistance[col])
            }
            let angWidthRad = Float(c.numCols) * hFOVRad / Float(cols)
            let width = 2.0 * minFD * tan(angWidthRad / 2.0)
            scored.append(ScoredCorridor(corridor: c, physicalWidth: width, minFreeDist: minFD))
        }

        // Filter passable corridors (width >= safeWidthConstant)
        let passable = scored.filter { $0.physicalWidth >= safeWidthConstant }

        // ── Nearest obstacle info (global) ──
        var globalNearDist = maxAnalysisRange
        var globalNearCol = cols / 2
        for c in 0..<cols {
            if freeDistance[c] < globalNearDist {
                globalNearDist = freeDistance[c]
                globalNearCol = c
            }
        }
        let nearAngle = (Float(globalNearCol) - centerCol) * angPerCol

        // ── Forward cone (±15°) nearest obstacle for P0 gating ──
        let forwardConeHalfDeg: Float = 15.0
        let forwardColSpan = Int(forwardConeHalfDeg / angPerCol)
        let fwdStart = max(0, Int(centerCol) - forwardColSpan)
        let fwdEnd = min(cols - 1, Int(centerCol) + forwardColSpan)
        var forwardNearDist = maxAnalysisRange
        for c in fwdStart...fwdEnd {
            forwardNearDist = min(forwardNearDist, freeDistance[c])
        }

        // ── Build obstacle clusters from blocked column groups ──
        var obstacleList: [ObstacleCluster] = []
        var blockStart: Int? = nil
        for c in 0..<cols {
            if !safeCols[c] {
                if blockStart == nil { blockStart = c }
            } else {
                if let bs = blockStart {
                    let be = c - 1
                    let ctrCol = Float(bs + be) / 2.0
                    let angle = (ctrCol - centerCol) * angPerCol
                    var minD = maxAnalysisRange
                    for bc in bs...be {
                        minD = min(minD, freeDistance[bc])
                    }
                    let numC = be - bs + 1
                    let angWidth = Float(numC) * angPerCol
                    let phyWidth = 2.0 * minD * tan(angWidth * Float.pi / 360.0)

                    // Classify obstacle type
                    let oType = classifyObstacleType(
                        cols: bs...be, classification: classification,
                        validMask: validMask, rows: rows, angWidth: angWidth
                    )

                    obstacleList.append(ObstacleCluster(
                        centerAngle: angle, distance: minD,
                        angularWidth: angWidth, physicalWidth: phyWidth, type: oType
                    ))
                    blockStart = nil
                }
            }
        }
        if let bs = blockStart {
            let be = cols - 1
            let ctrCol = Float(bs + be) / 2.0
            let angle = (ctrCol - centerCol) * angPerCol
            var minD = maxAnalysisRange
            for bc in bs...be { minD = min(minD, freeDistance[bc]) }
            let numC = be - bs + 1
            let angWidth = Float(numC) * angPerCol
            let phyWidth = 2.0 * minD * tan(angWidth * Float.pi / 360.0)
            let oType = classifyObstacleType(
                cols: bs...be, classification: classification,
                validMask: validMask, rows: rows, angWidth: angWidth
            )
            obstacleList.append(ObstacleCluster(
                centerAngle: angle, distance: minD,
                angularWidth: angWidth, physicalWidth: phyWidth, type: oType
            ))
        }

        // ── Select best corridor ──
        if passable.isEmpty {
            // Best-effort: find widest gap (even < 0.8m) for degraded steering
            var bestEffortAngle: Float = 0
            var bestEffortWidth: Float = 0
            if let widest = scored.max(by: { $0.physicalWidth < $1.physicalWidth }) {
                bestEffortAngle = (widest.corridor.centerCol - centerCol) * angPerCol
                bestEffortWidth = widest.physicalWidth
            }
            return (spe: false, sps: false, spa: bestEffortAngle, spw: bestEffortWidth,
                    nspf: true, nearDist: globalNearDist, nearAngle: nearAngle,
                    forwardNearDist: forwardNearDist, obstacles: obstacleList)
        }

        // Prefer corridor containing center (straight ahead)
        let centerCorridors = passable.filter {
            $0.corridor.startCol <= Int(centerCol) && $0.corridor.endCol >= Int(centerCol)
        }

        let best: ScoredCorridor
        let isStraight: Bool

        if let centerBest = centerCorridors.max(by: { $0.physicalWidth < $1.physicalWidth }) {
            best = centerBest
            isStraight = true
        } else {
            // Pick widest, tie-break by closest to center
            best = passable.sorted {
                if abs($0.physicalWidth - $1.physicalWidth) > 0.1 {
                    return $0.physicalWidth > $1.physicalWidth
                }
                return abs($0.corridor.centerCol - centerCol) < abs($1.corridor.centerCol - centerCol)
            }.first!
            isStraight = false
        }

        let bestAngle = (best.corridor.centerCol - centerCol) * angPerCol

        return (spe: true, sps: isStraight, spa: bestAngle,
                spw: best.physicalWidth, nspf: false,
                nearDist: globalNearDist, nearAngle: nearAngle,
                forwardNearDist: forwardNearDist, obstacles: obstacleList)
    }

    // MARK: - Obstacle Type Classification Helper

    private func classifyObstacleType(
        cols colRange: ClosedRange<Int>, classification: [[PointClassification]],
        validMask: [[Bool]], rows: Int, angWidth: Float
    ) -> ObstacleType {
        var countHigh = 0, countMid = 0, countLow = 0, countDrop = 0, total = 0

        for c in colRange {
            for r in 0..<rows {
                guard validMask[r][c] else { continue }
                let cls = classification[r][c]
                switch cls {
                case .obstacleHigh: countHigh += 1
                case .obstacleMid:  countMid += 1
                case .obstacleLow:  countLow += 1
                case .dropSevere, .dropMild: countDrop += 1
                default: break
                }
                total += 1
            }
        }

        guard total > 0 else { return .lowObstacle }

        if countDrop > countHigh + countMid + countLow {
            return .dropOff
        }
        if angWidth < 5.0 && (countHigh + countMid) > 0 {
            return .pole
        }
        if countHigh + countMid > total / 3 {
            return .wall
        }
        if countLow > 0 && countHigh + countMid == 0 {
            if Float(countLow) / Float(total) < 0.3 {
                return .tripHazard
            }
            return .lowObstacle
        }
        return .lowObstacle
    }

    // MARK: - Temporal Smoothing Helpers

    private func applyHysteresis(key: String, rawValue: Bool) -> Bool {
        var counter = hysteresisCounters[key] ?? 0
        let currentLatched = latchedBools[key] ?? false

        if rawValue {
            counter = max(1, counter + 1)
        } else {
            counter = min(-1, counter - 1)
        }
        hysteresisCounters[key] = counter

        if !currentLatched && counter >= boolHysteresisOn {
            latchedBools[key] = true
            return true
        } else if currentLatched && counter <= -boolHysteresisOff {
            latchedBools[key] = false
            return false
        }

        return currentLatched
    }

    // MARK: - Console Logging

    private func printAnalysis(_ a: FrameAnalysisResult) {
        var flags: [String] = []
        if a.safePathExist     { flags.append("SPE") }
        if a.safePathStraight  { flags.append("SPS") }
        if a.noSafePathFound   { flags.append("NSPF") }
        if a.upStairsExist     { flags.append("USE") }
        if a.downStairsExist   { flags.append("DSE") }
        if a.pathUpSlope       { flags.append("PUS") }
        if a.pathDownSlope     { flags.append("PDS") }

        let flagStr = flags.isEmpty ? "none" : flags.joined(separator: " ")
        let angleStr = String(format: "%+.1f°", a.safePathAngle)
        let widthStr = String(format: "%.2fm", a.safePathWidth)
        let nearStr  = String(format: "%.2fm@%+.0f°", a.nearestObstacleDistance, a.nearestObstacleAngle)
        let gY = a.bandGroundY
        let groundStr = String(format: "gY=[%.2f|%.2f|%.2f]", gY[0], gY[1], gY[2])

        // Log camera pitch for verifying tilt-aware behaviour
        let pitchStr: String
        if let pitch = lastCameraPitch {
            pitchStr = String(format: " pitch=%.0f°", pitch)
        } else {
            pitchStr = ""
        }

        print("[B2] flags=[\(flagStr)] angle=\(angleStr) width=\(widthStr) near=\(nearStr) \(groundStr) obs=\(a.obstacles.count)\(pitchStr)")
    }
}
